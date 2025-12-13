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
get_val () { echo "$RAW" | awk -F': ' -v k="$1" '$1==k{print $2}'; }

echo "— iPad Battery Info —"
echo "Charge %:               $(get_val BatteryCurrentCapacity)%"
echo "Is Charging:            $(get_val BatteryIsCharging)"
echo "External Power:         $(get_val ExternalConnected)"
echo "Fully Charged:          $(get_val FullyCharged)"
echo "Cycle Count:            $(get_val CycleCount)"
echo "Design Max Capacity:    $(get_val DesignCapacity)"
echo "Current Max Capacity:   $(get_val MaximumCapacity)"
echo "Nominal Charge (mAh):   $(get_val NominalChargeCapacity)"
echo "Voltage (mV):           $(get_val Voltage)"
echo "Temperature (0.1°C):    $(get_val Temperature)"
echo "Chemistry:              $(get_val BatteryChemistry)"
echo "Health Visible:         $(get_val BatteryHealth)"