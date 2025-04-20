Okay, let's refine the script based on your latest requirements.
 * Global Scan for App IDs: We'll scan the BASE_PATH for all directories matching the date pattern to find every unique AppCode_Country combination ever present.
 * base_path Label: Will be added to all metrics.
 * New Metric (Processing Duration): We'll add app_dir_processing_duration_seconds. Calculating this as last_modification_time - creation_time is problematic due to the unreliability of creation time (stat -c %W) on many Linux filesystems.
   * Implementation: We will attempt to calculate stat -c %Y (Last Mod) - stat -c %W (Birth). Crucially, if %W returns 0 (common when unsupported) or the stat command fails, we will report 0 for this duration metric and add an error="birth_time_unavailable" tag to that specific metric instance. This makes the metric available where possible but clearly indicates when it's not reliable.
   * Alternative/Additional Metric: As a potentially more robust measure of activity duration within the directory, I'll also add app_dir_file_activity_span_seconds (Newest File Mod Time - Oldest File Mod Time). This requires two potentially slow find operations.
Revised Script:
#!/bin/bash

# --- Configuration ---
BASE_PATH="/opt" # Base directory where YYYY-MM-DD_AppCode_Country dirs reside
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector" # node_exporter's textfile dir
# Optional: Set to true to enable potentially slow file span metric
ENABLE_FILE_SPAN_METRIC=true
# --- End Configuration ---

# --- Safety Checks ---
if [ ! -d "$BASE_PATH" ]; then
  echo "ERROR: Base path $BASE_PATH does not exist or is not a directory." >&2
  exit 1
fi
if ! mkdir -p "$TEXTFILE_DIR"; then
  echo "ERROR: Cannot create or access textfile directory: $TEXTFILE_DIR" >&2
  exit 1
fi

# Output file
OUTPUT_FILE="${TEXTFILE_DIR}/app_opt_dirs_global_scan.prom"
TMP_OUTPUT_FILE="${OUTPUT_FILE}.tmp.$$" # Temporary file for atomic write

