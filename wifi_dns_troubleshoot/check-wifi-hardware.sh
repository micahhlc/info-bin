#!/bin/bash

# WiFi Hardware Issue Detective
# Checks for hardware/driver-specific problems that might affect specific channels

GREEN="\033[92m"
RED="\033[91m"
YELLOW="\033[93m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}=== WiFi Hardware Issue Detective ===${RESET}\n"

# 1. Get hardware info
echo -e "${BOLD}--- 1️⃣  Hardware Information ---${RESET}"
HARDWARE=$(system_profiler SPHardwareDataType 2>/dev/null)
MODEL=$(echo "$HARDWARE" | grep "Model Name" | awk -F': ' '{print $2}')
CHIP=$(echo "$HARDWARE" | grep "Chip" | awk -F': ' '{print $2}')
echo "Mac Model: $MODEL"
echo "Chip: $CHIP"

# Get WiFi chip info
WIFI_CARD=$(system_profiler SPAirPortDataType 2>/dev/null | grep -A 3 "Card Type")
echo "WiFi Hardware:"
echo "$WIFI_CARD"
echo ""

# 2. Check for hardware errors in system logs
echo -e "${BOLD}--- 2️⃣  Hardware Error Logs (last 1 hour) ---${RESET}"
HW_ERRORS=$(log show --predicate 'subsystem contains "IO80211" OR processImagePath contains "airportd"' \
    --style syslog --last 1h 2>/dev/null | \
    grep -iE "firmware|hardware|reset|dma|chip|device" | \
    grep -iE "error|fail|timeout|unable" | tail -20)

if [ -n "$HW_ERRORS" ]; then
    echo "$HW_ERRORS" | while read -r line; do
        echo -e "[${RED}ERROR${RESET}] $line"
    done
else
    echo -e "[${GREEN} OK ${RESET}] No hardware errors found in system logs"
fi
echo ""

# 3. Check for WiFi driver crashes
echo -e "${BOLD}--- 3️⃣  WiFi Driver Crash Reports ---${RESET}"
CRASHES=$(ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | \
    grep -iE "wifi|airport|io80211|airportd" | head -5)

if [ -n "$CRASHES" ]; then
    echo -e "[${RED}FOUND${RESET}] Recent WiFi-related crashes:"
    echo "$CRASHES"
else
    echo -e "[${GREEN} OK ${RESET}] No WiFi crash reports found"
fi
echo ""

# 4. Check kernel messages for WiFi
echo -e "${BOLD}--- 4️⃣  Kernel Messages (WiFi-related) ---${RESET}"
KERNEL_WIFI=$(dmesg 2>/dev/null | grep -iE "wifi|80211|en0|brcm" | tail -10)

if [ -n "$KERNEL_WIFI" ]; then
    echo "$KERNEL_WIFI"
else
    echo -e "[${YELLOW}NOTE${RESET}] dmesg requires root access or SIP disabled"
fi
echo ""

# 5. Check for firmware errors
echo -e "${BOLD}--- 5️⃣  WiFi Firmware Status ---${RESET}"
FIRMWARE_ERRORS=$(log show --predicate 'eventMessage contains "firmware"' \
    --style syslog --last 6h 2>/dev/null | \
    grep -iE "wifi|80211|airport" | \
    grep -iE "error|fail|load|crash" | tail -10)

if [ -n "$FIRMWARE_ERRORS" ]; then
    echo -e "[${RED}ERROR${RESET}] Firmware issues detected:"
    echo "$FIRMWARE_ERRORS"
else
    echo -e "[${GREEN} OK ${RESET}] No firmware errors detected"
fi
echo ""

# 6. Check for channel-specific issues
echo -e "${BOLD}--- 6️⃣  Channel-Specific Errors ---${RESET}"
CHANNEL_ERRORS=$(log show --predicate 'eventMessage contains "channel"' \
    --style syslog --last 30m 2>/dev/null | \
    grep -iE "error|fail|136|invalid|unsupported" | tail -10)

if [ -n "$CHANNEL_ERRORS" ]; then
    echo -e "[${YELLOW}WARN${RESET}] Channel-related issues found:"
    echo "$CHANNEL_ERRORS"
else
    echo -e "[${GREEN} OK ${RESET}] No channel-specific errors"
fi
echo ""

# 7. WiFi hardware test via system_profiler
echo -e "${BOLD}--- 7️⃣  WiFi Capability Check ---${RESET}"
WIFI_CAPS=$(system_profiler SPAirPortDataType 2>/dev/null | grep -A 20 "Supported Channels")
echo "$WIFI_CAPS" | head -25
echo ""

# 8. Check for USB 3.0 interference (known issue)
echo -e "${BOLD}--- 8️⃣  USB 3.0 Interference Check ---${RESET}"
USB3_DEVICES=$(system_profiler SPUSBDataType 2>/dev/null | grep -B 5 "5.0 Gb/s" | grep "Product" | wc -l)
if [ "$USB3_DEVICES" -gt 0 ]; then
    echo -e "[${YELLOW}WARN${RESET}] Found $USB3_DEVICES USB 3.0 devices"
    echo "  USB 3.0 can interfere with 2.4GHz WiFi (channels 1-11)"
    echo "  Try unplugging USB 3.0 devices temporarily to test"
else
    echo -e "[${GREEN} OK ${RESET}] No USB 3.0 devices detected"
fi
echo ""

# 9. Memory/CPU pressure (can cause driver issues)
echo -e "${BOLD}--- 9️⃣  System Resource Pressure ---${RESET}"
MEMORY_PRESSURE=$(memory_pressure 2>/dev/null | head -5)
echo "$MEMORY_PRESSURE"

CPU_LOAD=$(uptime | awk -F'load averages: ' '{print $2}')
echo "CPU Load: $CPU_LOAD"
echo ""

# 10. Diagnosis
echo -e "${BOLD}=== 🔍 HARDWARE ISSUE INDICATORS ===${RESET}\n"

HAS_HW_ERROR=0

# Check for smoking guns
if echo "$HW_ERRORS" | grep -iq "firmware"; then
    echo -e "${RED}⚠️  Firmware errors detected - possible hardware/driver issue${RESET}"
    HAS_HW_ERROR=1
fi

if [ -n "$CRASHES" ]; then
    echo -e "${RED}⚠️  WiFi driver crashes detected - likely hardware/driver bug${RESET}"
    HAS_HW_ERROR=1
fi

if echo "$CHANNEL_ERRORS" | grep -iq "136"; then
    echo -e "${YELLOW}⚠️  Channel 136 specific errors found - possible driver bug${RESET}"
    HAS_HW_ERROR=1
fi

if [ "$HAS_HW_ERROR" -eq 0 ]; then
    echo -e "${GREEN}✅ No obvious hardware/driver issues detected${RESET}"
    echo ""
    echo "This suggests the problem is more likely:"
    echo "  - AP client overload (specific access point has too many users)"
    echo "  - Non-WiFi interference (Bluetooth, microwave, etc.)"
    echo "  - Network congestion (high traffic on that AP)"
    echo ""
    echo "Recommendation: Force reconnect to different AP/channel"
fi

echo ""
echo -e "${BOLD}Next Steps:${RESET}"
echo "1. If hardware errors found → Run Apple Diagnostics (restart + hold D)"
echo "2. If firmware errors → Update macOS: softwareupdate -l"
echo "3. If no hardware issues → Try different WiFi channel/AP"
echo "4. Compare with colleague's Mac model and chip"
echo ""
