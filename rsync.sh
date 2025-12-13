#!/bin/bash

# Caleb: Folder sync script (source → dest)
# Usage: compareFolder.sh /source/folder /dest/folder

SOURCE="$1"
DEST="$2"

# Validate input
if [ -z "$SOURCE" ] || [ -z "$DEST" ]; then
  echo "Usage: $0 source_folder dest_folder"
  exit 1
fi

if [ ! -d "$SOURCE" ]; then
  echo "Source folder does not exist: $SOURCE"
  exit 1
fi

if [ ! -d "$DEST" ]; then
  echo "Destination folder does not exist: $DEST"
  exit 1
fi

echo "🔍 Comparing & syncing..."
echo "Source:      $SOURCE"
echo "Destination: $DEST"
echo

rsync -avh --delete --progress \
  --exclude="Photos Library.photoslibrary" \
  --exclude=".DS_Store" \
  "$SOURCE"/ "$DEST"/

echo
echo "done."