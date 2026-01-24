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

# WARNING regarding iCloud:
# If files are "optimized" (not stored locally), this script will force a download
# of ALL files to your local Mac before transferring. ensure you have enough disk space!

# Flags explanation:
# -a: archive mode (recursive, preserves times, etc.)
# -v: verbose
# -h: human-readable numbers
# -P: shows progress AND allows resuming interrupted files (partial)
# --no-perms --no-owner --no-group: prevents errors on Google Drive/Fat32/ExFAT drives

rsync -avhP --no-perms --no-owner --no-group \
  --exclude="Photos Library.photoslibrary" \
  --exclude=".DS_Store" \
  "$SOURCE"/ "$DEST"/
  # --delete \   <-- UNCOMMENT CAREFULLY: This deletes files in Dest that aren't in Source
  # --dry-run \  <-- OPTIONAL: Uncomment to see what would happen without copying

echo
echo "done."