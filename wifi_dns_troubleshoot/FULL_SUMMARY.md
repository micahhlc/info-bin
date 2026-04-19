# WiFi / DNS Troubleshooting — Full Investigation Summary

**Machine:** MacBook Pro, macOS 14.3.1 (Sonoma)
**Period:** 2026-04-01 → 2026-04-15
**Status:** Mostly resolved — daemon installed, IPv6 disabled
**Post-Reboot Baseline (2026-04-15):** 4 utun interfaces (utun0–3), 24 routes total — healthy

---

## Timeline of Investigations

### Session 1 — 2026-04-01: Initial WiFi instability

**Symptom:** Ping spikes up to 1600ms, colleagues unaffected.

**Tools built:**
- `wifi-diagnostic.sh` — full WiFi health check
- `netskope-test.sh` — A/B test Netskope impact
- `ping-correlate.sh` — log system state during spikes
- `check_netskope.py` — Netskope tunnel status
- `netskope-analyzer.py` — parse Netskope logs

**Hypothesis tested:** Netskope causing instability.

**Result:** DISPROVEN. A/B test showed disabling Netskope made things *worse*.

**Actual finding:** WiFi driver packet drops.
- `rxToss=65–102` — packets dropped by WiFi driver
- `CCA=21%` — channel 136 moderately congested
- Root cause: AP overload / channel congestion

---

### Session 2 — 2026-04-15: DNS investigation

**Symptom:** Network "feels messy" — user suspected DNS/VPN issue.

**DNS findings:**
- 4 corporate DNS servers pushed via DHCP: `10.0.63.3`, `10.0.63.4`, `10.0.2.1`, `10.0.1.20`
- `10.0.63.4` AAAA (IPv6) queries: avg 199ms, max **575ms** — much slower than A records
- Cisco Umbrella `dnscryptproxy` running even when VPN disconnected (upstream: `208.67.220.220`)
- Stale dead link-local IPv6 nameserver `fe80::ec81:50ff:fe51:b864%en0` in `/opt/cisco/secureclient/umbrella/resolv.conf` — times out on every lookup
- `en0` MTU: 1436 (not standard 1500) — reduced by Netskope/Cisco

**DNS config chain:**
```
macOS mDNSResponder
  → queries all 4 corporate servers in parallel
  → takes first response (A or AAAA)
  → if slow AAAA wins, connection uses slow IPv6 path
```

---

### Session 3 — 2026-04-15: Ping pattern analysis — root cause found

**Ping to `www.rakuten.co.jp` — key pattern:**
```
Baseline: ~8ms  (WiFi hardware is healthy)
Event:    "No route to host" × 5–8 seconds
Recovery: 8000ms → 7000ms → 6000ms → ... → 8ms  (staircase = queued packets draining)
Interval: ~90 seconds between events
```

**This is NOT WiFi, NOT DNS — it's routing table churn.**

**Root cause confirmed: 15 simultaneous default routes**

```
default  10.49.167.254   en0        ← WiFi (legitimate)
default  fe80::%utun0    utun0      ← macOS system
default  fe80::%utun1    utun1      ← macOS system
default  fe80::%utun2    utun2      ← macOS system
default  fe80::%utun3    utun3      ← Cisco VPN
default  fe80::%utun4    utun4      ← STALE Netskope
default  fe80::%utun5    utun5      ← STALE Netskope
...
default  fe80::%utun13   utun13     ← STALE Netskope
```

**Why:** Netskope creates a new `utun` interface each time it reconnects but never removes the old default route. After 2 days 7 hours uptime → 10 stale routes accumulated.

**Why ~90 seconds:** Netskope's session renegotiation timer. Every ~90s it briefly tears down and re-adds a utun route. During that gap, kernel selects a stale dead utun → `No route to host`.

**Netskope version:** 126.0.9.2460

---

## Fixes Applied

### Fix 1: IPv6 disabled (immediate improvement)

Disabling IPv6 reduced hard blackout rate 5x (1 per 62 pings → 1 per 300 pings) because the kernel could no longer select stale IPv6 default routes from dead utun interfaces.

**How it was done (3 layers):**
1. `networksetup -setv6off <interface>` — all network services
2. `/etc/sysctl.conf` — `net.inet6.ip6.accept_rtadv=0` (kernel-level, survives reboots)
3. `com.micah.disable-ipv6` launchd daemon — re-applies on boot in case VPN re-enables it

**Script:** `disable-ipv6-permanent.sh` (undo with `--undo` flag)

---

### Fix 2: utun cleanup daemon (permanent fix for blackouts)

