# info-bin — Claude Code Context

## What this repo is

Personal toolbox for macOS network troubleshooting scripts and docs.
Primary ongoing issue: **Netskope/Cisco VPN causes recurring DNS and routing problems on MacBook Pro (macOS 14.3.1 Sonoma)**.

---

## Ongoing Network Issue — Read This First

**Machine:** MacBook Pro, macOS 14.3.1 (Sonoma)
**Netskope version:** 126.0.9.2460
**Corporate VPN:** Cisco AnyConnect (`vpnagentd`) + Cisco Umbrella (`dnscryptproxy`)

This is a **recurring, unresolved issue** requiring periodic diagnosis. Every time the user reports network problems, start here before assuming a new root cause.

### Known root causes (confirmed)

1. **Netskope utun route leak** — Netskope accumulates stale `utunN` default routes every time it reconnects. Does NOT clean them up. After hours of uptime, the kernel selects dead routes → periodic blackouts every ~90s.
   - Workaround daemon installed: `com.micah.utun-cleanup` (runs every 2 min)
   - Check: `netstat -nr | grep "^default" | wc -l` → should be ≤ 6

2. **DNS corruption after Cisco VPN connect** — Cisco pushes DNS config changes on VPN connect but does not cleanly restore them on disconnect. Symptoms: slow DNS, wrong nameservers, dead nameservers in resolver chain. Restart currently the only known full fix. **Still under investigation.**
   - Known slow server: `10.0.63.4` (AAAA queries avg 199ms, max 575ms) — should be excluded
   - Known dead entry: `fe80::ec81:50ff:fe51:b864%en0` in Cisco Umbrella resolv.conf
   - Active dnscryptproxy listens on `127.0.0.1:53`, upstream `208.67.222.222`
   - Check: `scutil --dns | grep nameserver` — should only show `10.0.63.3`, `10.0.2.1`, `10.0.1.20`

3. **IPv6 re-enabled by Netskope/Cisco on tunnel reconnect** — daemon `com.micah.disable-ipv6` re-applies IPv6 off at boot.

### Known-good baseline (post-reboot 2026-04-15)

| Metric | Healthy value |
|--------|--------------|
| Default routes | ≤ 6 (`en0` + `utun0–3` + 1 live Netskope) |
| utun interfaces | 4 (`utun0–utun3`) |
| All utun route entries | 24 (4 × 6 — not a problem indicator) |
| Active DNS servers | `10.0.63.3`, `10.0.2.1`, `10.0.1.20` only |
| Ping baseline | 9–25ms steady state |

### Quick triage commands

```bash
# 1. Default route count (most important)
netstat -nr | grep "^default" | wc -l

# 2. Active DNS resolvers
scutil --dns | grep nameserver

# 3. Daemon health
sudo launchctl list com.micah.utun-cleanup
sudo launchctl list com.micah.disable-ipv6

# 4. Daemon logs
tail -30 /var/log/utun-cleanup.log
tail -30 /var/log/disable-ipv6.log

# 5. Full diagnostic
sudo ./wifi_dns_troubleshoot/wifi-diagnostic.sh
```

### When things feel bad — manual reset

```bash
sudo ./wifi-reconnect.sh
```

---

## Key files

| File | Purpose |
|------|---------|
| `wifi_dns_troubleshoot/QUICK_SUMMARY.md` | Symptom → fix cheat sheet |
| `wifi_dns_troubleshoot/FULL_SUMMARY.md` | Full investigation history (all sessions) |
| `wifi_dns_troubleshoot/IT_TICKET_netskope_utun_leak.md` | IT ticket filed for Netskope bug |
| `wifi_dns_troubleshoot/utun-cleanup.sh` | Manual stale route flush |
| `wifi_dns_troubleshoot/install-utun-cleanup.sh` | Re-install daemon after fresh machine |
| `wifi_dns_troubleshoot/disable-ipv6-permanent.sh` | 3-layer IPv6 disable |
| `wifi-diagnostic.sh` | Full health check |
| `wifi-reconnect.sh` | Full manual network reset |

---

## Open issues (not yet resolved)

- **DNS corruption on Cisco VPN connect/disconnect** — exact mechanism not yet identified. Need to capture `scutil --dns` before and immediately after VPN connect to catch what gets injected.
- **IT ticket pending response** — filed for Netskope utun leak bug (126.0.9.2460). Awaiting version check + AOAC config review.

---

## Investigation approach

When the user reports a new network symptom:
1. Check baseline metrics above first (routes, DNS, daemon status)
2. Compare to known-good baseline
3. Form a hypothesis with a testable A/B — don't assume causation from correlation (past mistake: assumed Netskope was cause in Session 1, disproven by A/B test)
4. Document findings in `FULL_SUMMARY.md` as a new session entry
5. Update `QUICK_SUMMARY.md` if a new fix is found
