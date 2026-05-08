#!/usr/bin/env bash
set -euo pipefail

INTERVAL=2
ONCE=false

usage() {
  echo "Usage: $0 [-i SECONDS] [--once]"
  echo "  -i N    Poll interval in seconds (default: 2)"
  echo "  --once  Print currently connected USB devices and exit"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) INTERVAL="$2"; shift 2 ;;
    --once|-o) ONCE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

snapshot() {
  {
    # USB devices with Product ID (hubs, adapters, storage)
    system_profiler SPUSBDataType 2>/dev/null \
      | awk '/^[[:space:]]+[A-Z][^:]+:$/ { name=$0 } /Product ID:/ { print name }'
    # USB HID devices (keyboards, mice, gamepads) that don't appear in SPUSBDataType
    ioreg -p IOService -l -r -c IOHIDDevice 2>/dev/null \
      | awk '/"Transport" = "USB"/ { usb=1 } usb && /"Product" = / { gsub(/.*"Product" = "/,""); gsub(/".*$/,""); print "  "$0; usb=0 }'
  } | sort -u
}

if $ONCE; then
  echo "— Connected USB Devices —"
  SNAP="$(snapshot)"
  if [[ -z "$SNAP" ]]; then
    echo "(none detected)"
  else
    echo "$SNAP" | sed 's/^[[:space:]]*//'
  fi
  exit 0
fi

echo "Watching for new USB devices (interval: ${INTERVAL}s) … Ctrl+C to stop"
echo ""

PREV="$(snapshot)"

cleanup() { echo ""; echo "Stopped."; exit 0; }
trap cleanup INT TERM

while true; do
  sleep "$INTERVAL"
  CURR="$(snapshot)"
  NEW="$(comm -13 <(echo "$PREV") <(echo "$CURR"))"
  if [[ -n "$NEW" ]]; then
    TS="$(date '+%H:%M:%S')"
    echo "[$TS] New device connected:"
    echo "$NEW" | sed 's/^[[:space:]]*/  /'
  fi
  PREV="$CURR"
done
