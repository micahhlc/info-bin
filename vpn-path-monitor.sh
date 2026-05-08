#!/bin/bash
# vpn-path-monitor.sh — Continuously monitors which tunnel carries traffic
#                       and detects path changes on VPN reconnects
#
# Usage: sudo ./vpn-path-monitor.sh [target]
#   target defaults to 8.8.8.8
#
# Shows:
#   - Which utun interface is actually carrying bytes (live vs stale)
#   - traceroute path to target — re-runs whenever route table changes
#   - DNS path: which resolver answers and how fast
#   - VPN reconnect events (new utun appearing, route count change)

TARGET="${1:-8.8.8.8}"
LOGFILE="vpn-path-monitor-$(date +%Y%m%d-%H%M%S).log"
POLL=4   # seconds between polls

RED="\033[91m"
YELLOW="\033[93m"
GREEN="\033[92m"
CYAN="\033[96m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# ── helpers ───────────────────────────────────────────────────────────────────

ts() { date '+%H:%M:%S'; }

get_route_count() { netstat -nr 2>/dev/null | grep -c "^default"; }

get_active_default_ifaces() {
    # Which interfaces appear as default routes
    netstat -nr 2>/dev/null | awk '/^default/{print $NF}' | sort -u | tr '\n' ' '
}

get_utun_list() {
    ifconfig 2>/dev/null | awk -F: '/^utun/{print $1}' | tr '\n' ' '
}

get_dns_resolvers() {
    scutil --dns 2>/dev/null | awk '/nameserver/{print $3}' | sort -u | tr '\n' ' '
}

# Per-interface byte counters — returns associative-style "iface=RX:TX" lines
get_iface_counters() {
    for iface in en0 $(ifconfig 2>/dev/null | awk -F: '/^utun/{print $1}'); do
        line=$(netstat -I "$iface" -b 2>/dev/null | tail -1)
        [ -z "$line" ] && continue
        rx=$(echo "$line" | awk '{print $7}')
        tx=$(echo "$line" | awk '{print $10}')
        echo "$iface=$rx:$tx"
    done
}

# Compute delta bytes between two counter snapshots (passed as multiline strings)
iface_delta() {
    local prev="$1" cur="$2"
    while IFS='=' read -r iface counts; do
        prev_counts=$(echo "$prev" | awk -F= -v i="$iface" '$1==i{print $2}')
        [ -z "$prev_counts" ] && continue
        prev_rx=$(echo "$prev_counts" | cut -d: -f1)
        prev_tx=$(echo "$prev_counts" | cut -d: -f2)
        cur_rx=$(echo "$counts" | cut -d: -f1)
        cur_tx=$(echo "$counts" | cut -d: -f2)
        delta_rx=$((cur_rx - prev_rx))
        delta_tx=$((cur_tx - prev_tx))
        total=$((delta_rx + delta_tx))
        if [ "$total" -gt 0 ]; then
            printf "  %-8s  rx=%-10s tx=%-10s total=%s\n" \
                "$iface" "$(fmt_bytes $delta_rx)" "$(fmt_bytes $delta_tx)" "$(fmt_bytes $total)"
        fi
    done <<< "$cur"
}

fmt_bytes() {
    local b=$1
    if [ "$b" -ge 1048576 ]; then
        printf "%.1fMB" "$(echo "scale=1; $b/1048576" | bc)"
    elif [ "$b" -ge 1024 ]; then
        printf "%.1fKB" "$(echo "scale=1; $b/1024" | bc)"
    else
        printf "%sB" "$b"
    fi
}

