#!/bin/bash

# Caleb: Folder sync script (source → dest)
# Usage: ./rsync.sh /source/folder /dest/folder
#
# IMPORTANT - TRAILING SLASH BEHAVIOR:
# - Source ends with / (e.g. /Pictures/): Copies CONTENTS of Pictures into Dest.
# - Source NO slash    (e.g. /Pictures):  Copies the FOLDER Pictures into Dest.
#
# NOTE ON RSYNC VERSION:
# macOS ships with an ancient rsync (v2.6.9) which lacks modern features.
# This script automatically expects and prefers the Homebrew version (v3.x+)
# to enable the global progress bar (--info=progress2).
#
# To install modern rsync: brew install rsync

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
  echo "Destination folder does not exist. Creating it..."
  mkdir -p "$DEST"
  echo "✅ Created: $DEST"
fi

echo "🔍 Comparing & syncing..."
echo "Source:      $SOURCE"
echo "Destination: $DEST"
echo

# WARNING regarding iCloud:
# If files are "optimized" (not stored locally), this script will force a download
# of ALL files to your local Mac before transferring. ensure you have enough disk space!

# Base flags (Common to all versions)
# -a: archive mode
# --partial: allow resuming interrupted transfers
RSYNC_FLAGS="-a --partial --no-perms --no-owner --no-group"

# Detect best rsync version (Homebrew version preferred for progress bar support)
if [ -x "/opt/homebrew/bin/rsync" ]; then
    RSYNC_CMD="/opt/homebrew/bin/rsync"
elif [ -x "/usr/local/bin/rsync" ]; then
    RSYNC_CMD="/usr/local/bin/rsync"
else
    RSYNC_CMD="rsync"
fi

echo "ℹ️  Using rsync binary: $RSYNC_CMD"

# Check if the chosen rsync supports --info=progress2
if "$RSYNC_CMD" --help 2>&1 | grep -q "info="; then
    # MODERN RSYNC:
    # We use -v (verbose) intentionally to show the scrolling file list ("Matrix view").
    # This confirms exactly which files are being transferred/deleted.
    RSYNC_FLAGS="$RSYNC_FLAGS -v --info=progress2"
    echo "ℹ️  Progress Bar: ENABLED (Modern rsync detected)"
else
    # OLD RSYNC: Fallback to verbose (-v) and human-readable (-h) text output
    RSYNC_FLAGS="$RSYNC_FLAGS -vh"
    echo "⚠️  Note: Using standard progress. To see overall progress bar: brew install rsync"
fi

echo "⏳ Calculating file list & starting sync... (This may take a moment)"

# Build the command arguments array
# Note: Using an array prevents issues with spaces in filenames and messy line breaking
CMD=(
  "$RSYNC_CMD"
  $RSYNC_FLAGS
  --exclude="Photos Library.photoslibrary"
  --exclude=".DS_Store"
  # RSYNC SLASH BEHAVIOR:
  # - If SOURCE has trailing slash (src/): Copies CONTENTS of src into Dest.
  # - If SOURCE has NO slash (src): Copies the FOLDER 'src' into Dest.
  "$SOURCE"
  "${DEST%/}"
)

# Run the command
"${CMD[@]}"

echo
echo "✅ Sync complete."
echo

# Post-sync sanity check: Are there leftover files in Dest?
echo "🔍 Checking for extra files in Destination..."
# Use dry-run (-n) and --delete to see what WOULDBE deleted
# We grep for "deleting" to count them
EXTRA_FILES_COUNT=$("$RSYNC_CMD" -avn --delete --ignore-errors --force "${SOURCE%/}/" "${DEST%/}/" | grep -c "^deleting ")

if [ "$EXTRA_FILES_COUNT" -gt 0 ]; then
    echo "⚠️  Found $EXTRA_FILES_COUNT extra file(s) in Destination that are NOT in Source."
    echo "   (These were NOT deleted. Run ./rsync-clean.sh to review and remove them if desired.)"
else
    echo "✨ Destination is perfectly clean (Exact mirror of Source)."
fi

echo
echo "done."