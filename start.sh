Okay, here is a shell script designed to be run periodically (e.g., via cron). It generates the metrics discussed previously and outputs them to a file suitable for the node_exporter's textfile collector.
Assumptions:
 * You have node_exporter installed and running.
 * You know the directory node_exporter uses for its textfile collector (commonly /var/lib/node_exporter/textfile_collector/ or similar, check your node_exporter service configuration).
 * The script will run as a user with sufficient permissions to:
   * Read the application's daily directories (/path/to/base/YYYY-MM-DD).
   * Write to the node_exporter textfile collector directory.
 * Standard Linux tools like date, stat, du, find, wc, cut, sort, head, mkdir, mv are available.
The Script (monitor_daily_dirs.sh):
#!/bin/bash

# --- Configuration ---
# !! ADJUST THESE VARIABLES !!
APP_NAME="my_app"                   # Identifier for your application (used in labels)
BASE_PATH="/var/log/myapp"          # Parent directory containing the daily YYYY-MM-DD folders
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector" # node_exporter's textfile dir
# Optional: Set to true to enable potentially slow metrics (oldest/newest file)
ENABLE_SLOW_METRICS=false
# Optional: Set to true to also monitor yesterday's directory
MONITOR_YESTERDAY=true
# --- End Configuration ---

# --- Safety Checks ---
if [ -z "$APP_NAME" ] || [ -z "$BASE_PATH" ] || [ -z "$TEXTFILE_DIR" ]; then
  echo "ERROR: Configuration variables (APP_NAME, BASE_PATH, TEXTFILE_DIR) must be set." >&2
  exit 1
fi

if ! mkdir -p "$TEXTFILE_DIR"; then
  echo "ERROR: Cannot create or access textfile directory: $TEXTFILE_DIR" >&2
  exit 1
fi

# Output file names
OUTPUT_FILE="${TEXTFILE_DIR}/app_daily_dirs_${APP_NAME}.prom"
TMP_OUTPUT_FILE="${OUTPUT_FILE}.tmp.$$" # Temporary file for atomic write

