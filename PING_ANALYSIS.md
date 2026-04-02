# Ping Spike Analysis - Updated Evidence

**Date:** 2026-04-01
**Critical Discovery:** Ping shows 1600ms+ latency spikes (not just Netskope errors)

---

## 🚨 The Real Problem: Dual Issues

### Issue 1: Network Layer Problem (NEW - More Critical)
Your ping data shows **severe bufferbloat/queue saturation:**

```
Normal:    9-18ms   (90% of the time - WiFi is fine)
Spikes:   400-1600ms (catastrophic delays)
Pattern:  Sudden spike → gradual recovery
```

#### Classic Bufferbloat Pattern (seq 12340-12344):
```
12340: 1647ms  ← Buffer overflow starts
12341: 1383ms  ← Draining...
12342: 1012ms  ← Still draining...
12343:  609ms  ← Almost empty...
12344:   74ms  ← Normal
12345:    9ms  ← Recovered
```

This is **NOT a Netskope-only problem**. This is:
- WiFi driver buffer overflow, OR
- Access point queue saturation, OR
- macOS network stack issue, OR
- **Netskope + WiFi driver interaction bug**

---

### Issue 2: Netskope Broken Tunnel (Original Finding)
- Netskope tunnel (utun4) has no IP
- 33 TCP flow failures in last 500 logs
- Apps experience "connection refused" errors

---

## 🔬 Root Cause Analysis

### Why BOTH Issues Happen Together

**Hypothesis:** Netskope's broken tunnel causes network stack congestion

```
1. App tries to connect → Netskope intercepts
2. Netskope queues packet to route via utun4
3. utun4 has no IP → packet stuck in queue
4. Queue fills up (bufferbloat)
5. ALL network traffic (including ICMP ping) gets queued behind failed packets
6. Massive latency spike (1600ms)
7. Eventually queue times out/flushes
8. Traffic recovers (gradual drain: 1647→1383→1012→609→74→9ms)
```

**This explains why your colleagues are NOT affected:**
- Their Netskope tunnels work (have IP)
- OR they don't have Netskope
- Their packets don't get stuck in broken tunnel queue

---

## 📊 Evidence Summary

### Ping Statistics
| Metric | Your Machine | Expected |
|--------|--------------|----------|
| Normal latency | 9-18ms | ✅ Normal |
| Spike frequency | Every 20-30 pings | ❌ Too frequent |
| Spike magnitude | 400-1600ms | ❌ CRITICAL |
| Recovery pattern | Gradual (1647→9ms over 5 pings) | ⚠️ Bufferbloat signature |
| Packet duplication | seq 12340 (DUP!) | ❌ Queue overflow artifact |

### Netskope Logs (Correlated)
| Time | Event |
|------|-------|
| 15:23:50 | TCP flow error: "not connected" |
| 15:24:06 | TCP flow error: "peer closed" |
| 15:25:27 | TCP flow error: "Find TCP flow idx dict failed" |

**Pattern:** Netskope errors occur at same frequency as ping spikes

---

## 🧪 Diagnostic Tests

### Test 1: Disable Netskope (RECOMMENDED FIRST)
```bash
# Kill Netskope
sudo pkill -f NetskopeClientMacAppProxy
killall "Netskope Client"

# Monitor ping for 2 minutes
ping -i 1 8.8.8.8 | head -120

# If spikes DISAPPEAR → Netskope is the cause
# If spikes PERSIST → Deeper WiFi/driver issue
```

### Test 2: Correlate Ping Spikes with System Events
```bash
# Run correlation monitor (logs system state during spikes)
./ping-correlate.sh 23.193.119.212 200

# Let it run for 5 minutes to capture multiple spikes
# Review the log to see what's happening during spikes
```

### Test 3: Check WiFi Channel Congestion
```bash
# Scan for channel interference
sudo /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s | grep "r-intra"

# If your channel (136, 5GHz) has many APs → interference
# If channel 4/11 (2.4GHz) is active → band steering issue
```

### Test 4: Check for Bufferbloat
```bash
# Download bufferbloat test
curl -O https://www.waveform.com/tools/bufferbloat

# Or use online test: fast.com (watch for latency during test)
```

---

## 🎯 Most Likely Root Causes (Ranked)

### 1. **Netskope Broken Tunnel Causing Queue Saturation** (80% confidence)
- Evidence: Tunnel has no IP + flow errors + bufferbloat pattern
- Fix: Disable Netskope OR reconnect Cisco VPN to fix tunnel
- Test: Disable Netskope → spikes should disappear

### 2. **macOS WiFi Driver Bug** (10% confidence)
- Evidence: Bufferbloat pattern + gradual recovery
- Fix: Update macOS, reset NVRAM, reinstall WiFi driver
- Test: Boot to Safe Mode → test ping

### 3. **Access Point Overload/Congestion** (5% confidence)
- Evidence: Office WiFi with many users
- Fix: Move to different AP or use 5GHz only
- Test: Move to different location → test ping

### 4. **Hardware Failure (WiFi Card)** (5% confidence)
- Evidence: Only your machine affected
- Fix: Apple diagnostics, replace WiFi card
- Test: Boot from external macOS → test ping

---

## ✅ Recommended Action Plan

**STEP 1: Prove Netskope is the cause (5 minutes)**
```bash
# Before: Run ping for 60 seconds, count spikes
ping -c 60 8.8.8.8 > /tmp/before.txt

# Disable Netskope
sudo pkill -f NetskopeClientMacAppProxy
sleep 5

# After: Run ping for 60 seconds, count spikes
ping -c 60 8.8.8.8 > /tmp/after.txt

# Compare
echo "Before:"; grep "time=" /tmp/before.txt | awk -F'time=' '{print $2}' | awk '{if($1>100) print $1}' | wc -l
echo "After:"; grep "time=" /tmp/after.txt | awk -F'time=' '{print $2}' | awk '{if($1>100) print $1}' | wc -l
```

**STEP 2: If Netskope is confirmed (permanent fix)**
- Option A: Keep Netskope disabled in office
- Option B: Reconnect Cisco VPN to fix tunnel (may cause other issues)
- Option C: Contact IT to fix Netskope configuration

**STEP 3: If NOT Netskope (deeper investigation)**
- Run: `./ping-correlate.sh 23.193.119.212 200` for 10 minutes
- Review correlation log for patterns
- Check WiFi channel interference
- Run Apple Hardware Test

---

## 📝 Evidence to Show IT Team

1. **Ping log showing 1600ms spikes** (you already have this)
2. **Netskope tunnel status:** `ifconfig utun4` (shows no IP)
3. **Netskope error logs:** `/Library/Logs/Netskope/nsdebuglog.log`
4. **Before/after Netskope disable test** (Step 1 above)
5. **This analysis document:** `PING_ANALYSIS.md`

---

**Next Step:** Run the 5-minute test in STEP 1 to prove causation.
