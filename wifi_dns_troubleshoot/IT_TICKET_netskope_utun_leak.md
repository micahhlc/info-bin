# IT Support Ticket — Netskope: Stale utun Interface Leak Causing Periodic Network Blackouts

---

## Ticket Metadata

| Field | Value |
|---|---|
| **Priority** | High |
| **Category** | Network / VPN / Netskope |
| **Reported Date** | 2026-04-15 |
| **Device** | MacBook Pro |
| **OS Version** | macOS 14.3.1 (Sonoma) |
| **Netskope Client Version** | 126.0.9.2460 |

---

## 1. Summary

Netskope Client 126.0.9.2460 on macOS 14.3.1 fails to clean up utun (tunnel) interfaces from previous sessions, causing 15 simultaneous default routes to accumulate in the routing table. This results in periodic 5–10 second network blackouts occurring approximately every 90 seconds.

---

## 2. Impact

- **Symptom:** Complete loss of network connectivity for 5–10 seconds at a time, repeating approximately every 90 seconds.
- **Frequency:** 8 confirmed blackout events observed in under 8 minutes of continuous monitoring.
- **User Experience:** All network-dependent applications (browser, email, Slack, SSH sessions, video calls) drop simultaneously during each blackout event. After each blackout, connections recover over a staircase-pattern drain (approximately 8 seconds to full recovery) as queued packets flush.
- **Business Impact:** Interrupts video conferences, causes dropped SSH/VPN sessions, and creates intermittent failures in any application that does not tolerate multi-second connectivity gaps. The issue worsens over time as the machine runs longer without a Netskope process restart — more stale utun sessions accumulate the longer the process has been running.

---

## 3. Root Cause

When the Netskope client creates a new tunnel session, it allocates a new utun interface (e.g., `utun14`) and injects a default route (`0.0.0.0/0`) pointing to that interface. On session teardown or reconnect, Netskope is not removing the old utun interface or its associated default route from the routing table.

Over time, the routing table accumulates one stale default route per Netskope session. With multiple low-priority stale routes present alongside the legitimate active route (`utun14`) and the WiFi interface (`en0`), macOS route selection becomes non-deterministic. Outbound packets are intermittently routed to dead utun interfaces that have no associated IPv4 address, resulting in `sendto: No route to host` errors until the kernel retries a working route.

The stale utun interfaces are identifiable because they carry only an IPv6 link-local address (`inet6 fe80::`) and no IPv4 address — confirming they are remnants of terminated sessions with no active tunnel.

The underlying WiFi hardware is not at fault. Baseline ping latency is ~8ms and the connection is otherwise stable between blackout events.

---

## 4. Evidence

### 4a. Routing Table at Time of Diagnosis

At the time of diagnosis, the routing table contained **15 simultaneous default routes**:

| Interface | Status |
|---|---|
| `en0` (WiFi) | Active — legitimate |
| `utun0` – `utun3` | Expected — macOS system tunnels (e.g., mDNS, iCloud Private Relay) |
| `utun4` – `utun13` | **Stale leaked routes — no IPv4 address, dead sessions** |
| `utun14` | Active — current Netskope session |

Normal expected state: 1 (`en0`) + 2–3 macOS system utun interfaces.
Observed state: 10 additional stale Netskope utun interfaces with orphaned default routes.

All stale interfaces (`utun4`–`utun13`) confirmed dead: they carry only `inet6 fe80::` link-local addresses and no IPv4 address.

### 4b. Ping Log Pattern

Continuous ping to `www.rakuten.co.jp` over approximately 8 minutes:

- **Baseline RTT:** ~8ms (confirms WiFi hardware is healthy)
- **Blackout events:** `ping: sendto: No route to host` errors lasting 5–10 seconds per event
- **Recovery pattern:** Staircase RTT decrease after each blackout (8000ms → 7000ms → 6000ms → ... → 8ms) — consistent with a queue of packets draining after route re-selection
- **Blackout interval:** Stabilized at approximately 90 seconds between events
- **Total events observed:** 8 blackouts in under 8 minutes

### 4c. Process Uptimes

| Process | Uptime | Significance |
|---|---|---|
| `NetskopeClientMacAppProxy` | 2 days, 7 hours | Accumulated 14 stale utun sessions over this runtime |
| `cisco vpnagentd` | 35 days | Stable — ruled out as a contributing cause |

The direct correlation between Netskope proxy uptime and number of stale utun interfaces strongly implicates the Netskope session lifecycle as the source of the leak.

### 4d. Netskope Log Evidence

- `Config downloading supportability params` fires every 5 minutes (normal keepalive behavior — not abnormal)
- Active flows confirmed traversing `utun14` (the current, valid Netskope session)
- `utun4`–`utun13` have default routes in the routing table but no active flows and no IPv4 addresses — confirmed dead sessions

---

## 5. Expected Behavior

When a Netskope tunnel session ends (due to reconnect, sleep/wake, network change, or explicit disconnect), the Netskope client should:

1. Remove the default route associated with the terminating utun interface before or immediately after the new session is established.
2. Remove or release the utun interface itself, or ensure it is no longer injected into the routing table.

At no point should the routing table contain more than one Netskope-owned default route. The current behavior leaves orphaned routes indefinitely until the `NetskopeClientMacAppProxy` process is restarted.

---

## 6. Workaround Applied

As a temporary measure, a local `launchd` daemon has been installed on the affected machine to periodically detect and flush stale utun default routes from the routing table. This reduces the frequency of blackout events but does not address the root cause. The workaround is not a permanent solution and introduces its own maintenance overhead.

---

## 7. Requested Actions

The following actions are requested from IT / Netskope administration:

**a. Version verification**
Confirm whether Netskope Client 126.0.9.2460 is the latest available release qualified for macOS 14.3.1 (Sonoma). If a newer version is available, provide the upgrade path and confirm whether the utun leak behavior is addressed in the release notes.

**b. Known bug check**
Search the Netskope support knowledge base and internal bug tracker for any known issue related to utun interface leaks or stale default route accumulation on macOS. If a bug or advisory exists, share the reference number and any recommended mitigation.

**c. Tenant configuration review — AOAC settings**
Review the Netskope tenant configuration for this device/user profile, specifically:
- Always-On After Connect (AOAC) settings that may trigger tunnel teardown and re-creation more frequently than expected
- Any policy-driven reconnect intervals or gateway failover settings that could cause excessive utun churn
- Whether the device is enrolled in a steering policy that results in frequent tunnel renegotiation

**d. Escalation to Netskope support**
If no known fix or configuration resolution is identified in steps (a)–(c), escalate to Netskope TAC (Technical Assistance Center) with the evidence documented in this ticket. Request a root cause analysis and a target fix version.

---

## 8. Attachments / Supporting Data

The following items are available upon request:
- Full routing table output (`netstat -rn`) captured at time of diagnosis
- Full ping log (8-minute capture to `www.rakuten.co.jp`)
- Netskope client log excerpts showing session events and active flows
- `ifconfig` output showing interface states for `utun0`–`utun14`
- Local launchd daemon configuration (workaround)

---

*Ticket prepared: 2026-04-15*
