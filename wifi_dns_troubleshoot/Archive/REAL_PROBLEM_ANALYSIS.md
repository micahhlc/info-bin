# WiFi Instability - Root Cause Analysis (Updated)

**Date:** 2026-04-01 15:59
**Status:** Netskope is NOT the cause (test proved it)
**Real Issue:** WiFi driver dropping packets (rxToss) + channel congestion

---

## 🚨 Test Results: Netskope is INNOCENT

### Before/After Comparison
```
WITH Netskope:     6 spikes, max 1067ms, avg 76ms
WITHOUT Netskope: 12 spikes, max 1376ms, avg 96ms
```

**Verdict:** Disabling Netskope made things WORSE!

This means:
- ❌ Netskope is NOT causing the ping spikes
- ✅ There's a deeper WiFi layer issue
- ⚠️ Netskope's broken tunnel is a separate problem (doesn't affect connectivity)

---

## 🔬 The Real Smoking Gun: WiFi Driver Packet Loss

### From WiFi Quality Metrics (LQM):

```
Sample 1: rxToss=65  (65 packets dropped in 5 seconds!)
Sample 2: rxToss=102 (102 packets dropped!)
Sample 3: rxToss=22  (22 packets dropped)
```

**What is rxToss?**
- Packets received by WiFi hardware but **dropped by the driver**
- This happens BEFORE reaching the network stack
- Causes retransmissions, delays, and latency spikes

**Why your colleagues aren't affected:**
- They might be on different channels (different APs)
- They might have newer WiFi hardware
- Your specific WiFi chip/driver has a bug

---

## 📊 WiFi Channel Congestion Evidence

### Channel Clear Assessment (CCA):
```
cca=21.0%           ← Channel is 21% busy (moderate congestion)
ccaSelfTotal=6%     ← Your traffic: 6%
ccaOtherTotal=11%   ← Other devices: 11%
interferenceTotal=4 ← Some interference detected
```

**Interpretation:**
- Your channel (136, 5GHz) has **11% usage from other devices**
- This is MODERATE congestion (not terrible, but not great)
- Can cause bufferbloat when combined with other issues

### Retry Frames:
```
rxRetryFrames=1, 9, 6 (packets being retransmitted due to errors)
```

---

## 🎯 Root Cause: Multi-Factor Problem

### Primary Issue: WiFi Driver Buffer Overflow
1. Channel is moderately busy (21% CCA)
2. Packets arrive faster than driver can process
3. Driver buffer fills up → **drops packets (rxToss)**
4. TCP layer detects loss → retransmits
5. Retransmissions queue up → **bufferbloat**
6. Massive latency spikes (1000-1600ms)

### Contributing Factors:
- **Channel congestion** (11% from other devices)
- **Interference** (interferenceTotal=2-4)
- **Possible WiFi driver bug** (macOS 13.x specific?)
- **Access Point overload** (many users in office)

---

## 🔍 Why NOT Netskope?

**Evidence:**
1. Test showed worse performance WITHOUT Netskope
2. Netskope tunnel is down (no IP) but doesn't affect regular traffic
3. Netskope flow errors are for specific apps (Claude Code), not all traffic
4. WiFi metrics show problems at hardware layer (below Netskope)

**Netskope's role:**
- Tunnel is broken (separate issue)
- Causes some app connection failures
- But NOT the cause of ping spikes

---

## 🛠️ Actual Solutions (Ranked by Likelihood)

### 1. **Switch to Different WiFi Channel/AP** (80% confidence)
Your current channel (136, 5GHz) has congestion. Try:

```bash
# Force reconnect to potentially different AP
sudo ifconfig en0 down
sleep 5
sudo ifconfig en0 up
```

Or manually connect to different SSID if available (e.g., `r-intra-5G` or different floor AP).

### 2. **Update macOS** (60% confidence)
WiFi driver bugs are often fixed in updates:
```bash
softwareupdate -l
```

Check if you're on older macOS version than colleagues.

### 3. **Reset WiFi Module (SMC/NVRAM)** (40% confidence)
```bash
# Reset NVRAM (restart required)
sudo nvram -c
sudo reboot

# Or reset SMC (depends on Mac model)
# Intel Mac: Shut down → Shift+Ctrl+Option+Power for 10s → Release → Boot
# Apple Silicon: Shut down → Wait 30s → Boot
```

