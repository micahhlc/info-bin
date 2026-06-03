CyberArk EPM Evidence Package
==============================
IT Ticket:   Request #778550675
Filed:       2026-06-01
Machine:     MacBook Pro, macOS 14.3.1 (Sonoma)
EPM Version: 23.2.0 (installed via JAMF: CyberArk_23_2_0_86.pkg)
Process:     com.cyberark.CyberArkEPMEndpointSecurityExtension (PID 569)

ISSUE SUMMARY
-------------
CyberArk EPM kernel extension runs at sustained 100-104% CPU on a precise
44-second interval, causing network latency spikes of 100-1250ms every ~44s.

Root cause: EPM policy enforcement interval is set to 44 seconds (default is
typically 300s). Every 44s it runs a kernel-level scan that pegs a CPU core,
stalling all network I/O during the scan window.

Evidence: 20 consecutive spikes captured over ~16 minutes. CyberArk at 100%+
CPU in every single capture — zero exceptions.

Confirmed interval (seconds between spikes):
  44, 44, 44, 44, 44, 43, 44, 44, 44, 44, 45, 45, 44, 44, 44 (rock-solid 44s)

RTT range during spikes: 108ms – 1251ms (two spikes exceeded 1 full second)
RTT baseline (between spikes): 3–5ms

macOS also auto-generated a CPU resource diagnostic on 2026-05-29 (file 04),
confirming this is a pre-existing, ongoing issue — not a one-off event.

REQUESTED ACTION
----------------
1. Reduce EPM policy enforcement interval from 44s to ≥300s in admin console
2. Confirm whether version 23.2.0 has a known CPU spike bug (check with CyberArk)
3. Review why scan interval is set so aggressively on this endpoint

STATUS
------
[ ] 2026-06-01 — Ticket filed: Request #778550675
[ ] Awaiting IT response
[ ] Resolution confirmed

FILES
-----
01-ping-spike-capture.log       Ping + nettop captures at each spike (20 spikes, ~16 min)
                                 CyberArk at 100%+ CPU in ALL 20 captures.

02-process-and-version.txt      Process list, version (23.2.0), LaunchDaemon plists,
                                 system extension path, JAMF receipt.

03-syslog-cyberark.txt          macOS unified system log filtered for CyberArk/EPM.
                                 Run: sudo log show --predicate 'process contains "cyberark"
                                 OR process contains "CyberArk" OR process contains "EPM"'
                                 --last 2h > 03-syslog-cyberark.txt

04-cyberark-cpu-resource.diag   macOS-GENERATED CPU resource diagnostic (2026-05-29).
                                 OS flagged this process for excessive CPU automatically.

05-cyberark-prefs.txt           EPM preference files from /Library/Preferences/.

06-cyberark-spindump.txt        CPU stack trace during a spike (5s sample).
                                 Run: sudo spindump 569 5 > 06-cyberark-spindump.txt

07-network-and-cpu-state.txt    Network routing, DNS, WiFi signal, CPU snapshot at
                                 time of evidence collection.

TO GENERATE FULL SYSDIAGNOSE (share via IT ticket, not email):
  sudo sysdiagnose -f ~/Desktop