# --- Helper Function to Generate Metrics ---
# Arguments: $1=full_dir_path, $2=app_id, $3=dir_inherent_date, $4=base_path
generate_metrics() {
    local full_path="$1"
    local app_id="$2"
    local dir_inherent_date="$3" # Date associated with the directory itself
    local base_path_label_val="$4"
    local metrics=""
    # Add base_path to labels
    local labels="app_id=\"${app_id}\",base_path=\"${base_path_label_val}\""
    local now_ts stat_output mod_time_ts birth_time_ts start_of_day_ts \
          proc_duration size_output file_count time_since_mod mod_secs_since_start \
          oldest_file_ts newest_file_ts file_span \
          stat_exit du_exit find_exit date_exit find_oldest_exit find_newest_exit

    now_ts=$(date +%s)

    # Get modification time (%Y) and birth time (%W) using stat
    # Use a format string to get both in one go, handle potential errors
    stat_output=$(stat -c '%Y %W' "$full_path" 2>/dev/null)
    stat_exit=$?

    if [ $stat_exit -eq 0 ]; then
        # shellcheck disable=SC2086 # We expect word splitting here
        set -- $stat_output
        mod_time_ts=${1:-0}
        birth_time_ts=${2:-0} # Will be 0 if birth time is unsupported

        # Metric: Last Mod Timestamp
        metrics+="# HELP app_dir_last_modified_timestamp_seconds Last modification time of the most recent directory for the App ID (Unix Timestamp).\n"
        metrics+="# TYPE app_dir_last_modified_timestamp_seconds gauge\n"
        metrics+="app_dir_last_modified_timestamp_seconds{${labels}} ${mod_time_ts}\n"

        # Metric: Time Since Last Modification
        time_since_mod=$((now_ts - mod_time_ts))
        metrics+="# HELP app_dir_time_since_last_modified_seconds Seconds since the most recent directory for the App ID was last modified.\n"
        metrics+="# TYPE app_dir_time_since_last_modified_seconds gauge\n"
        metrics+="app_dir_time_since_last_modified_seconds{${labels}} ${time_since_mod}\n"

        # Metric: Seconds Since Day Start (using the dir's inherent date)
        start_of_day_ts=$(date +%s -d "${dir_inherent_date} 00:00:00")
        date_exit=$?
        if [ $date_exit -eq 0 ]; then
            mod_secs_since_start=$((mod_time_ts - start_of_day_ts))
            metrics+="# HELP app_dir_last_modified_seconds_since_day_start Seconds from 00:00:00 of the directory's date to its last modification.\n"
            metrics+="# TYPE app_dir_last_modified_seconds_since_day_start gauge\n"
            metrics+="app_dir_last_modified_seconds_since_day_start{${labels}} ${mod_secs_since_start}\n"
        else
            echo "WARN: Could not calculate start_of_day_ts for ${dir_inherent_date} (App ID: ${app_id})" >&2
            # Omit if date calc fails
        fi

        # NEW Metric: Processing Duration (Mod Time - Birth Time)
        metrics+="# HELP app_dir_processing_duration_seconds Processing duration based on directory metadata (Last Mod Time - Birth Time). Caution: Birth time may be unavailable.\n"
        metrics+="# TYPE app_dir_processing_duration_seconds gauge\n"
        if [ "$birth_time_ts" -ne 0 ]; then
            proc_duration=$((mod_time_ts - birth_time_ts))
             # Handle potential negative duration if clock changed or birth time > mod time (unlikely but possible)
             if [ "$proc_duration" -lt 0 ]; then proc_duration=0; fi
            metrics+="app_dir_processing_duration_seconds{${labels}} ${proc_duration}\n"
        else
            # Birth time is 0 (unavailable/unsupported) or stat failed before
            metrics+="app_dir_processing_duration_seconds{${labels},error=\"birth_time_unavailable\"} 0\n"
        fi

    else
        # Stat failed completely
        echo "WARN: Failed to stat directory ${full_path} (App ID: ${app_id})" >&2
        # Report 0 for timestamp and related metrics, with error label
        metrics+="# HELP app_dir_last_modified_timestamp_seconds Last modification time of the most recent directory for the App ID (Unix Timestamp).\n"
        metrics+="# TYPE app_dir_last_modified_timestamp_seconds gauge\n"
        metrics+="app_dir_last_modified_timestamp_seconds{${labels},error=\"stat_failed\"} 0\n"
        metrics+="# HELP app_dir_time_since_last_modified_seconds Seconds since the most recent directory for the App ID was last modified.\n"
        metrics+="# TYPE app_dir_time_since_last_modified_seconds gauge\n"
        metrics+="app_dir_time_since_last_modified_seconds{${labels},error=\"stat_failed\"} 0\n"
        metrics+="# HELP app_dir_last_modified_seconds_since_day_start Seconds from 00:00:00 of the directory's date to its last modification.\n"
        metrics+="# TYPE app_dir_last_modified_seconds_since_day_start gauge\n"
        metrics+="app_dir_last_modified_seconds_since_day_start{${labels},error=\"stat_failed\"} 0\n"
        metrics+="# HELP app_dir_processing_duration_seconds Processing duration based on directory metadata (Last Mod Time - Birth Time). Caution: Birth time may be unavailable.\n"
        metrics+="# TYPE app_dir_processing_duration_seconds gauge\n"
        metrics+="app_dir_processing_duration_seconds{${labels},error=\"stat_failed\"} 0\n"

    fi

    # Metric: Size
    # shellcheck disable=SC2046
    set -- $(du -sb "$full_path" 2>/dev/null)
    du_exit=$?
    size_output=${1:-0}
    metrics+="# HELP app_dir_size_bytes Total size in bytes of the most recent directory for the App ID.\n"
    metrics+="# TYPE app_dir_size_bytes gauge\n"
    if [ $du_exit -eq 0 ]; then
        metrics+="app_dir_size_bytes{${labels}} ${size_output}\n"
    else
        echo "WARN: Failed to get size for directory ${full_path} (App ID: ${app_id})" >&2
        metrics+="app_dir_size_bytes{${labels},error=\"du_failed\"} 0\n"
    fi

    # Metric: File Count
    file_count=$(find "$full_path" -maxdepth 10 -type f 2>/dev/null | wc -l) # Added maxdepth for safety
    find_exit=$?
    metrics+="# HELP app_dir_files_count Total number of files in the most recent directory for the App ID.\n"
    metrics+="# TYPE app_dir_files_count gauge\n"
    if [ $find_exit -eq 0 ]; then
        metrics+="app_dir_files_count{${labels}} ${file_count}\n"
    else
        echo "WARN: Failed to count files for directory ${full_path} (App ID: ${app_id})" >&2
        metrics+="app_dir_files_count{${labels},error=\"find_failed\"} 0\n"
    fi

    # Optional NEW Metric: File Activity Span (Newest File Mod Time - Oldest File Mod Time)
    if [[ "$ENABLE_FILE_SPAN_METRIC" == "true" ]]; then
        metrics+="# HELP app_dir_file_activity_span_seconds Timespan between oldest and newest file modification times within the directory.\n"
        metrics+="# TYPE app_dir_file_activity_span_seconds gauge\n"
        # Need to run find twice, can be slow
        oldest_file_ts=$(find "$full_path" -maxdepth 10 -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1)
        find_oldest_exit=$?
        newest_file_ts=$(find "$full_path" -maxdepth 10 -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -1)
        find_newest_exit=$?

        if [[ $find_oldest_exit -eq 0 && $find_newest_exit -eq 0 && -n "$oldest_file_ts" && -n "$newest_file_ts" ]]; then
            # Convert timestamps to integers (remove potential decimals from printf %T@)
            oldest_file_ts_int=${oldest_file_ts%.*}
            newest_file_ts_int=${newest_file_ts%.*}
            file_span=$((newest_file_ts_int - oldest_file_ts_int))
            if [ "$file_span" -lt 0 ]; then file_span=0; fi # Ensure non-negative
            metrics+="app_dir_file_activity_span_seconds{${labels}} ${file_span}\n"
        elif [[ $find_oldest_exit -ne 0 || $find_newest_exit -ne 0 ]]; then
             echo "WARN: Failed find command for file span in ${full_path} (App ID: ${app_id})" >&2
             metrics+="app_dir_file_activity_span_seconds{${labels},error=\"find_failed\"} 0\n"
        else
            # Find succeeded but returned no timestamps (e.g., directory has no files)
             metrics+="app_dir_file_activity_span_seconds{${labels},error=\"no_files\"} 0\n"
        fi
    fi


    # Output the generated metrics for this App ID
    printf "%s" "$metrics"
}

