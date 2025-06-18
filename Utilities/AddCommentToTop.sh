#!/bin/bash

# This script finds all .swift files within a specified directory and its subdirectories,
# and prepends a string including the filename and an extra comment to the beginning of each file.
# It is designed to work on macOS.
#
# Usage: ./prepend_string_to_swift.sh "extra comment at the top" /path/to/starting/directory

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 \"extra comment at the top\" /path/to/starting/directory"
    exit 1
fi

EXTRA_COMMENT="$1"
START_DIR="$2"

# Check if the starting path is a directory
if [ ! -d "$START_DIR" ]; then
    echo "Error: Directory '$START_DIR' not found or is not a directory."
    exit 1
fi

# Find all .swift files in the directory and its subdirectories
# Using -print0 and xargs -0 is robust for filenames with spaces or special characters
find "$START_DIR" -type f -name "*.swift" -print0 | while IFS= read -r -d '' FILE_PATH; do
    echo "Processing file: $FILE_PATH"

    # Check if the file exists and is a regular file (should be covered by find, but defensive)
    if [ ! -f "$FILE_PATH" ]; then
        echo "Warning: '$FILE_PATH' disappeared or is not a regular file. Skipping."
        continue
    fi

    # Extract the filename from the full path
    FILENAME=$(basename "$FILE_PATH")

    # Construct the string to prepend: "// FILENAME.swift\n// extra comment at the top"
    STRING_TO_PREPEND="//\n//  $FILENAME\n$EXTRA_COMMENT"

    # Prepend the string to the file using echo with the -e option to interpret \n
    TEMP_FILE=$(mktemp)
    echo -e "$STRING_TO_PREPEND" > "$TEMP_FILE"
    cat "$FILE_PATH" >> "$TEMP_FILE"
    mv "$TEMP_FILE" "$FILE_PATH"

    echo "Successfully prepended string to '$FILE_PATH'."
done

echo "Finished processing all .swift files in '$START_DIR'."
