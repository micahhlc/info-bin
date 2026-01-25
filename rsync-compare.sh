#!/bin/bash

# Caleb: Folder Comparison Tool
# Usage: ./rsync-compare.sh /source/folder /dest/folder
# Purpose: Compares Source & Dest CONTENTS and reports differences.
# DOES NOT MODIFY ANYTHING.

SOURCE="$1"
DEST="$2"

# Validate input
if [ -s "$SOURCE" ] || [ -z "$DEST" ]; then
  # Fallback check if arguments missing
  if [ -z "$SOURCE" ] || [ -z "$DEST" ]; then
      echo "Usage: $0 source_folder dest_folder"
      exit 1
  fi
fi

# Detect rsync
if [ -x "/opt/homebrew/bin/rsync" ]; then
    RSYNC_CMD="/opt/homebrew/bin/rsync"
else
    RSYNC_CMD="rsync"
fi

echo "🔍 Analyzing Differences..."
echo "Source: $SOURCE"
echo "Dest:   $DEST"
echo "---------------------------------------------------"

# We use -n (dry run) + -i (itemize) + --delete (to see extras)
# We FORCE content comparison by using trailing slashes on both
# output format is captured to a variable
OUTPUT=$("$RSYNC_CMD" -avn -i --delete --ignore-errors --force "${SOURCE%/}/" "${DEST%/}/")

# Process the output
# rsync -i codes:
# >f+++++++++ : Transferring file (Missing in dest)
# .d..t...... : Directory timestamp check (ignore)
# *deleting   : Extra file in dest

MISSING=$(echo "$OUTPUT" | grep "^>f")
EXTRAS=$(echo "$OUTPUT" | grep "deleting")
CHANGED=$(echo "$OUTPUT" | grep "^>f" | grep -v "+++++++++") # If it's transferring but not new, it's changed

# Counts
NUM_MISSING=$(echo "$MISSING" | grep -v "^$" | wc -l | tr -d ' ')
NUM_EXTRAS=$(echo "$EXTRAS" | grep -v "^$" | wc -l | tr -d ' ')

# Report
if [ "$NUM_MISSING" -eq 0 ] && [ "$NUM_EXTRAS" -eq 0 ]; then
    echo "✅ IDENTICAL. The folders match perfectly."
    exit 0
fi

if [ "$NUM_MISSING" -gt 0 ]; then
    echo "❌ MISSING in Destination ($NUM_MISSING files):"
    echo "   (These failed to copy or haven't been copied yet)"
    echo "$MISSING" | awk '{print $2}' | head -n 20
    if [ "$NUM_MISSING" -gt 20 ]; then echo "... (and $((NUM_MISSING - 20)) more)"; fi
    echo
fi

if [ "$NUM_EXTRAS" -gt 0 ]; then
    echo "⚠️  EXTRA in Destination ($NUM_EXTRAS files):"
    echo "   (These exist in Dest but not Source)"
    echo "$EXTRAS" | awk '{print $2}' | head -n 20
    if [ "$NUM_EXTRAS" -gt 20 ]; then echo "... (and $((NUM_EXTRAS - 20)) more)"; fi
    echo
fi

echo "---------------------------------------------------"
echo "Summary:"
echo " - Missing/Different: $NUM_MISSING"
echo " - Extras:            $NUM_EXTRAS"
