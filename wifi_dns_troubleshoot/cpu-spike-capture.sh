#!/bin/bash
#
# cpu-spike-capture.sh
# Polls CPU every second. When any process exceeds THRESHOLD_CPU%, captures
# a snapshot with process list, route count, DNS state, and gateway ping.
#
# Unlike ping-spike-capture.sh (which triggers on network latency then traces
# back to CPU), this triggers directly on CPU and records network context.
#
# Usage:
#   sudo ./cpu-spike-capture.sh [threshold_%] [cooldown_s]
#   sudo ./cpu-spike-capture.sh              # 50% threshold, 20s cooldown
#   sudo ./cpu-spike-capture.sh 30 30        # 30% / 30s cooldown
#
# Cooldown note: CyberArk EPM bursts recur ~every 44s; keep cooldown < 44s
# to capture each burst, but > ~5s to avoid duplicate entries per burst.
#

THRESHOLD_CPU="${1:-50}"
COOLDOWN="${2:-20}"
LOGFILE="./cpu-spike-capture.log"

# Auto-detect gateway for ping health check
GATEWAY=$(netstat -nrf inet 2>/dev/null | awk '$1=="default" && $4!~/utun/{print $2; exit}')

echo "CPU spike monitor  threshold=${THRESHOLD_CPU}%  cooldown=${COOLDOWN}s"
echo "Gateway: ${GATEWAY:-not detected}"
echo "Log: $LOGFILE"
echo "Press Ctrl-C to stop."
echo ""

last_capture=0
spike_count=0

while true; do
    # Snapshot all process CPU — sorted descending
    cpu_snapshot=$(ps -eo pid,pcpu,comm 2>/dev/null | sort -k2 -rn)

    # Find processes at or above threshold
    high_cpu=$(echo "$cpu_snapshot" | awk -v t="$THRESHOLD_CPU" 'NR>1 && $2+0 >= t+0')

    if [[ -n "$high_cpu" ]]; then
        now=$(date +%s)
        elapsed=$(( now - last_capture ))

        if (( elapsed >= COOLDOWN )); then
            spike_count=$(( spike_count + 1 ))
            ts=$(date '+%Y-%m-%d %H:%M:%S')
            last_capture=$now

            top_pid=$(echo "$high_cpu" | head -1 | awk '{print $1}')
            top_pct=$(echo "$high_cpu" | head -1 | awk '{print $2}')
            top_cmd=$(echo "$high_cpu" | head -1 | awk '{print $3}')
            # Shorten for screen display: strip path, keep last component
            top_short="${top_cmd##*/}"

            high_count=$(echo "$high_cpu" | wc -l | tr -d ' ')

            printf "\033[1;31m>>> CPU SPIKE #%d  %s  %s (PID %s) = %s%%  [%d proc(s) >%s%%]\033[0m\n" \
                "$spike_count" "$ts" "$top_short" "$top_pid" "$top_pct" "$high_count" "$THRESHOLD_CPU"

            {
                echo "================================================================"
                printf "CPU SPIKE #%d  time=%s\n" "$spike_count" "$ts"
                printf "Top: %s  PID=%s  cpu=%s%%  (%d proc(s) above %s%%)\n" \
                    "$top_short" "$top_pid" "$top_pct" "$high_count" "$THRESHOLD_CPU"
                echo "================================================================"

                echo "--- Processes above ${THRESHOLD_CPU}% ---"
                echo "$high_cpu" | awk '{printf "  %6s%%  PID %-6s  %s\n", $2, $1, $3}'
                echo ""

                echo "--- Top 15 processes by CPU ---"
                echo "$cpu_snapshot" | awk 'NR>1 && NR<=16 {printf "  %6s%%  PID %-6s  %s\n", $2, $1, $3}'
                echo ""

                echo "--- Default routes (healthy = ≤6) ---"
                route_count=$(netstat -nr 2>/dev/null | grep -c "^default")
                netstat -nr 2>/dev/null | grep "^default" | awk '{printf "  %-8s  via %s  %s\n", $1, $2, $4}'
                if (( route_count <= 6 )); then route_status="OK"; else route_status="ELEVATED"; fi
                printf "  Total: %s  (%s)\n" "$route_count" "$route_status"
                echo ""

                echo "--- Active DNS resolvers ---"
                scutil --dns 2>/dev/null | grep "nameserver\[" | awk '{print $3}' | sort -u \
                    | awk '{print "  " $0}'
                echo ""

                echo "--- Gateway ping (1 packet) ---"
                if [[ -n "$GATEWAY" ]]; then
                    ping_out=$(ping -c 1 -t 2 "$GATEWAY" 2>&1 | tail -2)
                    echo "$ping_out" | awk '{print "  " $0}'
                else
                    echo "  (gateway not detected)"
                fi
                echo ""

            } >> "$LOGFILE"
        fi
    else
        # Print a heartbeat dot every 10 seconds so you know it's still running
        now=$(date +%s)
        if (( now % 10 == 0 )); then
            printf "."
        fi
    fi

    sleep 1
done
