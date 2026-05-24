#!/bin/sh

# 1. Define scan path (modify as needed, recommended to scan /var/mobile for testing)
set TARGET_PATH "/"
set OUTPUT_FILE "/var/mobile/Documents/disk_usage.txt"

echo "Scanning $TARGET_PATH ..."
echo "Results will be saved to $OUTPUT_FILE"

# 2. Scan using du command
# -a: List all files and directories
# -k: In KB (convenient for calculation)
# du output format is usually: 1024 /var/mobile/foo
du -ak "$TARGET_PATH" > "$OUTPUT_FILE" 2>/dev/null

echo "Scan complete! File saved."