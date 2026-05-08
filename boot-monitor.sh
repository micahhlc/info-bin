#!/bin/bash
# boot-monitor.sh — Run right after reboot to capture how Netskope/Cisco change routing & DNS
# Usage: sudo ./boot-monitor.sh [duration_seconds]
#
# Logs every change to:
#   - default route table (count + entries)
#   - active DNS resolvers
#   - utun interface list
#   - per-interface byte counters (en0, utun*)
# Snapshots traceroute to 8.8.8.8 at t=0, then whenever routes change.
# Output: boot-monitor-<timestamp>.log  +  summary printed to terminal

DURATION="${1:-300}"   # 5 min default — covers full Netskope+Cisco init window
INTERVAL=3             # poll every 3 seconds
LOGFILE="boot-monitor-$(date +%Y%m%d-%H%M%S).log"
TRACEROUTE_HOST="8.8.8.8"

RED="\033[91m"
YELLOW="\033[93m"
GREEN="\033[92m"
CYAN="\033[96m"
BOLD="\033[1m"
RESET="\033[0m"

# ── helpers ──────────────────────────────────────────────────────────────────

get_default_routes() {
    netstat -nr 2>/dev/null | awk '/^default/{print $2, $6}'
}

get_default_route_count() {
    netstat -nr 2>/dev/null | grep -c "^default"
}

get_dns() {
    scutil --dns 2>/dev/null | awk '/nameserver/{print $3}' | sort -u | tr '\n' ' '
}

get_utun_list() {
    ifconfig 2>/dev/null | awk -F: '/^utun/{print $1}' | tr '\n' ' '
}

get_iface_bytes() {
    # Returns "en0:RX/TX utun0:RX/TX ..."
    for iface in en0 $(ifconfig 2>/dev/null | awk -F: '/^utun/{print $1}'); do
        stats=$(netstat -I "$iface" -b 2>/dev/null | tail -1)
        if [ -n "$stats" ]; then
            rx=$(echo "$stats" | awk '{print $7}')
            tx=$(echo "$stats" | awk '{print $10}')
            printf "%s:%s/%s " "$iface" "$rx" "$tx"
        fi
    done
}

get_top_net_procs() {
    # Top 5 processes by bytes — nettop snapshot mode
    nettop -P -L 1 -J bytes_in,bytes_out 2>/dev/null \
        | awk 'NR>1 && ($2+$3)>0 {printf "%s(in=%s out=%s) ", $1, $2, $3}' \
        | cut -c1-200
}

snapshot_traceroute() {
    local label="$1"
    echo "" >> "$LOGFILE"
    echo "=== TRACEROUTE @ $label ===" >> "$LOGFILE"
    echo "Time: $(date '+%H:%M:%S')" >> "$LOGFILE"
    traceroute -n -w 1 -q 1 -m 15 "$TRACEROUTE_HOST" 2>&1 >> "$LOGFILE"
    echo "" >> "$LOGFILE"
}

log_event() {
    local tag="$1"
    local msg="$2"
    local ts
    ts=$(date '+%H:%M:%S')
    echo "[$ts] [$tag] $msg" >> "$LOGFILE"
    echo -e "${CYAN}[$ts]${RESET} ${BOLD}[$tag]${RESET} $msg"
}

# ── init ─────────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "=== boot-monitor.sh ===" | tee -a "$LOGFILE"
echo "Started:   $(date)" | tee -a "$LOGFILE"
echo "Duration:  ${DURATION}s (poll every ${INTERVAL}s)" | tee -a "$LOGFILE"
echo "Log:       $LOGFILE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Baseline snapshot
PREV_ROUTES=$(get_default_routes)
PREV_ROUTE_COUNT=$(get_default_route_count)
PREV_DNS=$(get_dns)
PREV_UTUN=$(get_utun_list)

log_event "BASELINE" "routes=$PREV_ROUTE_COUNT  dns=[$PREV_DNS]  utun=[$PREV_UTUN]"
{
    echo "--- Baseline default routes ---"
    netstat -nr | grep "^default"
    echo ""
    echo "--- Baseline DNS ---"
    scutil --dns | grep nameserver
    echo ""
    echo "--- Baseline interfaces ---"
    ifconfig | grep -E "^(en|utun|lo)[0-9]|inet |status"
    echo ""
} >> "$LOGFILE"

snapshot_traceroute "BASELINE (t=0)"

CHANGE_COUNT=0
START_TIME=$(date +%s)
LAST_TRACEROUTE_TIME=0

echo ""
echo -e "${BOLD}Monitoring... (Ctrl-C to stop)${RESET}"
echo ""