# --- Main Script Logic ---
script_start_ts=$(date +%s)
echo "INFO: Starting global directory scan at $(date)" >&2

# Clear temp file
> "$TMP_OUTPUT_FILE"

processed_app_ids=0
script_errors=0

# Step 1: Find all unique AppCode_Country identifiers globally
# Pattern: YYYY-MM-DD_AppCode_Country
unique_app_ids=$(find "$BASE_PATH" -maxdepth 1 -type d -regextype posix-extended -regex ".*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[^_]+_.+" -print0 2>/dev/null | while IFS= read -r -d $'\0' dir_path; do
    dir_name=$(basename "$dir_path")
    # Extract AppCode_Country part after the date and first underscore
    if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_(.*)$ ]]; then
        echo "${BASH_REMATCH[1]}" # Output AppCode_Country
    fi
done | sort -u)

# Check if find/sort operation produced output and was successful
if [ $? -ne 0 ]; then
      echo "ERROR: Failed during global find/sort operation to identify unique App IDs." >&2
      script_errors=$((script_errors + 1))
      unique_app_ids="" # Prevent loop from running on error
fi


# Step 2: Loop through each unique App ID and find its most recent directory
if [ -n "$unique_app_ids" ]; then
    echo "INFO: Found unique App IDs globally: ${unique_app_ids//$'\n'/ }" # Replace newlines with spaces for logging
    while IFS= read -r app_id; do
        # Find all directories for this specific app_id, sort by name (date), get the last one
        target_dir=$(find "$BASE_PATH" -maxdepth 1 -type d -name "*_${app_id}" -print0 2>/dev/null | xargs -0 ls -1td | head -n 1)
        find_target_exit=$?

        if [[ $find_target_exit -eq 0 && -n "$target_dir" && -d "$target_dir" ]]; then
             target_dir_name=$(basename "$target_dir")
            # Extract the date from the target directory name
             if [[ "$target_dir_name" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_.*$ ]]; then
                 target_date_for_calc="${BASH_REMATCH[1]}"
                 echo "INFO: Monitoring MOST RECENT directory for App ID ${app_id}: ${target_dir}" >&2
                 # Generate metrics using the most recent directory found
                 generate_metrics "$target_dir" "$app_id" "$target_date_for_calc" "$BASE_PATH" >> "$TMP_OUTPUT_FILE"
                 if [ $? -ne 0 ]; then script_errors=$((script_errors + 1)); fi
                 processed_app_ids=$((processed_app_ids + 1))
             else
                 echo "WARN: Could not parse date from most recent directory name for App ID ${app_id}: ${target_dir_name}" >&2
                 script_errors=$((script_errors + 1))
             fi
        elif [[ $find_target_exit -ne 0 ]]; then
             echo "ERROR: Failed find/ls operation for App ID ${app_id}" >&2
             script_errors=$((script_errors + 1))
        else
             # No directory found for this App ID at all
             echo "INFO: No directory found for App ID ${app_id} in ${BASE_PATH}" >&2
             # No metrics to generate for this app_id
        fi
    done <<< "$unique_app_ids" # Feed the unique IDs string into the loop
