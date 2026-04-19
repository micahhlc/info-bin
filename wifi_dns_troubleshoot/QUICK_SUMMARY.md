# WiFi / DNS Troubleshooting Guide

**Machine:** MacBook Pro, macOS 14.3.1 (Sonoma)
**Last Updated:** 2026-04-15

---

## Quick Diagnosis

Run this first — it checks everything:
```bash
sudo ./wifi-diagnostic.sh
```

Watch for:
- **Section 9** — "Routing Table Audit" → stale utun routes (>4 = problem)
- **Section 10** — "DNS Diagnostic" → slow AAAA queries, dead nameservers


**Check DNS/Route issue**
```bash
# 1. See your current default route
route get default

# 2. See ALL routes (verbose)
netstat -rn | grep -E "^(Destination|default|0\.0\.0\.0)"

# 3. Check active VPN interfaces
ifconfig | grep -E "^utun|^tap"

# 4. Check DNS (system-wide)
scutil --dns | head -30

# 5. Check if Netskope/Cisco services are running
launchctl list | grep -i "netskope\|cisco\|umbrella\|anyconnect"

# 6. See which interface owns the default route
route get default | grep interface

# 7. Check for route conflicts (multiple default routes)
netstat -rn | grep -c "^default"

```
---

## Symptom → Root Cause → Fix

### Symptom: Periodic "No route to host" / total blackout every ~90 seconds

**Root cause:** Netskope accumulates stale utun default routes. Each reconnect adds a new `utunN` but never removes the old one. Kernel cycles through dead routes → blackout.

**Quick check:**
```bash
netstat -nr | grep "^default" | wc -l    # should be ≤ 4
netstat -nrf inet6 | grep "^default"     # look for utun4, utun5, ... stale ones
```

**Fix — daemon (permanent, runs every 2 min):**
```bash
sudo launchctl list com.micah.utun-cleanup    # verify running
cat /var/log/utun-cleanup.log                 # check last run
```

**Fix — manual reset (when things feel bad now):**
```bash
sudo ./wifi-reconnect.sh
```

**Fix - DNS issue**
```bash
sudo networksetup -setdnsservers Wi-Fi "Empty"
```



---

### Symptom: Slow DNS / connections feel sluggish on first request

**Root cause:** Corporate DNS server `10.0.63.4` takes up to 575ms for AAAA (IPv6) queries. Also: stale dead Cisco Umbrella IPv6 nameserver `fe80::ec81:50ff:fe51:b864%en0` times out on every lookup.

**Quick check:**
```bash
dig @10.0.63.4 www.google.com AAAA    # should be fast; if >200ms = slow server
scutil --dns | head -30               # check active nameservers
```

**Fix — remove slow DNS server:**
```bash
networksetup -setdnsservers Wi-Fi 10.0.63.3 10.0.2.1 10.0.1.20
# (omits 10.0.63.4 — the slow AAAA server)
```

**Revert to DHCP defaults:**
```bash
networksetup -setdnsservers Wi-Fi "Empty"
```

---

### Symptom: Random 50–900ms jitter even after fixes

**Root cause:** Netskope SSL inspection overhead. Every connection is inspected at variable latency. This is **expected behavior** for corporate DLP/CASB proxy.

**Cannot be fixed locally** — requires IT to add SSL inspection exemptions for trusted traffic.

---

### Symptom: IPv6 got re-enabled after VPN reconnect

**Root cause:** Netskope/Cisco re-enables IPv6 when tunnels come up.

**Check:**
```bash
networksetup -getinfo Wi-Fi | grep IPv6
sysctl net.inet6.ip6.accept_rtadv        # read-only on macOS — ignore this value
sudo launchctl list com.micah.disable-ipv6    # should be present
```

**Fix:**
```bash
sudo ./disable-ipv6-permanent.sh         # re-applies all 3 layers
```

---

## Installed Daemons (Permanent Fixes)

| Daemon | Interval | Purpose |
|--------|----------|---------|
| `com.micah.utun-cleanup` | Every 2 min | Remove stale Netskope utun default routes |
| `com.micah.disable-ipv6` | At boot | Re-apply IPv6 off after VPN re-enables it |

**Check both are running:**
```bash
sudo launchctl list com.micah.utun-cleanup
sudo launchctl list com.micah.disable-ipv6
```

**Logs:**
```bash
tail -50 /var/log/utun-cleanup.log
tail -50 /var/log/disable-ipv6.log
```

---

## The "Everything Is Bad" Manual Reset

When the network feels completely broken — run this one command:
```bash
sudo ./wifi-reconnect.sh
```