# ── main loop ────────────────────────────────────────────────────────────────

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))

    [ "$ELAPSED" -ge "$DURATION" ] && break

    sleep "$INTERVAL"

    CUR_ROUTES=$(get_default_routes)
    CUR_ROUTE_COUNT=$(get_default_route_count)
    CUR_DNS=$(get_dns)
    CUR_UTUN=$(get_utun_list)

    CHANGED=false

    # ── route change ──
    if [ "$CUR_ROUTES" != "$PREV_ROUTES" ]; then
        CHANGED=true
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        DELTA_COUNT=$((CUR_ROUTE_COUNT - PREV_ROUTE_COUNT))
        SIGN=""; [ "$DELTA_COUNT" -ge 0 ] && SIGN="+"
        if [ "$CUR_ROUTE_COUNT" -gt 6 ]; then
            COLOR="$RED"
        elif [ "$CUR_ROUTE_COUNT" -gt 4 ]; then
            COLOR="$YELLOW"
        else
            COLOR="$GREEN"
        fi
        echo -e "${COLOR}[ROUTE CHANGE] ${PREV_ROUTE_COUNT} → ${CUR_ROUTE_COUNT} routes (${SIGN}${DELTA_COUNT})${RESET}"
        log_event "ROUTE" "count: ${PREV_ROUTE_COUNT}→${CUR_ROUTE_COUNT}  new_entries: $(echo "$CUR_ROUTES" | tr '\n' '|')"
        {
            echo "--- Route table after change ---"
            netstat -nr | grep "^default"
            echo ""
        } >> "$LOGFILE"

        # Traceroute on route change (throttle: max once per 30s)
        if [ $((NOW - LAST_TRACEROUTE_TIME)) -ge 30 ]; then
            snapshot_traceroute "ROUTE_CHANGE #${CHANGE_COUNT} (t=${ELAPSED}s)"
            LAST_TRACEROUTE_TIME=$NOW
            log_event "TRACEROUTE" "captured after route change"
        fi

        PREV_ROUTES="$CUR_ROUTES"
        PREV_ROUTE_COUNT="$CUR_ROUTE_COUNT"
    fi

    # ── DNS change ──
    if [ "$CUR_DNS" != "$PREV_DNS" ]; then
        CHANGED=true
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "${YELLOW}[DNS CHANGE] [$PREV_DNS] → [$CUR_DNS]${RESET}"
        log_event "DNS" "before=[$PREV_DNS] after=[$CUR_DNS]"
        {
            echo "--- DNS after change ---"
            scutil --dns | grep -A2 "nameserver\|domain\|search"
            echo ""
        } >> "$LOGFILE"
        PREV_DNS="$CUR_DNS"
    fi

    # ── new utun interface ──
    if [ "$CUR_UTUN" != "$PREV_UTUN" ]; then
        CHANGED=true
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "${YELLOW}[UTUN CHANGE] [$PREV_UTUN] → [$CUR_UTUN]${RESET}"
        log_event "UTUN" "before=[$PREV_UTUN] after=[$CUR_UTUN]"
        {
            echo "--- utun interfaces after change ---"
            ifconfig | awk '/^utun/{iface=$1} iface && /inet /{print iface, $2; iface=""}'
            echo ""
        } >> "$LOGFILE"
        PREV_UTUN="$CUR_UTUN"
    fi

    # ── periodic status line (every 15s) ──
    if [ $((ELAPSED % 15)) -lt "$INTERVAL" ]; then
        BYTES=$(get_iface_bytes)
        echo -e "  ${CYAN}t=${ELAPSED}s${RESET}  routes=${CUR_ROUTE_COUNT}  dns=[${CUR_DNS}]  bytes: ${BYTES}"
    fi
done

# ── final summary ────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=== Monitor complete ===${RESET}"
FINAL_ROUTE_COUNT=$(get_default_route_count)
FINAL_DNS=$(get_dns)
FINAL_UTUN=$(get_utun_list)

{
    echo ""
    echo "=== FINAL STATE ==="
    echo "Routes: $FINAL_ROUTE_COUNT"
    netstat -nr | grep "^default"
    echo ""
    echo "DNS: $FINAL_DNS"
    scutil --dns | grep nameserver
    echo ""
    echo "utun: $FINAL_UTUN"
    echo ""
    echo "Total changes logged: $CHANGE_COUNT"
    echo "Ended: $(date)"
} | tee -a "$LOGFILE"

snapshot_traceroute "FINAL (t=${DURATION}s)"

echo ""
if [ "$FINAL_ROUTE_COUNT" -gt 6 ]; then
    echo -e "${RED}WARNING: ${FINAL_ROUTE_COUNT} default routes (expected ≤6) — utun leak likely${RESET}"
fi

EXPECTED_DNS="10.0.63.3 10.0.2.1 10.0.1.20"
for expected in $EXPECTED_DNS; do
    if ! echo "$FINAL_DNS" | grep -q "$expected"; then
        echo -e "${YELLOW}NOTE: expected DNS server $expected not present${RESET}"
    fi
done

echo ""
echo "Full log: $LOGFILE"
echo "Changes:  $CHANGE_COUNT events recorded"
