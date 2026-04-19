#!/bin/bash
#
# wifi-reconnect.sh
#
# Full network reset: flushes stale Netskope utun routes, enforces IPv6-off,
# renews the WiFi connection, and clears DNS cache.
#
# Usage: sudo ./wifi-reconnect.sh [interface] [wait_seconds]
# Defaults: interface=en0, wait=5
#

GREEN="\033[92m"
RED="\033[91m"
YELLOW="\033[93m"
BOLD="\033[1m"
RESET="\033[0m"

INTERFACE="${1:-en0}"
WAIT_TIME="${2:-5}"

ok()   { echo -e "  [${GREEN} OK ${RESET}] $*"; }
warn() { echo -e "  [${YELLOW}WARN${RESET}] $*"; }
fail() { echo -e "  [${RED}FAIL${RESET}] $*"; }
step() { echo -e "\n${BOLD}--- $* ---${RESET}"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR:${RESET} This script must be run as root."
    echo "  Run: sudo $0"
    exit 1
fi

echo -e "\n${BOLD}=== WiFi Full Network Reset ===${RESET}\n"

# ---------------------------------------------------------------
# 0. Snapshot current WiFi state before touching anything
# ---------------------------------------------------------------
AIRPORT=/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport
CURRENT_CHANNEL=$("$AIRPORT" -I 2>/dev/null | awk '/channel:/{print $2}')
CURRENT_SSID=$("$AIRPORT" -I 2>/dev/null | awk '/^ SSID:/{print $2}')
CURRENT_RSSI=$("$AIRPORT" -I 2>/dev/null | awk '/agrCtlRSSI:/{print $2}')

echo "Before:"
echo "  SSID:    ${CURRENT_SSID:-unknown}"
echo "  Channel: ${CURRENT_CHANNEL:-unknown}"
echo "  Signal:  ${CURRENT_RSSI:-unknown} dBm"

# ---------------------------------------------------------------
# 1. Flush stale Netskope utun default routes
#    utun0-3 reserved (macOS system + Cisco), utun4+ are Netskope.
#    Stale = no IPv4 address, not the highest-numbered (live session).
# ---------------------------------------------------------------
step "1. Flush stale Netskope utun routes"

# Collect utun4+ that have a default IPv6 route
mapfile -t utuns_with_route < <(
    netstat -nrf inet6 2>/dev/null \
    | awk '$1=="default"{print $NF}' \
    | grep -E '^utun([4-9]|[0-9]{2,})$' \
    | sort -V
)

UTUN_REMOVED=0
if [[ ${#utuns_with_route[@]} -eq 0 ]]; then
    ok "No stale utun default routes found"
else
    # Protect the highest-numbered one (Netskope's live session)
    highest=""
    for iface in "${utuns_with_route[@]}"; do
        num="${iface#utun}"
        if [[ -z "$highest" ]] || (( num > ${highest#utun} )); then
            highest="$iface"
        fi
    done

    for iface in "${utuns_with_route[@]}"; do
        [[ "$iface" == "$highest" ]] && continue
        # Skip if it has an IPv4 address (unexpectedly active)
        if ifconfig "$iface" 2>/dev/null | grep -q '^\s*inet '; then
            warn "Skipping $iface — has IPv4 address"
            continue
        fi
        if route delete -inet6 default -ifscope "$iface" &>/dev/null; then
            ok "Removed stale default route: $iface"
            UTUN_REMOVED=$(( UTUN_REMOVED + 1 ))
        else
            warn "Could not remove route for $iface (may be gone already)"
        fi
    done

    REMAINING=$(netstat -nrf inet6 2>/dev/null | awk '$1=="default"{print $NF}' | grep -cE '^utun' || true)
    ok "Done — removed $UTUN_REMOVED stale route(s), $REMAINING utun default route(s) remain"
fi

# ---------------------------------------------------------------
# 2. Enforce IPv6 off on all network interfaces
# ---------------------------------------------------------------
step "2. Enforce IPv6 off"

IPV6_FIXED=0
while IFS= read -r svc; do
    [[ "$svc" == \** ]] && continue
    current=$(networksetup -getinfo "$svc" 2>/dev/null | awk '/IPv6:/{print $2}')
    if [[ "$current" != "Off" ]]; then
        networksetup -setv6off "$svc" 2>/dev/null && \
            ok "IPv6 disabled: $svc" || warn "Could not disable IPv6: $svc"
        IPV6_FIXED=$(( IPV6_FIXED + 1 ))
    fi
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)


if [[ $IPV6_FIXED -eq 0 ]]; then
    ok "All interfaces already had IPv6 off"
fi

# ---------------------------------------------------------------
# 3. Reconnect WiFi
# ---------------------------------------------------------------
step "3. Reconnect WiFi ($INTERFACE)"

echo -e "  Disconnecting..."
if ifconfig "$INTERFACE" down 2>/dev/null; then
    ok "Interface down"
else
    fail "Could not bring $INTERFACE down"
    exit 1
fi

echo "  Waiting ${WAIT_TIME}s..."
sleep "$WAIT_TIME"

echo -e "  Reconnecting..."
if ifconfig "$INTERFACE" up 2>/dev/null; then
    ok "Interface up"
else
    fail "Could not bring $INTERFACE up"
    exit 1
fi

echo "  Waiting 10s for association..."
sleep 10

# ---------------------------------------------------------------
# 4. Flush DNS cache
# ---------------------------------------------------------------
step "4. Flush DNS cache"

dscacheutil -flushcache 2>/dev/null && \
    killall -HUP mDNSResponder 2>/dev/null && \
    ok "DNS cache flushed" || warn "Could not flush DNS cache"

# ---------------------------------------------------------------
# 5. Results
# ---------------------------------------------------------------
step "5. Results"

NEW_CHANNEL=$("$AIRPORT" -I 2>/dev/null | awk '/channel:/{print $2}')
NEW_SSID=$("$AIRPORT" -I 2>/dev/null | awk '/^ SSID:/{print $2}')
NEW_RSSI=$("$AIRPORT" -I 2>/dev/null | awk '/agrCtlRSSI:/{print $2}')
DEFAULT_COUNT=$(netstat -nr 2>/dev/null | grep -c "^default" || echo "?")

echo ""
echo "  After:"
echo "  SSID:           ${NEW_SSID:-unknown}"
if [[ "$NEW_CHANNEL" != "$CURRENT_CHANNEL" ]]; then
    echo -e "  Channel:        ${GREEN}${CURRENT_CHANNEL} → ${NEW_CHANNEL}${RESET} (changed)"
else
    echo "  Channel:        ${NEW_CHANNEL:-unknown} (same)"
fi
echo "  Signal:         ${NEW_RSSI:-unknown} dBm"
echo "  Default routes: ${DEFAULT_COUNT}"

echo ""
# Quick connectivity check
if ping -c 3 -t 5 8.8.8.8 &>/dev/null; then
    ok "Connectivity confirmed (ping 8.8.8.8)"
else
    warn "Ping 8.8.8.8 failed — give it a few more seconds and retry"
fi

echo ""
echo -e "${BOLD}=== Done ===${RESET}"
echo ""
echo "Monitor:"
echo "  netstat -nr | grep '^default' | wc -l   # should be ≤ 4"
echo "  ping -c 30 8.8.8.8                       # check for spikes"
echo ""