else
     echo "INFO: No App IDs found matching the pattern in ${BASE_PATH}." >&2
fi

echo "INFO: Processed ${processed_app_ids} App IDs." >&2

# Add script execution metrics
script_end_ts=$(date +%s)
script_duration=$((script_end_ts - script_start_ts))
script_success=1
if [ "$script_errors" -gt 0 ]; then
    script_success=0
    echo "ERROR: ${script_errors} errors encountered during script execution." >&2
fi

printf "# HELP app_dirs_global_monitor_script_success Indicates if the global monitor script ran without critical errors (1=success, 0=failure).\n" >> "$TMP_OUTPUT_FILE"
printf "# TYPE app_dirs_global_monitor_script_success gauge\n"
printf "app_dirs_global_monitor_script_success{} %d\n" "$script_success" >> "$TMP_OUTPUT_FILE"

printf "# HELP app_dirs_global_monitor_script_duration_seconds Time taken for the global monitor script to execute.\n" >> "$TMP_OUTPUT_FILE"
printf "# TYPE app_dirs_global_monitor_script_duration_seconds gauge\n"
printf "app_dirs_global_monitor_script_duration_seconds{} %d\n" "$script_duration" >> "$TMP_OUTPUT_FILE"

# Atomically move the temporary file to the final destination
if ! mv "$TMP_OUTPUT_FILE" "$OUTPUT_FILE"; then
  echo "ERROR: Failed to move temporary file to $OUTPUT_FILE" >&2
  # Clean up temp file if move fails
  rm -f "$TMP_OUTPUT_FILE"
  exit 1
fi

echo "INFO: Metrics successfully written to $OUTPUT_FILE at $(date)" >&2
exit 0

关键改动说明:
 * 全局 App ID 发现: 脚本现在使用 find 配合正则表达式扫描 BASE_PATH 下所有符合 YYYY-MM-DD_AppCode_Country 格式的目录，提取 AppCode_Country 部分并去重，得到所有出现过的 app_id 列表。
 * 查找最新目录: 对于每个唯一的 app_id，脚本再次使用 find 找到所有与之匹配的目录 (*_${app_id}), 然后通过 ls -1td 按修改时间排序（最新的在前）并用 head -n 1 取出最新的那个目录作为 target_dir。
 * base_path Label: generate_metrics 函数增加了第四个参数 base_path，并将其添加到了 labels 字符串中。
 * app_dir_processing_duration_seconds Metric:
   * 尝试使用 stat -c '%Y %W' 获取最后修改时间和出生时间。
   * 如果出生时间 (%W) 不为 0，则计算差值 (%Y - %W)。
   * 如果出生时间为 0 或 stat 失败，则输出 0 并添加 error="birth_time_unavailable" 或 error="stat_failed" 标签。
 * app_dir_file_activity_span_seconds Metric (Optional):
   * 通过 ENABLE_FILE_SPAN_METRIC=true 控制是否启用。
   * 使用两次 find ... -printf '%T@' 分别获取目录内文件最早和最晚的修改时间戳。
   * 计算两者之差。
   * 处理 find 命令失败或目录内无文件的情况。
请注意:
 * stat -c %W 的可靠性: 再次强调，目录的“出生时间”在很多常见 Linux 文件系统上可能不可用或为 0。app_dir_processing_duration_seconds 的值需要谨慎解读。
 * 性能: 全局扫描和为每个 app_id 查找最新目录（特别是 ls -td）以及计算文件活动时间跨度 (ENABLE_FILE_SPAN_METRIC=true 时）可能会在 BASE_PATH 下目录非常多或目录内文件非常多时产生性能开销。请根据实际情况评估。
 * 正则表达式: find 命令中使用了 -regextype posix-extended 和对应的正则表达式来匹配目录名格式，确保了更精确的匹配。
 * 查找最新目录的方法: 使用 ls -1td | head -n 1 是查找最新修改目录的常用方法，但如果目录数量极其巨大，可能有更高效的纯脚本方式（但会更复杂）。此方法在大多数情况下是可接受的。