# --- Helper Function to Generate Metrics for a Specific Date ---
generate_metrics_for_date() {
  local target_date="$1"
  local dir_path="${BASE_PATH}/${target_date}"
  local metrics=""
  local labels="app_name=\"${APP_NAME}\",base_path=\"${BASE_PATH}\",date=\"${target_date}\""
  local now_ts

  now_ts=$(date +%s)

  # Metric: Existence
  metrics+="# HELP app_daily_dir_exists Directory existence status (1=exists, 0=does not exist).\n"
  metrics+="# TYPE app_daily_dir_exists gauge\n"
  if [ -d "$dir_path" ]; then
    metrics+="app_daily_dir_exists{${labels}} 1\n"

    # --- Metrics for Existing Directory ---

    # Metric: Size (Bytes) - Use '--max-depth=0' if only top-level size is needed (faster)
    local dir_size dir_size_err
    # shellcheck disable=SC2046 # We want word splitting from du output
    set -- $(du -sb "$dir_path" 2>/dev/null)
    dir_size_err=$?
    dir_size=${1:-0} # Default to 0 if command fails or no output
    metrics+="# HELP app_daily_dir_size_bytes Total size of the directory in bytes.\n"
    metrics+="# TYPE app_daily_dir_size_bytes gauge\n"
    if [ "$dir_size_err" -eq 0 ]; then
        metrics+="app_daily_dir_size_bytes{${labels}} ${dir_size}\n"
    else
        metrics+="app_daily_dir_size_bytes{${labels},error=\"permission_or_missing\"} 0\n" # Indicate error via label
        echo "WARN: Could not get size for $dir_path" >&2
    fi


    # Metric: File Count (Recursive)
    local file_count file_count_err
    file_count=$(find "$dir_path" -type f 2>/dev/null | wc -l)
    file_count_err=$?
    metrics+="# HELP app_daily_dir_files_count Total number of files in the directory.\n"
    metrics+="# TYPE app_daily_dir_files_count gauge\n"
    if [ "$file_count_err" -eq 0 ]; then
         metrics+="app_daily_dir_files_count{${labels}} ${file_count}\n"
    else
        metrics+="app_daily_dir_files_count{${labels},error=\"permission_or_missing\"} 0\n" # Indicate error via label
        echo "WARN: Could not count files in $dir_path" >&2
    fi

    # Metric: Last Modification Time
    local mod_time_ts mod_time_err
    mod_time_ts=$(stat -c %Y "$dir_path" 2>/dev/null)
    mod_time_err=$?
    metrics+="# HELP app_daily_dir_last_modified_timestamp_seconds Last modification time of the directory (Unix Timestamp).\n"
    metrics+="# TYPE app_daily_dir_last_modified_timestamp_seconds gauge\n"
    if [ "$mod_time_err" -eq 0 ]; then
      metrics+="app_daily_dir_last_modified_timestamp_seconds{${labels}} ${mod_time_ts}\n"

      # Metric: Time Since Last Modification
      local time_since_mod=$((now_ts - mod_time_ts))
      metrics+="# HELP app_daily_dir_time_since_last_modified_seconds Seconds since the directory was last modified.\n"
      metrics+="# TYPE app_daily_dir_time_since_last_modified_seconds gauge\n"
      metrics+="app_daily_dir_time_since_last_modified_seconds{${labels}} ${time_since_mod}\n"
    else
      # Set mod time related metrics to 0 if stat fails
      metrics+="app_daily_dir_last_modified_timestamp_seconds{${labels},error=\"permission_or_missing\"} 0\n"
      metrics+="# HELP app_daily_dir_time_since_last_modified_seconds Seconds since the directory was last modified.\n"
      metrics+="# TYPE app_daily_dir_time_since_last_modified_seconds gauge\n"
      metrics+="app_daily_dir_time_since_last_modified_seconds{${labels},error=\"permission_or_missing\"} 0\n"
      echo "WARN: Could not stat $dir_path" >&2
    fi

    # --- Optional Slow Metrics ---
    if [[ "$ENABLE_SLOW_METRICS" == "true" ]]; then
        # Metric: Oldest File Modification Time
        local oldest_ts oldest_ts_err
        oldest_ts=$(find "$dir_path" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1)
        oldest_ts_err=$?
        metrics+="# HELP app_daily_dir_oldest_file_timestamp_seconds Modification time of the oldest file in the directory (Unix Timestamp).\n"
        metrics+="# TYPE app_daily_dir_oldest_file_timestamp_seconds gauge\n"
        if [[ "$oldest_ts_err" -eq 0 && -n "$oldest_ts" ]]; then
            metrics+="app_daily_dir_oldest_file_timestamp_seconds{${labels}} ${oldest_ts%.*}\n" # Remove potential fractional part
        else
            metrics+="app_daily_dir_oldest_file_timestamp_seconds{${labels},error=\"permission_or_empty\"} 0\n"
            echo "WARN: Could not determine oldest file time for $dir_path (check permissions or if dir is empty)" >&2
        fi

        # Metric: Newest File Modification Time
        local newest_ts newest_ts_err
        newest_ts=$(find "$dir_path" -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -1)
        newest_ts_err=$?
        metrics+="# HELP app_daily_dir_newest_file_timestamp_seconds Modification time of the newest file in the directory (Unix Timestamp).\n"
        metrics+="# TYPE app_daily_dir_newest_file_timestamp_seconds gauge\n"
         if [[ "$newest_ts_err" -eq 0 && -n "$newest_ts" ]]; then
            metrics+="app_daily_dir_newest_file_timestamp_seconds{${labels}} ${newest_ts%.*}\n" # Remove potential fractional part
        else
             metrics+="app_daily_dir_newest_file_timestamp_seconds{${labels},error=\"permission_or_empty\"} 0\n"
             echo "WARN: Could not determine newest file time for $dir_path (check permissions or if dir is empty)" >&2
        fi
    fi

  else
    # Directory does not exist - output exists=0 and zero for others
    metrics+="app_daily_dir_exists{${labels}} 0\n"
    metrics+="# HELP app_daily_dir_size_bytes Total size of the directory in bytes.\n"
    metrics+="# TYPE app_daily_dir_size_bytes gauge\n"
    metrics+="app_daily_dir_size_bytes{${labels}} 0\n"
    metrics+="# HELP app_daily_dir_files_count Total number of files in the directory.\n"
    metrics+="# TYPE app_daily_dir_files_count gauge\n"
    metrics+="app_daily_dir_files_count{${labels}} 0\n"
    metrics+="# HELP app_daily_dir_last_modified_timestamp_seconds Last modification time of the directory (Unix Timestamp).\n"
    metrics+="# TYPE app_daily_dir_last_modified_timestamp_seconds gauge\n"
    metrics+="app_daily_dir_last_modified_timestamp_seconds{${labels}} 0\n"
    metrics+="# HELP app_daily_dir_time_since_last_modified_seconds Seconds since the directory was last modified.\n"
    metrics+="# TYPE app_daily_dir_time_since_last_modified_seconds gauge\n"
    metrics+="app_daily_dir_time_since_last_modified_seconds{${labels}} 0\n"
    if [[ "$ENABLE_SLOW_METRICS" == "true" ]]; then
        metrics+="# HELP app_daily_dir_oldest_file_timestamp_seconds Modification time of the oldest file in the directory (Unix Timestamp).\n"
        metrics+="# TYPE app_daily_dir_oldest_file_timestamp_seconds gauge\n"
        metrics+="app_daily_dir_oldest_file_timestamp_seconds{${labels}} 0\n"
        metrics+="# HELP app_daily_dir_newest_file_timestamp_seconds Modification time of the newest file in the directory (Unix Timestamp).\n"
        metrics+="# TYPE app_daily_dir_newest_file_timestamp_seconds gauge\n"
        metrics+="app_daily_dir_newest_file_timestamp_seconds{${labels}} 0\n"
    fi
  fi

  # Output the generated metrics for this date
  # Use printf for better control and portability over echo -e
  printf "%s" "$metrics"
}

