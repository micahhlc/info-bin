# Network Troubleshooting — Quick Reference

**Machine:** MacBook Pro, macOS 14.3.1 (Sonoma)
**Last Updated:** 2026-06-01

---

## Status

| Issue | Root Cause | Status |
|-------|-----------|--------|
| Periodic blackouts every ~90s | Netskope stale utun routes | ✅ Fixed — daemon running |
| DNS slow / wrong nameservers | Cisco VPN pushes bad DNS on connect | ✅ Fixed — daemon flushes on cleanup |
| IPv6 re-enabled by VPN | Netskope/Cisco re-enables on tunnel reconnect | ✅ Fixed — daemon running |
| Ping spikes 100–1250ms every 44s | CyberArk EPM at 100% CPU (scan interval too aggressive) | ⏳ IT ticket pending — Request #778550675 |

---

## Quick Triage

```bash
# 1. Default route count — should be 1 (just en0)
netstat -nr | grep "^default"

# 2. Daemon health
sudo launchctl list com.micah.utun-cleanup
sudo launchctl list com.micah.disable-ipv6

# 3. Daemon logs
tail -20 /var/log/utun-cleanup.log

# 4. DNS resolvers — should only show 10.0.63.3, 10.0.2.1, 10.0.1.20
scutil --dns | grep nameserver

# 5. CyberArk CPU — if >100%, it's causing your ping spikes
ps aux | grep -i cyberark | grep -v grep | awk '{print $3, $11}'
```

---

## Symptom → Fix

### Blackouts / "No route to host"
```bash
# Check — should be just 1 default route via en0
netstat -nr | grep "^default"

# Manual fix (daemon usually catches this first)
sudo ./utun-cleanup.sh --force

# Nuclear option
sudo ../wifi-reconnect.sh
```

### Slow DNS / wrong nameservers after VPN
```bash
# Check
scutil --dns | grep nameserver

# Fix — flush everything
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

# Or run the cleanup script (also does DNS)
sudo ./utun-cleanup.sh
```

### IPv6 re-enabled after VPN reconnect
```bash
networksetup -getinfo Wi-Fi | grep IPv6

# Fix
sudo ./disable-ipv6-permanent.sh
```

### Ping spikes every ~44s (100–1250ms)
**CyberArk EPM scan interval too aggressive — IT ticket filed.**
```bash
# Confirm it's CyberArk
ps aux | grep -i cyberark | grep -v grep | awk '{print $3, $11}'
# If CPU column shows ~100, that's the cause

# Monitor and capture spikes
./ping-spike-capture.sh
```
IT ticket: **Request #778550675** — requesting EPM scan interval reduced from 44s → ≥300s.
Evidence: `cyberark-evidence/`

---

## Running Daemons

| Daemon | Interval | What it does |
|--------|----------|-------------|
| `com.micah.utun-cleanup` | Every 2 min | Removes dead utun interfaces, flushes DNS |
| `com.micah.disable-ipv6` | At boot | Re-applies IPv6 off after VPN re-enables it |

```bash
# Verify both running
sudo launchctl list com.micah.utun-cleanup
sudo launchctl list com.micah.disable-ipv6

# Reinstall after fresh machine
sudo ./install-utun-cleanup.sh
sudo ./disable-ipv6-permanent.sh
```

---

## Files

| File | Purpose |
|------|---------|
| `utun-cleanup.sh` | Stale utun route + DNS cleanup (runs via daemon) |
| `disable-ipv6-permanent.sh` | 3-layer IPv6 disable |
| `install-utun-cleanup.sh` | Reinstall utun daemon after reboot/fresh machine |
| `com.micah.utun-cleanup.plist` | launchd config for utun daemon |
| `ping-spike-capture.sh` | Monitor pings, capture culprit process on spike |
| `cyberark-evidence/` | Evidence package for IT ticket #778550675 |
| `IT_TICKET_netskope_utun_leak.md` | Netskope utun leak IT ticket (separate issue) |
