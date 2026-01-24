#!/bin/bash

# Caleb: Folder sync script (source → dest)
# Usage: ./rsync.sh /source/folder /dest/folder
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

# Flags explanation:
# -a: archive mode (recursive, preserves times, etc.)
# -v: verbose
# -h: human-readable numbers
# -P: allows resuming interrupted files (partial)
# --info=progress2: shows overall progress bar (requires rsync 3.1.0+)
# --no-perms --no-owner --no-group: prevents errors on Google Drive/Fat32/ExFAT drives

# Base flags (Common to all versions)
# -a: archive mode
# --partial: allow resuming interrupted transfers (we avoid -P because it forces per-file progress)
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
    # MODERN RSYNC: Use progress bar, disable verbose (-v) for a clean display
    RSYNC_FLAGS="$RSYNC_FLAGS --info=progress2"
    echo "ℹ️  Progress Bar: ENABLED (Modern rsync detected)"
else
    # OLD RSYNC: Fallback to verbose (-v) and human-readable (-h) text output
    RSYNC_FLAGS="$RSYNC_FLAGS -vh"
    echo "⚠️  Note: Using standard progress. To see overall progress bar: brew install rsync"
fi

# Build the command arguments array
# Note: Using an array prevents issues with spaces in filenames and messy line breaking
CMD=(
  "$RSYNC_CMD"
  $RSYNC_FLAGS
  --exclude="Photos Library.photoslibrary"
  --exclude=".DS_Store"
  "${SOURCE%/}"  # Remove trailing slash: copies the FOLDER ITSELF (e.g. 'Diet') into destination
  "${DEST%/}"
)

# Run the command
"${CMD[@]}"

# Optional flags you can add manually above:
# --delete   (deletes files in Dest that aren't in Source)
# --dry-run  (simulate without copying)

echo
echo "done."