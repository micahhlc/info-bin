#!/bin/bash
#
# install-utun-cleanup.sh
# Installs the utun-cleanup daemon so it runs automatically every 2 minutes.
#
# Run with: sudo ./install-utun-cleanup.sh
#

set -euo pipefail

SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/utun-cleanup.sh"
PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/com.micah.utun-cleanup.plist"

SCRIPT_DEST="/usr/local/bin/utun-cleanup.sh"
PLIST_DEST="/Library/LaunchDaemons/com.micah.utun-cleanup.plist"
LABEL="com.micah.utun-cleanup"
LOG="/var/log/utun-cleanup.log"

# ------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root."
    echo "       Run: sudo $0"
    exit 1
fi

if [[ ! -f "$SCRIPT_SRC" ]]; then
    echo "ERROR: Cleanup script not found at: $SCRIPT_SRC"
    exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
    echo "ERROR: Plist not found at: $PLIST_SRC"
    exit 1
fi

# ------------------------------------------------------------
# Install the cleanup script
# ------------------------------------------------------------

echo "Installing cleanup script to $SCRIPT_DEST ..."
cp "$SCRIPT_SRC" "$SCRIPT_DEST"
chmod 755 "$SCRIPT_DEST"
chown root:wheel "$SCRIPT_DEST"
echo "  OK"

# ------------------------------------------------------------
# Install the launchd plist
# ------------------------------------------------------------

echo "Installing plist to $PLIST_DEST ..."

# If the daemon is already loaded, unload it first so we can replace the plist.
if launchctl list "$LABEL" &>/dev/null; then
    echo "  Found existing daemon, unloading ..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

cp "$PLIST_SRC" "$PLIST_DEST"
chmod 644 "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
echo "  OK"

# ------------------------------------------------------------
# Create the log file with correct permissions if it doesn't exist
# ------------------------------------------------------------

if [[ ! -f "$LOG" ]]; then
    echo "Creating log file at $LOG ..."
    touch "$LOG"
    chmod 644 "$LOG"
    chown root:wheel "$LOG"
    echo "  OK"
fi

# ------------------------------------------------------------
# Load the daemon
# ------------------------------------------------------------

echo "Loading daemon with launchctl ..."
launchctl load "$PLIST_DEST"
echo "  OK"

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

echo ""
echo "Verifying daemon is loaded ..."
if launchctl list "$LABEL" &>/dev/null; then
    echo "  Daemon is active: $LABEL"
else
    echo "  WARNING: daemon does not appear in launchctl list — check the plist."
    exit 1
fi

echo ""
echo "Installation complete."
echo ""
echo "The daemon will:"
echo "  - Run immediately (RunAtLoad)"
echo "  - Re-run every 2 minutes (StartInterval: 120)"
echo "  - Log activity to: $LOG"
echo ""
echo "Useful commands:"
echo "  View log:              tail -f $LOG"
echo "  Check daemon status:   sudo launchctl list $LABEL"
echo "  Unload/disable:        sudo launchctl unload $PLIST_DEST"
echo "  Reload after changes:  sudo launchctl unload $PLIST_DEST && sudo launchctl load $PLIST_DEST"