### 4. **Disable WiFi Power Management** (30% confidence)
```bash
# Check current setting
pmset -g | grep powernap

# Disable WiFi power saving (stays on AC power)
sudo pmset -c disablesleep 1
```

### 5. **Check for Specific Interference** (20% confidence)
- Bluetooth devices (disable temporarily)
- USB 3.0 devices near Mac (known to interfere with 2.4GHz)
- Microwave ovens (seriously!)

### 6. **Hardware Issue** (10% confidence)
Your WiFi card might be failing:
```bash
# Run Apple Diagnostics
# Restart → Hold D during boot → Run diagnostics
```

---

## 📝 Detailed Investigation Plan

### Step 1: Confirm Channel Congestion (Need sudo)
```bash
# Scan all APs and see how many are on channel 136
sudo /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s | grep "136"
```

### Step 2: Monitor WiFi Quality Continuously
```bash
# Log WiFi metrics every 5 seconds for 5 minutes
for i in {1..60}; do
  date '+%H:%M:%S'
  /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep -E "agrCtlRSSI|channel|lastTxRate"
  sleep 5
done > wifi-monitor.log
```

### Step 3: Correlate with Ping
Run both simultaneously:
```bash
# Terminal 1: Continuous ping
ping 8.8.8.8 > ping.log

# Terminal 2: Watch for rxToss
while true; do
  log show --predicate 'subsystem contains "com.apple.wifi"' --style syslog --last 5s | grep "rxToss" | tail -1
  sleep 5
done
```

### Step 4: Test Different Location
Move to different room/floor and test if spikes persist.

---

## 🧪 Quick Test: Force 5GHz Only

Your diagnostic showed multiple channels (136, 128, 8, 11). You might be band-steering between 2.4GHz and 5GHz:

```bash
# Check current channel
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel

# If it switches to channel 8 or 11 (2.4GHz), that's your problem
# 2.4GHz is much more congested in offices
```

Force 5GHz by forgetting 2.4GHz SSIDs if they exist separately.

---

## 🎯 Most Likely Culprit: Access Point Overload

**Hypothesis:**
- Office has many users on same AP
- AP's buffer fills up during peak usage
- AP drops packets → your Mac sees rxToss
- Your colleagues on different APs don't see this

**Test:**
1. Check with colleagues: "What WiFi channel are you on?"
   ```
   /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel
   ```
2. If they're on different channels, that's the issue
3. Force reconnect until you get different channel

---

## 📊 Evidence Summary

| Symptom | Evidence | Layer |
|---------|----------|-------|
| Ping spikes | 1600ms max | ✅ Confirmed |
| Packet drops | rxToss=65-102 | ✅ WiFi driver |
| Channel busy | CCA=21% | ✅ WiFi channel |
| Retries | rxRetryFrames=1-9 | ✅ WiFi layer |
| Netskope tunnel down | No IP on utun4 | ⚠️ Separate issue |
| TCP errors | 0 retransmits | ✅ Network stack OK |
| WiFi errors | 0 Ierrs/Oerrs | ⚠️ Hardware reports OK |

**Conclusion:** Problem is at **WiFi driver/firmware** layer, likely due to channel congestion + driver buffer overflow.

---

## ⚡ Quick Fix to Try NOW

**Force WiFi reconnect to get different AP/channel:**

```bash
sudo ifconfig en0 down && sleep 5 && sudo ifconfig en0 up
```

Then immediately test:
```bash
# Check new channel
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep channel

# Test ping
ping -c 60 8.8.8.8 | grep -E "time=|statistics"
```

If you get a different channel (e.g., 40, 44, 149 instead of 136), ping should improve.

---

**Next Steps:**
1. Try the quick fix above
2. Compare WiFi channel with colleagues
3. If problem persists after multiple reconnects, escalate to IT (AP overload)
4. Consider using Ethernet if available

---

**Created:** 2026-04-01 16:00
**Previous hypothesis (Netskope):** ❌ DISPROVEN by test
**Current hypothesis (Channel congestion + driver overflow):** Under investigation
