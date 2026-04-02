#!/bin/bash

# Ping correlation tool - monitors ping latency and logs system state during spikes
# Usage: ./ping-correlate.sh <host> [spike_threshold_ms]

HOST="${1:-8.8.8.8}"
THRESHOLD="${2:-200}"  # Log when ping > 200ms
LOGFILE="ping-correlation-$(date +%Y%m%d-%H%M%S).log"

RED="\033[91m"
YELLOW="\033[93m"
GREEN="\033[92m"
RESET="\033[0m"

echo "=== Ping Correlation Monitor ==="
echo "Host: $HOST"
echo "Spike threshold: ${THRESHOLD}ms"
echo "Logging to: $LOGFILE"
echo ""
echo "Starting continuous ping..."
echo ""

# Header
cat > "$LOGFILE" <<EOF
# Ping Correlation Log
# Host: $HOST
# Threshold: ${THRESHOLD}ms
# Started: $(date)

EOF

# Continuous ping with correlation
ping "$HOST" | while read line; do
    echo "$line"

    # Extract latency
    if [[ "$line" =~ time=([0-9.]+)[[:space:]]ms ]]; then
        LATENCY="${BASH_REMATCH[1]}"
        LATENCY_INT=$(printf "%.0f" "$LATENCY")

        # Check if spike
        if [ "$LATENCY_INT" -gt "$THRESHOLD" ]; then
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S.%3N')

            echo -e "${RED}[SPIKE] ${LATENCY}ms at $TIMESTAMP${RESET}"

            # Log detailed system state
            {
                echo ""
                echo "==================================="
                echo "SPIKE DETECTED: ${LATENCY}ms"
                echo "Time: $TIMESTAMP"
                echo "==================================="

                # WiFi info
                echo ""
                echo "--- WiFi Status ---"
                /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep -E "agrCtlRSSI|agrCtlNoise|state|lastTxRate|channel"

                # Interface stats
                echo ""
                echo "--- Interface Stats (en0) ---"
                netstat -I en0 -b | tail -1

                # Active connections
                echo ""
                echo "--- Active Connections ---"
                netstat -an | grep -E "ESTABLISHED|SYN_SENT|CLOSE_WAIT" | wc -l | xargs echo "Connection count:"

                # Top bandwidth users
                echo ""
                echo "--- Top Processes by Network ---"
                nettop -P -L 1 -J bytes_in,bytes_out 2>/dev/null | head -10

                # VPN/Tunnel status
                echo ""
                echo "--- Tunnel Interfaces ---"
                for iface in utun0 utun1 utun2 utun3 utun4 utun5; do
                    if ifconfig $iface &>/dev/null; then
                        IP=$(ifconfig $iface 2>/dev/null | grep "inet " | awk '{print $2}')
                        if [ -n "$IP" ]; then
                            echo "$iface: UP (IP: $IP)"
                        else
                            echo "$iface: UP (no IP)"
                        fi
                    fi
                done

                # Netskope status
                if pgrep -f "NetskopeClientMacAppProxy" > /dev/null; then
                    echo ""
                    echo "--- Netskope Recent Errors (last 5 seconds) ---"
                    tail -50 /Library/Logs/Netskope/nsdebuglog.log 2>/dev/null | grep -iE "error|fail|timeout" | tail -5
                fi

                # Memory pressure
                echo ""
                echo "--- Memory Pressure ---"
                vm_stat | grep -E "Pages free|Pages active|Pages wired|Pages inactive|Pages occupied by compressor"

                # CPU load
                echo ""
                echo "--- CPU Load ---"
                uptime

                echo ""

            } >> "$LOGFILE"
        fi
    fi
done

echo ""
echo "Correlation log saved to: $LOGFILE"
