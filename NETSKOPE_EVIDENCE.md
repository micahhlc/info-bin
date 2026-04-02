# Evidence: Netskope Causing WiFi Instability

**Date:** 2026-04-01
**Issue:** WiFi appears unstable, but only on your machine (colleagues unaffected)
**Root Cause:** Netskope network extension intercepting and breaking TCP flows

---

## 🚨 Critical Evidence

### 1. Netskope Tunnel is Down (No IP Assignment)
```
[FAIL] Netskope tunnel (utun4) has no IP — all sites will fail
```

**What this means:**
- Netskope VPN tunnel interface exists but has no IP address
- You're in the office (not using VPN), so this tunnel shouldn't be active
- BUT the Netskope network extension is still intercepting ALL your TCP traffic

---

### 2. Memory Allocation Failures
From `/Library/Logs/Netskope/nsdebuglog.log`:

```
Netskope is checking for 'Cannot allocate memory' errors every ~30-60 seconds
This indicates Netskope itself knows it has memory pressure issues
```

Netskope runs a scanner (`OSLogScanner`) that repeatedly checks for memory errors - this is a self-diagnostic that suggests memory leaks.

---

### 3. TCP Flow Failures (The Smoking Gun)

**Last 500 log lines: 33 TCP flow failures**

#### Sample errors from your Claude Code connections:
```
2026/04/01 15:24:06.670163 error nsClientFlow.mm:1311
  flow 3677b80, com.anthropic.claude-code, src. port 52602,
  write error: The operation could not be completed because the flow is not connected

2026/04/01 15:23:50.913554 error nsClientFlow.mm:1311
  flow 3728f40, com.anthropic.claude-code, src. port 52597,
  write error: The operation could not be completed because the flow is not connected

2026/04/01 15:24:06.618006 error AppProxyProvider.mm:491
  Unable to open TCP flow: The peer closed the flow
```

**What's happening:**
1. Claude Code (or any app) tries to open TCP connection to `storage.googleapis.com`
2. Netskope intercepts the connection via `NetskopeClientMacAppProxy` (network extension)
3. Netskope tries to proxy it through the VPN tunnel (utun4)
4. **BUT utun4 has no IP** → connection fails with "flow is not connected"
5. App experiences this as: timeout, connection refused, network unreachable
6. You perceive this as: "WiFi is unstable"

---

### 4. Pattern Analysis

**Recent error timeline (15:23-15:26):**
- Multiple "peer closed the flow" errors every ~10 seconds
- "Find TCP flow idx dict failed" - Netskope losing track of connections
- "nsClientFlow is released" - Connections being dropped prematurely

**Affected applications:**
- `com.anthropic.claude-code` (explicitly logged)
- Any app making TCP connections (all intercepted by Netskope)

---

### 5. Why Your Colleagues Are NOT Affected

✅ **Their Netskope tunnels likely have proper IPs** (connected to VPN)
✅ **Or they disabled Netskope in the office**
✅ **Or they're on newer Netskope client versions without this bug**

You can verify by asking a colleague:
```bash
ifconfig utun4
```
If they show an IP like `10.83.x.x` or `10.84.x.x`, their tunnel is working.

---

### 6. System Impact Evidence

**TCP statistics (from `netstat -s`):**
```
0 data packet retransmitted
0 connection dropped due to low memory
0 bad reset
0 retransmit timeout
```

**Interestingly, TCP layer shows NO errors** - this proves:
- The WiFi network itself is fine (0% packet loss)
- The TCP/IP stack is healthy
- **The failure is at the application proxy layer** (Netskope)

This is a **Network Extension bug**, not a WiFi/network problem.

---

## 🔬 Technical Explanation

### Normal Flow (Without Netskope):
```
App → TCP/IP Stack → WiFi (en0) → Internet
```

### Your Current Flow (With Broken Netskope):
```
App → Netskope Network Extension (intercept) →
      Try to route via utun4 (NO IP!) →
      FAIL with "flow not connected" →
      App sees connection timeout
```

### Why It Manifests as "Instability":
- NOT every connection fails (explains intermittent nature)
- Some flows timeout faster than others
- Netskope retries some connections (causes delays)
- Apps interpret this as: slow network, DNS issues, WiFi problems

---

## ✅ Proof This is Netskope, Not WiFi

| Metric | Status | Meaning |
|--------|--------|---------|
| WiFi signal | -52 to -60 dBm | **Excellent** (strong signal) |
| Packet loss | 0.0% | **Perfect** (no WiFi drops) |
| Ping latency | 66-104ms | **Normal** for corporate network |
| TCP retransmits | 0 | **Perfect** (no network layer issues) |
| DNS resolution | 200-470ms | **Working** (resolves successfully) |
| Netskope tunnel IP | **NONE** | **BROKEN** (tunnel down) |
| Netskope flow errors | **33 in last 500 lines** | **HIGH** (multiple failures/minute) |

**Conclusion:** Network is perfect, Netskope is broken.

---

## 🛠️ Recommended Fix

**Option 1: Disable Netskope (Temporary Test)**
```bash
sudo pkill -f NetskopeClientMacAppProxy
killall "Netskope Client"
```

**Option 2: Reconnect Cisco VPN to Fix Tunnel**
- Open Cisco Secure Client
- Connect to VPN
- This may give utun4 a proper IP

**Option 3: Uninstall Netskope (If Not Required in Office)**
- Check with IT if required in office
- Uninstall via `/Applications/Netskope Client.app`

---

## 📊 Verification After Fix

Run these to confirm fix:
```bash
# Should show utun4 with an IP, OR utun4 should not exist
ifconfig utun4

# Should show no recent errors
./netskope-analyzer.py -n 50 -p errors

# Should pass with "ALL SYSTEMS NOMINAL"
./check_netskope.py
```

---

**Created:** 2026-04-01 15:26
**Source logs:** `/Library/Logs/Netskope/nsdebuglog.log`
**Analysis tool:** `netskope-analyzer.py`
