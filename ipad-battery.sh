#!/usr/bin/env bash
set -euo pipefail

# 1) Check Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first, then re-run."
  exit 1
fi

# 2) Ensure libimobiledevice is installed
if ! command -v ideviceinfo >/dev/null 2>&1; then
  echo "Installing libimobiledevice (requires internet + brew)…"
  brew install libimobiledevice
fi

# 3) Make sure a device is connected & trusted
if ! idevice_id -l >/dev/null 2>&1; then
  echo "No iOS/iPadOS device detected."
  echo "• Connect your iPad via USB-C/Lightning"
  echo "• Unlock it and tap 'Trust this computer' if prompted"
  exit 2
fi

DEVICE_ID="$(idevice_id -l | head -n1)"
echo "Found device: ${DEVICE_ID}"

# Validate pairing (will fail if not trusted/unlocked)
if ! idevicepair validate >/dev/null 2>&1; then
  echo "Pairing not validated. Attempting to pair… (accept the prompt on iPad)"
  idevicepair pair || {
    echo "Pairing failed. Make sure iPad is unlocked and you tapped 'Trust'."
    exit 3
  }
fi

# 4) Query battery domain
RAW="$(ideviceinfo -q com.apple.mobile.battery 2>/dev/null || true)"
if [[ -z "$RAW" ]]; then
  echo "No battery info returned. This can happen if the device/OS restricts it."
  echo "Try unlocking iPad, keeping it on the Home screen, then re-run."
  exit 4
fi

# 5) Pretty-print selected fields if present
# 5) Fetch GasGauge diagnostics (for CycleCount)
GAS_XML="$(idevicediagnostics diagnostics GasGauge 2>/dev/null || true)"

# 6) Fetch AppleSmartBattery registry entry (for true mAh capacities)
IOREG_XML="$(idevicediagnostics ioregentry AppleSmartBattery 2>/dev/null || true)"

# Helper to parse integer keys from XML (GasGauge or IOReg)
get_xml_val() {
  local xml="$1"
  local key="$2"
  echo "$xml" | grep -A1 "<key>$key</key>" | grep "<integer>" | head -n1 | sed -E 's/.*<integer>([0-9]+)<\/integer>.*/\1/'
}

# Parse values
CYCLE_COUNT="$(get_xml_val "$GAS_XML" CycleCount)"
DESIGN_CAP="$(get_xml_val "$GAS_XML" DesignCapacity)"

RAW_MAX_CAP="$(get_xml_val "$IOREG_XML" AppleRawMaxCapacity)"
NOMINAL_CAP="$(get_xml_val "$IOREG_XML" NominalChargeCapacity)"

# Fallback for Design Cap if not found in GasGauge
if [[ -z "$DESIGN_CAP" ]]; then
  DESIGN_CAP="$(get_xml_val "$IOREG_XML" DesignCapacity)"
fi

# Calculate Health % if we have both values
HEALTH_CALC=""
if [[ -n "$RAW_MAX_CAP" && -n "$DESIGN_CAP" && "$DESIGN_CAP" -gt 0 ]]; then
  # Integer arithmetic for percentage
  HEALTH_CALC="$(( (RAW_MAX_CAP * 10000) / DESIGN_CAP ))"
  # Format as percentage with 2 decimal places (e.g. 7945 -> 79.45)
  HEALTH_PCT="$(echo "$HEALTH_CALC" | awk '{printf "%.1f", $1/100}')"
fi

# 7) Pretty-print fields
get_val () { echo "$RAW" | awk -F': ' -v k="$1" '$1==k{print $2}'; }

# Prefer fetched diagnostic values
RAW_CYCLE="$(get_val CycleCount)"
[[ -n "$CYCLE_COUNT" ]] && RAW_CYCLE="$CYCLE_COUNT"

RAW_DESIGN="$(get_val DesignCapacity)"
[[ -n "$DESIGN_CAP" ]] && RAW_DESIGN="$DESIGN_CAP"

echo "— iPad Battery Info —"
echo "Charge %:               $(get_val BatteryCurrentCapacity)%"
echo "Is Charging:            $(get_val BatteryIsCharging)"
echo "External Power:         $(get_val ExternalConnected)"
echo "Fully Charged:          $(get_val FullyCharged)"
echo "Cycle Count:            $RAW_CYCLE"
echo "Design Max Capacity:    $RAW_DESIGN mAh"

if [[ -n "$RAW_MAX_CAP" ]]; then
  echo "Current Max Capacity:   $RAW_MAX_CAP mAh (AppleRaw)"
elif [[ -n "$NOMINAL_CAP" ]]; then
  echo "Current Max Capacity:   $NOMINAL_CAP mAh (Nominal)"
else
  echo "Current Max Capacity:   $(get_val MaximumCapacity)"
fi

if [[ -n "$HEALTH_PCT" ]]; then
  echo "Battery Health:         $HEALTH_PCT% (Actual)"
else
  echo "Health Visible:         $(get_val BatteryHealth)"
fi

echo "Voltage (mV):           $(get_val Voltage)"
echo "Temperature (0.1°C):    $(get_val Temperature)"
echo "Chemistry:              $(get_val BatteryChemistry)"