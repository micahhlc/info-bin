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
#   identityservicesd (iMessage/Handoff) also leaks utun interfaces over time.
#
# Liveness rule (the only guard that matters):
#   A utun is ALIVE if ifconfig shows an "inet " address on it.
#   A utun is DEAD  if it has no "inet " address — clean its default routes.
#   No hardcoded number ranges. utun0, utun1, utun2 are dead → cleaned too.
#
# Usage: run as root (via launchd or: sudo ./utun-cleanup.sh)
#        sudo ./utun-cleanup.sh --force   remove ALL utun default routes, even active ones
#        sudo ./utun-cleanup.sh --reset   kill ghost utun owners so launchd can restart them clean
# Log:   /var/log/utun-cleanup.log
#

LOG=/var/log/utun-cleanup.log
SCRIPT_NAME="utun-cleanup"
FORCE=0
RESET=0
[[ "${1:-}" == "--force" ]] && FORCE=1
[[ "${1:-}" == "--reset" || "${2:-}" == "--reset" ]] && RESET=1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME] $*" >> "$LOG"
}

_mode=""
(( FORCE )) && _mode+=" (--force mode)"
(( RESET )) && _mode+=" (--reset mode)"
log "Script started${_mode}"
unset _mode

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

    # ALIVE — has an IPv4 address assigned, skip unless --force.
    if ifconfig "$iface" 2>/dev/null | grep -q '^\s*inet '; then
        if (( FORCE )); then
            log "FORCE removing active utun $iface (--force mode)"
        else
            log "SKIP $iface: has IPv4 address, leaving alone"
            continue
        fi
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

# ------------------------------------------------------------
# 3. --reset mode: kill all processes owning utun interfaces
#    except the active VPN tunnel. They restart via launchd.
#    Run manually when ghost utun interfaces accumulate.
#    Note: ifconfig utunN destroy is rejected by the kernel for
#    process-owned utun interfaces (SIOCIFDESTROY: Invalid argument).
#    The only way to release them is to kill the owning process.
# ------------------------------------------------------------
if (( RESET )); then

    # Find active VPN: highest-numbered utun with an inet address
    active_utun=""
    for iface in $(ifconfig -l | tr ' ' '\n' | grep -E '^utun[0-9]+$' \
                   | sort -t n -k 1.5 -rn); do
        if ifconfig "$iface" 2>/dev/null | grep -q '^\s*inet '; then
            active_utun="$iface"
            break
        fi
    done
    log "Active VPN tunnel: ${active_utun:-none}"

    before=$(ifconfig -l | tr ' ' '\n' | grep -cE '^utun[0-9]+$')
    killed=0

    while IFS= read -r line; do
        proc=$(awk '{print $1}' <<< "$line")
        pid=$(awk '{print $2}' <<< "$line")
        # lsof reports "unit N" where N maps to utunN-1 (unit 1 = utun0, etc.)
        unit=$(grep -oE 'unit [0-9]+' <<< "$line" | grep -oE '[0-9]+')
        iface="utun$(( unit - 1 ))"

        # Skip owner of active VPN tunnel
        if [[ "$iface" == "$active_utun" ]]; then
            log "SKIP $proc (PID $pid): owns active VPN $active_utun"
            continue
        fi

        log "KILL $proc (PID $pid) owns $iface — launchd will restart"
        kill -SIGTERM "$pid" 2>/dev/null && killed=$(( killed + 1 ))
    done < <(lsof 2>/dev/null | grep "utun_control" | sort -k2,2 -u)

    sleep 2
    after=$(ifconfig -l | tr ' ' '\n' | grep -cE '^utun[0-9]+$')
    log "--reset done. Killed $killed process(es). utun count: $before → $after"
fi

exit 0
