#!/bin/bash
#
# ping-spike-capture.sh
# Pings the WiFi gateway continuously. When a ping exceeds THRESHOLD_MS,
# captures a 3-second nettop snapshot to identify which process is
# saturating the network at that moment.
#
# Usage:
#   ./ping-spike-capture.sh [gateway] [threshold_ms]
#   ./ping-spike-capture.sh                        # auto-detect gateway, 100ms threshold
#   ./ping-spike-capture.sh 10.49.167.254 150      # custom target + threshold
#
# Output: prints to stdout + appends captures to LOGFILE
#

GATEWAY="${1:-}"
THRESHOLD_MS="${2:-150}"
LOGFILE="./ping-spike-capture.log"
COOLDOWN=5   # seconds to suppress repeat captures after a spike

# Auto-detect gateway if not provided
if [[ -z "$GATEWAY" ]]; then
    GATEWAY=$(netstat -nrf inet 2>/dev/null | awk '$1=="default" && $4!~/utun/{print $2; exit}')
    if [[ -z "$GATEWAY" ]]; then
        echo "ERROR: could not auto-detect gateway. Pass it as first argument."
        exit 1
    fi
fi

echo "Monitoring: ping $GATEWAY  |  spike threshold: ${THRESHOLD_MS}ms"
echo "Captures logged to: $LOGFILE"
echo "Press Ctrl-C to stop."
echo ""

last_capture=0
spike_count=0

# Run ping in background, parse each line as it arrives
ping -i 1 "$GATEWAY" 2>/dev/null | while IFS= read -r line; do
    # Extract RTT from lines like: 64 bytes from ...: icmp_seq=N ttl=N time=X.XXX ms
    rtt=$(echo "$line" | grep -oE 'time=[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+')
    [[ -z "$rtt" ]] && continue

    seq=$(echo "$line" | grep -oE 'icmp_seq=[0-9]+' | grep -oE '[0-9]+')
    rtt_int=${rtt%.*}   # integer part for comparison (bash 3.2 has no float math)

    # Color-code output: normal=plain, spike=bold red
    if (( rtt_int >= THRESHOLD_MS )); then
        printf "\033[1;31m%s\033[0m\n" "$line"
    else
        echo "$line"
    fi

    # Capture nettop if this is a spike and cooldown has passed
    now=$(date +%s)
    elapsed=$(( now - last_capture ))

    if (( rtt_int >= THRESHOLD_MS && elapsed >= COOLDOWN )); then
        spike_count=$(( spike_count + 1 ))
        ts=$(date '+%Y-%m-%d %H:%M:%S')
        last_capture=$now

        # ---- screen summary (brief) ----
        top_cpu=$(ps -eo pid,pcpu,comm 2>/dev/null | sort -k2 -rn | head -3 \
            | awk '{printf "  %s (%.1f%%)\n", $3, $2}')
        printf "\n\033[1;31m>>> SPIKE #%d  %s  RTT=%.0fms\033[0m\n" \
            "$spike_count" "$ts" "$rtt"
        printf "  Top CPU:\n%s\n\n" "$top_cpu"

        # ---- full capture to log (unchanged) ----
        {
            echo "================================================================"
            echo "SPIKE #$spike_count  time=$ts  rtt=${rtt}ms  seq=$seq  gateway=$GATEWAY"
            echo "================================================================"

            # Snapshot interface byte counters before and after 2s window,
            # then diff to show which interface moved bytes during the spike.
            snap_before=$(netstat -ib 2>/dev/null | grep -E "^(en0|utun)")
            sleep 2
            snap_after=$(netstat -ib 2>/dev/null | grep -E "^(en0|utun)")

            echo "--- Interface byte delta (2s window around spike) ---"
            echo "Interface   Ibytes_delta   Obytes_delta"
            while IFS= read -r before_line; do
                iface=$(echo "$before_line" | awk '{print $1}')
                echo "$before_line" | grep -q '<Link#' || continue
                ib_before=$(echo "$before_line" | awk '{print $7}')
                ob_before=$(echo "$before_line" | awk '{print $10}')
                after_line=$(echo "$snap_after" | awk -v i="$iface" '$1==i && /<Link#>/ || $1==i' | grep '<Link#' | head -1)
                ib_after=$(echo "$after_line" | awk '{print $7}')
                ob_after=$(echo "$after_line" | awk '{print $10}')
                ib_delta=$(( ${ib_after:-0} - ${ib_before:-0} ))
                ob_delta=$(( ${ob_after:-0} - ${ob_before:-0} ))
                if (( ib_delta > 0 || ob_delta > 0 )); then
                    printf "  %-10s  in=%-10s  out=%s\n" "$iface" "$ib_delta" "$ob_delta"
                fi
            done <<< "$snap_before"
            echo ""

            echo "--- nettop per-process (top senders during spike) ---"
            nettop -P -d -n -L 2 2>/dev/null \
                | grep -v '^\s*$' \
                | head -40
            echo ""

            echo "--- top CPU processes ---"
            ps -eo pid,pcpu,comm 2>/dev/null | sort -k2 -rn | head -10
            echo ""
        } >> "$LOGFILE"
    fi
done