# --- Main Script Logic ---

# Clear temp file before starting
> "$TMP_OUTPUT_FILE"

# Generate metrics for Today
TODAY=$(date +%Y-%m-%d)
echo "INFO: Processing date: $TODAY" >&2
generate_metrics_for_date "$TODAY" >> "$TMP_OUTPUT_FILE"
SCRIPT_EXIT_CODE=$?

# Generate metrics for Yesterday (Optional)
if [[ "$MONITOR_YESTERDAY" == "true" ]]; then
  YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
  echo "INFO: Processing date: $YESTERDAY" >&2
  generate_metrics_for_date "$YESTERDAY" >> "$TMP_OUTPUT_FILE"
  # If either date processing failed, reflect it
  if [ $? -ne 0 ]; then SCRIPT_EXIT_CODE=1; fi
fi

# Add a metric for the script's own execution status
script_success=1
if [ "$SCRIPT_EXIT_CODE" -ne 0 ]; then
    script_success=0
    echo "ERROR: One or more metric collections failed." >&2
fi
printf "# HELP app_daily_dir_exporter_script_success Indicates if the exporter script ran successfully (1=success, 0=failure).\n" >> "$TMP_OUTPUT_FILE"
printf "# TYPE app_daily_dir_exporter_script_success gauge\n" >> "$TMP_OUTPUT_FILE"
printf "app_daily_dir_exporter_script_success{app_name=\"%s\",base_path=\"%s\"} %d\n" "$APP_NAME" "$BASE_PATH" "$script_success" >> "$TMP_OUTPUT_FILE"


# Atomically move the temporary file to the final destination
if ! mv "$TMP_OUTPUT_FILE" "$OUTPUT_FILE"; then
  echo "ERROR: Failed to move temporary file to $OUTPUT_FILE" >&2
  # Clean up temp file if move fails
  rm -f "$TMP_OUTPUT_FILE"
  exit 1
fi

echo "INFO: Metrics successfully written to $OUTPUT_FILE" >&2
exit 0

How to Use:
 * Save: Save the script to a file, for example, /usr/local/bin/monitor_daily_dirs.sh.
 * Configure: Edit the Configuration section at the top of the script:
   * Set APP_NAME to a suitable name for your application.
   * Set BASE_PATH to the correct parent directory (e.g., /var/log/my_app_logs).
   * Verify TEXTFILE_DIR matches your node_exporter setup.
   * Decide if you want ENABLE_SLOW_METRICS and MONITOR_YESTERDAY.
 * Permissions: Make the script executable: chmod +x /usr/local/bin/monitor_daily_dirs.sh. Ensure the user running the script has read access to BASE_PATH and its subdirectories, and write access to TEXTFILE_DIR.
 * Test: Run the script manually: /usr/local/bin/monitor_daily_dirs.sh. Check for any WARN or ERROR messages. Verify the output file (e.g., /var/lib/node_exporter/textfile_collector/app_daily_dirs_my_app.prom) contains the expected metrics.
 * Schedule with Cron: Edit the crontab for the appropriate user (e.g., sudo crontab -e -u node_exporter or another user with correct permissions):
   # Run the daily directory monitor script every 5 minutes
*/5 * * * * /usr/local/bin/monitor_daily_dirs.sh > /dev/null 2>&1

   * Adjust the frequency (*/5 * * * *) as needed. Running it too frequently might cause unnecessary load, especially if ENABLE_SLOW_METRICS is true. Running it every 5 or 15 minutes is usually sufficient.
   * > /dev/null 2>&1 suppresses standard output and error from cron emails, but errors are still logged within the script's logic (to stderr, which you might want to redirect to a log file instead if needed).
Now, node_exporter should pick up the metrics from the .prom file on its next scrape, and they will become available in Prometheus.
