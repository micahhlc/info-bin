#!/bin/bash
#
# utun-cleanup.sh
# Removes stale utun default routes AND dead utun interfaces that accumulate
# after repeated Cisco/Netskope VPN connect/disconnect cycles on macOS.
# Left unchecked, dead utuns block routing entirely — requiring a reboot.
#
# Background:
#   Netskope and Cisco VPN each create utun interfaces on connect and leave
#   behind stale default routes and orphaned interfaces on disconnect. The
#   kernel cycles through all default routes, dropping packets on dead ones.
#   Enough dead utuns can starve the routing table and kill internet access.
#
# Liveness rule (the only guard that matters):
#   A utun is ALIVE if ifconfig shows an "inet " address on it.
#   A utun is DEAD  if it has no "inet " address.
#   Dead utuns: routes removed, owning process killed (launchd restarts clean).
#
# Usage: run as root (via launchd or: sudo ./utun-cleanup.sh)
#        sudo ./utun-cleanup.sh --force   remove ALL utun default routes, even active ones;
#                                         also kills known VPN daemons if no live utuns exist
#        sudo ./utun-cleanup.sh --reset   (legacy alias — interface cleanup now runs every cycle)
# Log:   /var/log/utun-cleanup.log
#
# Every run also: flushes DNS cache, reloads mDNSResponder, removes stale /etc/resolver/ files.
#

LOG=/var/log/utun-cleanup.log
SCRIPT_NAME="utun-cleanup"

# Fall back to stderr if log file isn't writable (e.g., running without sudo)
if ! touch "$LOG" 2>/dev/null; then
    LOG=/dev/stderr
fi
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
    log "No utun default routes found — skipping route cleanup"
else
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
        log "Route cleanup done. Removed $cleaned stale default route(s)."
    fi
fi

# ------------------------------------------------------------
# 3. Interface cleanup — runs every cycle (not just --reset).
#    Three-step approach for macOS Sonoma where system extensions
#    (Netskope, Cisco) run sandboxed and lsof may not see them:
#      a) Try ifconfig destroy on every dead utun (works for
#         truly orphaned interfaces).
#      b) Use lsof to find process-owned dead utuns and kill the
#         owning process ONLY if it owns NO active utuns at all.
#      c) Log before/after counts.
# ------------------------------------------------------------

# Find active utuns: all with an inet address (space-delimited string, bash 3.2 compatible)
active_utuns_list=""
for iface in $(ifconfig -l | tr ' ' '\n' | grep -E '^utun[0-9]+$'); do
    if ifconfig "$iface" 2>/dev/null | grep -q '^\s*inet '; then
        active_utuns_list="$active_utuns_list $iface"
    fi
done

# Helper: is_active <iface>
is_active() { echo " $active_utuns_list " | grep -qw "$1"; }

if [[ -n "$active_utuns_list" ]]; then
    log "Active utun interfaces (skipping):$active_utuns_list"
else
    log "No active utun interfaces found (none have an inet address)"
fi

before=$(ifconfig -l | tr ' ' '\n' | grep -cE '^utun[0-9]+$')
destroyed=0

# 3a. Try ifconfig destroy on each dead utun (no-op if process-owned).
for iface in $(ifconfig -l | tr ' ' '\n' | grep -E '^utun[0-9]+$'); do
    is_active "$iface" && continue
    if ifconfig "$iface" destroy 2>/dev/null; then
        log "DESTROY $iface succeeded (orphaned interface)"
        destroyed=$(( destroyed + 1 ))
    fi
done

# 3b. For any dead utuns still present, find their owning processes via lsof.
#     Collect all matching lines, then iterate unique PIDs. Kill a process only
#     if ALL its utuns are dead (avoids killing a process that owns a live utun too).
lsof_lines=$(lsof 2>/dev/null | grep -E "utun_control|com\.apple\.net\.utun")
unique_pids=$(echo "$lsof_lines" | awk 'NF{print $2}' | sort -u)

