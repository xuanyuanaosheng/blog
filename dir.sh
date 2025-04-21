for dir in $(find /your/target/dir -mindepth 1 -maxdepth 1 -type d); do
    mod_time=$(stat -c %Y "$dir")
    human_time=$(date -d @"$mod_time" +"%Y-%m-%d %H:%M:%S")
    size=$(du -sh "$dir" | awk '{print $1}')
    file_count=$(find "$dir" -mindepth 1 -maxdepth 1 -type f | wc -l)
    echo -e "$human_time\t$(basename "$dir")\t$size\t$file_count"
done | sort -r