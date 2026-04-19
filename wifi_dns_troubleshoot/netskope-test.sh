#!/bin/bash

# Quick test to prove Netskope is causing ping spikes

RED="\033[91m"
GREEN="\033[92m"
YELLOW="\033[93m"
BOLD="\033[1m"
RESET="\033[0m"

HOST="${1:-8.8.8.8}"
COUNT=60

echo -e "${BOLD}=== Netskope Impact Test ===${RESET}"
echo ""

# Function to count high-latency pings
count_spikes() {
    grep "time=" | awk -F'time=' '{print $2}' | awk '{gsub(" ms","",$1); if($1>100) print $1}' | wc -l | xargs
}

# Function to show max latency
max_latency() {
    grep "time=" | awk -F'time=' '{print $2}' | awk '{gsub(" ms","",$1); print $1}' | sort -n | tail -1
}

# PHASE 1: Test with Netskope enabled
echo -e "${YELLOW}Phase 1: Testing with Netskope ENABLED${RESET}"
echo "Running ${COUNT} pings to ${HOST}..."
ping -c $COUNT $HOST > /tmp/netskope_before.txt 2>&1

SPIKES_BEFORE=$(cat /tmp/netskope_before.txt | count_spikes)
MAX_BEFORE=$(cat /tmp/netskope_before.txt | max_latency)
AVG_BEFORE=$(tail -2 /tmp/netskope_before.txt | grep "round-trip" | awk -F'/' '{print $5}')

echo -e "  Spikes >100ms: ${RED}${SPIKES_BEFORE}${RESET}"
echo -e "  Max latency: ${RED}${MAX_BEFORE}ms${RESET}"
echo -e "  Average: ${AVG_BEFORE}ms"
echo ""

# PHASE 2: Disable Netskope
echo -e "${YELLOW}Phase 2: Disabling Netskope...${RESET}"
sudo pkill -f NetskopeClientMacAppProxy 2>/dev/null
if [ $? -eq 0 ]; then
    echo "  Netskope killed successfully"
else
    echo "  Netskope was not running or already stopped"
fi

echo "  Waiting 5 seconds for network to stabilize..."
sleep 5
echo ""

# PHASE 3: Test with Netskope disabled
echo -e "${YELLOW}Phase 3: Testing with Netskope DISABLED${RESET}"
echo "Running ${COUNT} pings to ${HOST}..."
ping -c $COUNT $HOST > /tmp/netskope_after.txt 2>&1

SPIKES_AFTER=$(cat /tmp/netskope_after.txt | count_spikes)
MAX_AFTER=$(cat /tmp/netskope_after.txt | max_latency)
AVG_AFTER=$(tail -2 /tmp/netskope_after.txt | grep "round-trip" | awk -F'/' '{print $5}')

echo -e "  Spikes >100ms: ${GREEN}${SPIKES_AFTER}${RESET}"
echo -e "  Max latency: ${GREEN}${MAX_AFTER}ms${RESET}"
echo -e "  Average: ${AVG_AFTER}ms"
echo ""

# RESULTS
echo -e "${BOLD}=== RESULTS ===${RESET}"
echo ""
echo "Before (Netskope ON):"
echo "  Spikes: ${SPIKES_BEFORE}"
echo "  Max: ${MAX_BEFORE}ms"
echo "  Avg: ${AVG_BEFORE}ms"
echo ""
echo "After (Netskope OFF):"
echo "  Spikes: ${SPIKES_AFTER}"
echo "  Max: ${MAX_AFTER}ms"
echo "  Avg: ${AVG_AFTER}ms"
echo ""

# Calculate improvement
if [ "$SPIKES_BEFORE" -gt 0 ]; then
    IMPROVEMENT=$(( (SPIKES_BEFORE - SPIKES_AFTER) * 100 / SPIKES_BEFORE ))
    echo -e "${BOLD}Spike reduction: ${GREEN}${IMPROVEMENT}%${RESET}"
else
    echo -e "${YELLOW}Not enough spikes in before test to calculate improvement${RESET}"
fi

# Verdict
echo ""
if [ "$SPIKES_AFTER" -lt "$((SPIKES_BEFORE / 2))" ]; then
    echo -e "${BOLD}${GREEN}✅ VERDICT: Netskope is causing the instability${RESET}"
    echo ""
    echo "Recommendation: Keep Netskope disabled in office, or contact IT to fix tunnel"
elif [ "$SPIKES_AFTER" -eq "$SPIKES_BEFORE" ] && [ "$SPIKES_BEFORE" -gt 5 ]; then
    echo -e "${BOLD}${RED}⚠️  VERDICT: Netskope is NOT the cause${RESET}"
    echo ""
    echo "Recommendation: Investigate WiFi channel interference or hardware issues"
    echo "  Run: ./ping-correlate.sh $HOST 200"
else
    echo -e "${BOLD}${YELLOW}⚠️  VERDICT: Inconclusive - not enough spikes captured${RESET}"
    echo ""
    echo "Recommendation: Run test again during a period of instability"
fi

echo ""
echo "Detailed logs saved:"
echo "  Before: /tmp/netskope_before.txt"
echo "  After:  /tmp/netskope_after.txt"
echo ""