killed=0
for pid in $unique_pids; do
    [[ -z "$pid" ]] && continue
    pid_lines=$(echo "$lsof_lines" | awk -v p="$pid" '$2 == p')
    proc=$(echo "$pid_lines" | awk '{print $1}' | head -1)

    has_active=0
    dead_ifaces=""
    while IFS= read -r line; do
        unit=$(echo "$line" | grep -oE 'unit [0-9]+' | grep -oE '[0-9]+')
        [[ -z "$unit" ]] && continue
        iface="utun$(( unit - 1 ))"
        if is_active "$iface"; then
            has_active=1
        else
            dead_ifaces="$dead_ifaces $iface"
        fi
    done <<< "$pid_lines"

    if [[ $has_active -eq 1 ]]; then
        log "SKIP $proc (PID $pid): owns active utun(s), not killing"
        continue
    fi
    [[ -z "$dead_ifaces" ]] && continue
    # rapportd (AirDrop/Handoff) and identityservicesd (iMessage/FaceTime) use
    # IPv6-only utuns legitimately — killing them breaks Apple features with no benefit.
    # Their stale routes are already removed above; just leave the processes alone.
    if [[ "$proc" == "rapportd" || "$proc" == "identitys" ]]; then
        log "SKIP $proc (PID $pid): Apple system process, routes cleaned but process preserved"
        continue
    fi
    log "KILL $proc (PID $pid) owns only dead utun(s):$dead_ifaces — launchd will restart"
    kill -SIGTERM "$pid" 2>/dev/null && killed=$(( killed + 1 ))
done

if (( destroyed > 0 || killed > 0 )); then
    sleep 2
fi

# 3c. ifconfig down fallback — for dead utuns still present after destroy/kill,
#     bring them administratively down so the kernel stops routing through them.
downed=0
for iface in $(ifconfig -l | tr ' ' '\n' | grep -E '^utun[0-9]+$'); do
    is_active "$iface" && continue
    if ifconfig "$iface" down 2>/dev/null; then
        log "DOWN $iface (destroy unavailable, brought interface down)"
        downed=$(( downed + 1 ))
    fi
done

# 3d. Known-process kill — lsof is blind to sandboxed system extensions on Sonoma.
#     Only kill known VPN daemons when no active utuns exist (safe to restart all).
if [[ -z "$active_utuns_list" ]]; then
    for proc_pattern in "vpnagentd" "acumbrellaagent" "NetskopeClientMacAppProxy"; do
        pid=$(pgrep -x "$proc_pattern" 2>/dev/null)
        [[ -z "$pid" ]] && pid=$(pgrep -f "$proc_pattern" 2>/dev/null | head -1)
        [[ -z "$pid" ]] && continue
        log "KILL $proc_pattern (PID $pid) — no active utuns, safe to restart"
        kill -SIGTERM "$pid" 2>/dev/null && killed=$(( killed + 1 ))
    done
fi

after=$(ifconfig -l | tr ' ' '\n' | grep -cE '^utun[0-9]+$')
if (( destroyed > 0 || killed > 0 || downed > 0 )); then
    log "Interface cleanup done. Destroyed $destroyed, downed $downed, killed $killed process(es). utun count: $before → $after"
elif (( before > 0 )); then
    log "WARN: $before dead utun(s) present but none removed (system extension sandboxing may block). utun count unchanged: $after"
fi

# ------------------------------------------------------------
# 4. DNS cleanup — always runs after interface sweep.
#    - Remove stale /etc/resolver/ files for dead utun interfaces.
#    - Flush DNS cache and signal mDNSResponder to reload.
#    - Log surviving nameservers for diagnostics.
# ------------------------------------------------------------
dns_removed=0
if [[ -d /etc/resolver ]]; then
    for rfile in /etc/resolver/*; do
        [[ -f "$rfile" ]] || continue
        rbase=$(basename "$rfile")
        if echo "$rbase" | grep -qE '^utun[0-9]+$'; then
            if ! is_active "$rbase"; then
                log "REMOVE stale resolver file /etc/resolver/$rbase"
                rm -f "$rfile" && dns_removed=$(( dns_removed + 1 ))
            fi
        fi
    done
fi

dscacheutil -flushcache 2>/dev/null && log "DNS cache flushed (dscacheutil)"
killall -HUP mDNSResponder 2>/dev/null && log "mDNSResponder reloaded"

ns_list=$(scutil --dns 2>/dev/null | awk '/nameserver/{print $3}' | sort -u | tr '\n' ' ')
log "DNS nameservers after cleanup: ${ns_list:-none}"

exit 0
