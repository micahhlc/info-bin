#!/bin/bash

# WiFi Reconnect Script
# Forces WiFi to disconnect and reconnect (useful to get different channel/AP)

GREEN="\033[92m"
YELLOW="\033[93m"
BOLD="\033[1m"
RESET="\033[0m"

INTERFACE="${1:-en0}"
WAIT_TIME="${2:-5}"

echo -e "${BOLD}=== WiFi Reconnect Tool ===${RESET}\n"

# Get current channel before disconnect
echo "Current WiFi status:"
CURRENT_CHANNEL=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "channel:" | awk '{print $2}')
CURRENT_SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "^ SSID:" | awk '{print $2}')
echo "  SSID: ${CURRENT_SSID}"
echo "  Channel: ${CURRENT_CHANNEL}"
echo ""

# Disconnect
echo -e "${YELLOW}Disconnecting WiFi (${INTERFACE})...${RESET}"
sudo ifconfig "$INTERFACE" down

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${RESET} WiFi disconnected"
else
    echo -e "  ${RED}✗${RESET} Failed to disconnect WiFi (need sudo?)"
    exit 1
fi

# Wait
echo "  Waiting ${WAIT_TIME} seconds..."
sleep "$WAIT_TIME"

# Reconnect
echo -e "${YELLOW}Reconnecting WiFi...${RESET}"
sudo ifconfig "$INTERFACE" up

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✓${RESET} WiFi reconnected"
else
    echo -e "  ${RED}✗${RESET} Failed to reconnect WiFi"
    exit 1
fi

# Wait for connection to establish
echo "  Waiting for network association (10 seconds)..."
sleep 10

# Show new status
echo ""
echo -e "${BOLD}New WiFi status:${RESET}"
NEW_CHANNEL=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "channel:" | awk '{print $2}')
NEW_SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "^ SSID:" | awk '{print $2}')
SIGNAL=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "agrCtlRSSI:" | awk '{print $2}')

echo "  SSID: ${NEW_SSID}"
echo "  Channel: ${NEW_CHANNEL}"
echo "  Signal: ${SIGNAL} dBm"

# Compare channels
if [ "$NEW_CHANNEL" != "$CURRENT_CHANNEL" ]; then
    echo -e "\n${GREEN}✓ Channel changed: ${CURRENT_CHANNEL} → ${NEW_CHANNEL}${RESET}"
else
    echo -e "\n${YELLOW}⚠ Still on channel ${CURRENT_CHANNEL} (may need to reconnect again)${RESET}"
fi

echo ""
echo "Test connection with: ping -c 10 8.8.8.8"
echo ""