It does (in order):
1. Flush all stale utun4+ default routes
2. Enforce IPv6 off on all interfaces
3. Bring en0 down → wait 5s → back up
4. Flush DNS cache (`dscacheutil` + restart `mDNSResponder`)
5. Show before/after state + ping connectivity check

---

## Verification After Fix

```bash
# Default routes only — should be ≤ 6 (en0 + utun0–3 + 1 live Netskope session)
# This is what the daemon monitors and cleans
netstat -nr | grep "^default" | wc -l

# All utun-related routes — baseline is 24 (4 interfaces × 6 routes each)
# Each utun interface has: 1 default + 1 link-local subnet + 1 link-local host + 3 multicast = 6
# This number alone is NOT a problem indicator — use default route count above instead
netstat -rn | grep utun | wc -l

# utun interface count — baseline is 4 (utun0–utun3)
netstat -rn | grep utun | awk '{print $NF}' | grep utun | sort -u

# Ping stability — should be ~10ms with no "No route to host"
ping -c 30 8.8.8.8

# DNS speed check
dig google.com A      # should be <50ms
dig google.com AAAA   # should also be <50ms if IPv6 disabled (no AAAA lookups)

# Daemon status
sudo launchctl list com.micah.utun-cleanup | grep -E "LastExitStatus|PID"
```

**Known-good baseline (post-reboot 2026-04-15):**
- Default routes: ~6 (en0 + utun0–3 + 1 live Netskope session) ← what daemon watches
- utun interfaces: 4 (`utun0–utun3`)
- All utun routes: 24 (4 interfaces × 6 route entries each) ← not a problem indicator
- Ping baseline: 9–25ms steady state

---

## Key Files

### Active Tools

| File                        | What It Does                                                |
| --------------------------- | ----------------------------------------------------------- |
| `wifi-diagnostic.sh`        | Full health check — run this first                          |
| `wifi-reconnect.sh`         | Full manual network reset (sudo required)                   |
| `utun-cleanup.sh`           | Manual stale route flush (also runs via daemon every 2 min) |
| `disable-ipv6-permanent.sh` | 3-layer IPv6 disable; `--undo` to revert                    |
| `install-utun-cleanup.sh`   | Reinstall utun cleanup daemon after reboot/fresh machine    |

### Archive — Investigation Tools

These were used to diagnose the root cause. Keep for reference, but not needed day-to-day.

| File                  | What It Does                                              |
| --------------------- | --------------------------------------------------------- |
| `check-wifi-hardware.sh` | WiFi driver stats (rxToss, CCA) — Session 1 diagnosis |
| `ping-correlate.sh`   | Capture system state during ping spikes                   |
| `netskope-test.sh`    | A/B test: Netskope on vs off (already disproven as cause) |
| `ping_stats.sh`       | Ping latency percentiles (p50/p90/p95/p99)                |
| `ping_stats.js`       | Node.js version of ping stats                             |
| `check_netskope.py`   | Netskope tunnel status + site reachability                |
| `netskope-analyzer.py` | Parse Netskope error logs for patterns                   |

### launchd Config

| File | What It Does |
|------|-------------|
| `com.micah.utun-cleanup.plist` | launchd plist for utun cleanup daemon (runs every 2 min as root) |

### Documentation

| File | What It Does |
|------|-------------|
| `QUICK_SUMMARY.md` | This file — troubleshooting guide |
| `FULL_SUMMARY.md` | Complete investigation history (both sessions, all findings) |
| `REAL_PROBLEM_ANALYSIS.md` | Session 1 root cause: WiFi channel congestion (rxToss, CCA) |
| `PING_ANALYSIS.md` | Session 1 ping spike analysis — 1600ms spikes, Netskope disproven |
| `NETSKOPE_EVIDENCE.md` | Session 1 evidence log (pre-disproven hypothesis) |

### Evidence / Logs

| File | What It Does |
|------|-------------|
| `IT_TICKET_netskope_utun_leak.md` | IT ticket to file with Netskope/IT team |
| `ping-correlation-20260401-155912.log` | Raw ping correlation log from 2026-04-01 |
| `netskope_before.txt` | Ping results with Netskope enabled (A/B test baseline) |
| `netskope_after.txt` | Ping results with Netskope disabled (A/B test result) |
| `netskope.log` | Raw Netskope log excerpts used for analysis |

---

## If You Reboot / Fresh Machine

Re-run the daemon installers once:
```bash
sudo ./install-utun-cleanup.sh          # utun cleanup daemon
sudo ./disable-ipv6-permanent.sh        # IPv6 disable daemon
```

Then verify:
```bash
sudo launchctl list com.micah.utun-cleanup
sudo launchctl list com.micah.disable-ipv6
```
