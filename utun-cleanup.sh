#!/bin/bash
#
# utun-cleanup.sh
# Removes stale utun default routes (IPv4 + IPv6) that accumulate over time
# and cause periodic network blackouts (~90s cycles) on macOS.
#
# Background:
#   Netskope and Cisco VPN each create utun interfaces on connect and leave
#   behind stale default routes on disconnect. The kernel cycles through all
#   default routes, dropping packets each time it hits a dead one.
#
# Liveness rule (the only guard that matters):
#   A utun is ALIVE if ifconfig shows an "inet " address on it.
#   A utun is DEAD  if it has no "inet " address — clean its default routes.
#   No hardcoded number ranges. utun0, utun1, utun2 are dead → cleaned too.
#
# Usage: run as root (via launchd or: sudo ./utun-cleanup.sh)
# Log:   /var/log/utun-cleanup.log
#

LOG=/var/log/utun-cleanup.log
SCRIPT_NAME="utun-cleanup"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME] $*" >> "$LOG"
}

# ------------------------------------------------------------
# Helper: list utunN interfaces that have a default route for
#         a given address family (inet or inet6).
# ------------------------------------------------------------
utuns_for_family() {
    local family="$1"
    netstat -nrf "$family" 2>/dev/null \
        | awk '$1 == "default" { print $NF }' \
        | grep -E '^utun[0-9]+$'
}

# ------------------------------------------------------------
# 1. Collect all utun interfaces with any default route.
# ------------------------------------------------------------
all_candidate_utuns=()
while IFS= read -r line; do
    all_candidate_utuns+=("$line")
done < <(
    { utuns_for_family inet; utuns_for_family inet6; } \
        | sort -u \
        | sort -t n -k 1.5 -n
)

if [[ ${#all_candidate_utuns[@]} -eq 0 ]]; then
    exit 0
fi

# ------------------------------------------------------------
# 2. For each candidate: skip if alive (has inet addr),
#    otherwise remove its stale default routes.
# ------------------------------------------------------------
cleaned=0

for iface in "${all_candidate_utuns[@]}"; do

    # ALIVE — has an IPv4 address assigned, skip it.
    if ifconfig "$iface" 2>/dev/null | grep -q '^\s*inet '; then
        continue
    fi

    # DEAD — no inet address. Remove stale default routes.

    if utuns_for_family inet | grep -qx "$iface"; then
        log "REMOVE stale IPv4 default route via $iface"
        if route delete -inet default -ifscope "$iface" >> "$LOG" 2>&1; then
            log "OK removed IPv4 default route for $iface"
            cleaned=$(( cleaned + 1 ))
        else
            log "WARN route delete failed for $iface IPv4 (may already be gone)"
        fi
    fi

    if utuns_for_family inet6 | grep -qx "$iface"; then
        log "REMOVE stale IPv6 default route via $iface"
        if route delete -inet6 default -ifscope "$iface" >> "$LOG" 2>&1; then
            log "OK removed IPv6 default route for $iface"
            cleaned=$(( cleaned + 1 ))
        else
            log "WARN route delete failed for $iface IPv6 (may already be gone)"
        fi
    fi

done

if (( cleaned > 0 )); then
    log "Done. Removed $cleaned stale default route(s)."
fi

exit 0