# Use route get instead of traceroute — works even when Netskope blocks ICMP probes
run_route_check() {
    local targets="8.8.8.8 1.1.1.1 10.0.63.3"
    for t in $targets; do
        result=$(route get "$t" 2>/dev/null | awk '
            /interface:/{iface=$2}
            /gateway:/{gw=$2}
            END{printf "%-15s → gw=%-15s iface=%s\n", target, gw, iface}
        ' target="$t")
        echo "  $result"
    done
}

# Compact route get summary for change detection
get_route_fingerprint() {
    local targets="8.8.8.8 1.1.1.1 10.0.63.3"
    for t in $targets; do
        route get "$t" 2>/dev/null | awk '/interface:|gateway:/{printf "%s=%s ", $1, $2}'
    done
}

# DNS timing test — query each resolver directly with timing
dns_timing() {
    local domain="google.com"
    for ns in $(scutil --dns 2>/dev/null | awk '/nameserver/{print $3}' | sort -u); do
        # Skip loopback — dnscryptproxy handles that
        [[ "$ns" == 127.* ]] && continue
        start=$(date +%s%3N)
        answer=$(dig +time=2 +tries=1 +short "@${ns}" "$domain" A 2>/dev/null | head -1)
        end=$(date +%s%3N)
        elapsed=$((end - start))
        if [ -z "$answer" ]; then
            printf "  %-18s → TIMEOUT (%dms)\n" "$ns" "$elapsed"
        else
            printf "  %-18s → %s  (%dms)\n" "$ns" "$answer" "$elapsed"
        fi
    done
}

log() { echo "$@" >> "$LOGFILE"; }
logline() { echo "[$( ts)] $*" >> "$LOGFILE"; echo -e "[$( ts)] $*"; }

# ── init ──────────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo -e "${BOLD}=== vpn-path-monitor.sh ===${RESET}" | tee -a "$LOGFILE"
echo "Target:  $TARGET" | tee -a "$LOGFILE"
echo "Log:     $LOGFILE" | tee -a "$LOGFILE"
echo "Poll:    every ${POLL}s  |  Ctrl-C to stop" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

PREV_ROUTE_COUNT=$(get_route_count)
PREV_DEFAULT_IFACES=$(get_active_default_ifaces)
PREV_UTUN=$(get_utun_list)
PREV_DNS=$(get_dns_resolvers)
PREV_COUNTERS=$(get_iface_counters)
RECONNECT_COUNT=0
LAST_TRACE_ROUTES=""

echo -e "${BOLD}── Baseline ──────────────────────────────────────────────────${RESET}"
echo "  Default routes : $PREV_ROUTE_COUNT  via [$PREV_DEFAULT_IFACES]"
echo "  DNS resolvers  : [$PREV_DNS]"
echo "  utun interfaces: [$PREV_UTUN]"
echo ""

log "=== BASELINE ==="
log "routes=$PREV_ROUTE_COUNT  ifaces=[$PREV_DEFAULT_IFACES]  dns=[$PREV_DNS]  utun=[$PREV_UTUN]"
log ""

# Initial routing decisions
echo -e "${BOLD}── Initial routing decisions (route get) ──────────────────────${RESET}"
echo ""
run_route_check | tee -a "$LOGFILE"
LAST_ROUTE_FP=$(get_route_fingerprint)
echo ""
echo -e "${BOLD}── Initial DNS timing ─────────────────────────────────────────${RESET}"
echo ""
dns_timing | tee -a "$LOGFILE"
echo ""

echo -e "${BOLD}── Monitoring (interface traffic shown every ${POLL}s) ──────────${RESET}"
echo ""
log "=== MONITOR START ==="

# ── main loop ─────────────────────────────────────────────────────────────────

while true; do
    sleep "$POLL"

    CUR_ROUTE_COUNT=$(get_route_count)
    CUR_DEFAULT_IFACES=$(get_active_default_ifaces)
    CUR_UTUN=$(get_utun_list)
    CUR_DNS=$(get_dns_resolvers)
    CUR_COUNTERS=$(get_iface_counters)

    CHANGED=false

    # ── new utun = VPN reconnect event ──
    if [ "$CUR_UTUN" != "$PREV_UTUN" ]; then
        CHANGED=true
        RECONNECT_COUNT=$((RECONNECT_COUNT + 1))
        echo ""
        echo -e "${RED}${BOLD}[VPN RECONNECT #${RECONNECT_COUNT}]${RESET} ${YELLOW}utun changed${RESET}"
        echo -e "  before: [$PREV_UTUN]"
        echo -e "  after:  [$CUR_UTUN]"
        logline "VPN_RECONNECT #${RECONNECT_COUNT}: utun [$PREV_UTUN] → [$CUR_UTUN]"
        {
            echo "--- utun IPs after reconnect ---"
            ifconfig 2>/dev/null | awk '
                /^utun/{iface=$1; sub(/:$/,"",iface)}
                iface && /inet /{print iface": "$2; iface=""}
            '
            echo ""
        } >> "$LOGFILE"
        PREV_UTUN="$CUR_UTUN"
    fi

    # ── route table change ──
    if [ "$CUR_ROUTE_COUNT" != "$PREV_ROUTE_COUNT" ] || [ "$CUR_DEFAULT_IFACES" != "$PREV_DEFAULT_IFACES" ]; then
        CHANGED=true
        DELTA=$((CUR_ROUTE_COUNT - PREV_ROUTE_COUNT))
        SIGN=""; [ "$DELTA" -ge 0 ] && SIGN="+"
        if [ "$CUR_ROUTE_COUNT" -gt 6 ]; then
            COLOR="$RED"
        elif [ "$CUR_ROUTE_COUNT" -gt 4 ]; then
            COLOR="$YELLOW"
        else
            COLOR="$GREEN"
        fi
        echo ""
        echo -e "${COLOR}${BOLD}[ROUTE CHANGE]${RESET} ${PREV_ROUTE_COUNT}→${CUR_ROUTE_COUNT} routes (${SIGN}${DELTA})  via [${CUR_DEFAULT_IFACES}]"
        logline "ROUTE: ${PREV_ROUTE_COUNT}→${CUR_ROUTE_COUNT}  ifaces=[${CUR_DEFAULT_IFACES}]"
        {
            echo "--- default routes ---"
            netstat -nr | grep "^default"
            echo ""
        } >> "$LOGFILE"
        PREV_ROUTE_COUNT="$CUR_ROUTE_COUNT"
        PREV_DEFAULT_IFACES="$CUR_DEFAULT_IFACES"
    fi

    # ── DNS change ──
    if [ "$CUR_DNS" != "$PREV_DNS" ]; then
        CHANGED=true
        echo ""
        echo -e "${YELLOW}${BOLD}[DNS CHANGE]${RESET}"
        echo -e "  before: [$PREV_DNS]"
        echo -e "  after:  [$CUR_DNS]"
        echo "  New DNS timing:"
        dns_timing | tee -a "$LOGFILE"
        logline "DNS: [$PREV_DNS] → [$CUR_DNS]"
        PREV_DNS="$CUR_DNS"
    fi

    # ── routing decision check on any change ──
    if $CHANGED; then
        echo ""
        echo -e "${CYAN}  Checking routing decisions...${RESET}"
        NEW_ROUTE_FP=$(get_route_fingerprint)
        run_route_check | tee -a "$LOGFILE"

        if [ "$NEW_ROUTE_FP" != "$LAST_ROUTE_FP" ]; then
            echo -e "${YELLOW}  ROUTING PATH CHANGED${RESET}"
            logline "ROUTING_PATH_CHANGE"
            LAST_ROUTE_FP="$NEW_ROUTE_FP"
        else
            echo -e "  ${DIM}routing decisions unchanged${RESET}"
        fi

        echo "  DNS timing:"
        dns_timing | tee -a "$LOGFILE"
        echo ""
    fi

    # ── always: show which interfaces are moving bytes this interval ──
    TRAFFIC=$(iface_delta "$PREV_COUNTERS" "$CUR_COUNTERS")
    if [ -n "$TRAFFIC" ]; then
        echo -e "${DIM}[$(ts)] active traffic:${RESET}"
        echo -e "${DIM}${TRAFFIC}${RESET}"
    else
        echo -e "${DIM}[$(ts)] routes=${CUR_ROUTE_COUNT}  no traffic this interval${RESET}"
    fi

    PREV_COUNTERS="$CUR_COUNTERS"
done