**Script:** `/usr/local/bin/utun-cleanup.sh`
**Daemon:** `/Library/LaunchDaemons/com.micah.utun-cleanup.plist`
**Runs:** Every 2 minutes as root
**Log:** `/var/log/utun-cleanup.log`

**Logic:**
- Finds all `utun4+` interfaces with a default IPv6 route but no IPv4 address = stale Netskope sessions
- Protects: `utun0–3` (macOS system + Cisco), highest-numbered utun (live Netskope session)
- Removes stale default routes with `route delete -inet6 default -ifscope utunN`

**Result after first run:**
```
Removed 9 stale default route(s). 
Routes: 15 → 6 (en0 + utun0–3 + utun13 live session)
```

**Verify:** `sudo launchctl list com.micah.utun-cleanup` → `LastExitStatus = 0`

---

### Fix 3: wifi-reconnect.sh updated

All fixes consolidated into one manual reset command:
```bash
sudo ./wifi-reconnect.sh
```
Does in order: flush stale utun routes → enforce IPv6 off → reconnect WiFi → flush DNS cache → show results.

---

### Fix 4: wifi-diagnostic.sh updated

Added two new sections:
- **Section 9 — Routing Table Audit:** detects stale utun default routes, alerts if >4
- **Section 10 — DNS Diagnostic:** times A and AAAA queries per server, flags slow AAAA, detects dead Cisco Umbrella IPv6 nameserver

---

## IT Ticket

Filed as: `IT_TICKET_netskope_utun_leak.md`

**Asks:**
1. Confirm Netskope 126.0.9.2460 is latest for macOS 14.3.1
2. Check for known utun leak bug
3. Review AOAC (Always-On After Connect) config — may cause excessive tunnel churn
4. Escalate to Netskope TAC if no fix found

---

## Post-Reboot Baseline (2026-04-15)

After reboot, network fully reset. Measured state:

**Routing table:**
- 4 utun interfaces: `utun0`, `utun1`, `utun2`, `utun3`
- 24 total utun routes (6 route entries per interface: default + link-local subnet + link-local host + 3 multicast)
- ~6 default routes: `en0` + `utun0–3` + 1 live Netskope session
- No stale/orphaned utun interfaces

**Key distinction:**
- `netstat -rn | grep utun | wc -l` → **24** is normal (all utun route entries, not a problem indicator)
- `netstat -nr | grep "^default" | wc -l` → **≤6** is healthy (what the daemon actually watches/cleans)

**Ping to `www.rakuten.co.jp` (187 samples):**
- Baseline: 9–25ms
- Startup instability (seq 0–25): spikes up to 1314ms, 1 timeout — expected (VPN + routing rebuild)
- Steady state (seq 26+): isolated spikes 50–91ms, no 500ms+ events
- Pre-reboot comparison: sustained 300–1300ms storms → now clean

**Monitoring note:** Watch `netstat -nr | grep "^default" | wc -l` over time. If default routes climb back above 10+, the Netskope utun leak is recurring and the daemon interval may need tightening. Also watch for the startup instability window growing longer with uptime.

---

## Remaining Jitter (post-fix)

After IPv6 disable + daemon install, random 50–900ms jitter remains (23% of pings >100ms). This is likely **Netskope SSL inspection overhead** — every connection is inspected at variable latency. This is expected behavior for a corporate DLP/CASB proxy and cannot be fixed locally; requires IT/Netskope policy change (exemptions for trusted traffic).

---

## Files in This Repo

| File | Purpose |
|------|---------|
| `wifi-diagnostic.sh` | Full health check — signal, routing, DNS, VPN |
| `wifi-reconnect.sh` | One-shot full network reset |
| `utun-cleanup.sh` | Flush stale Netskope utun routes (also at `/usr/local/bin/`) |
| `install-utun-cleanup.sh` | Install utun cleanup launchd daemon |
| `com.micah.utun-cleanup.plist` | launchd plist (also at `/Library/LaunchDaemons/`) |
| `disable-ipv6-permanent.sh` | Permanently disable IPv6 across 3 layers |
| `check_netskope.py` | Netskope tunnel + site reachability check |
| `netskope-analyzer.py` | Parse Netskope error logs |
| `netskope-test.sh` | A/B test: Netskope on vs off |
| `ping-correlate.sh` | Log system state during ping spikes |
| `check-wifi-hardware.sh` | WiFi hardware/driver check |
| `wifi-reconnect.sh` | Force WiFi reconnect |
| `IT_TICKET_netskope_utun_leak.md` | IT ticket for Netskope utun leak bug |
| `REAL_PROBLEM_ANALYSIS.md` | Session 1 root cause analysis (channel congestion) |
