All Your WiFi Tools

  ┌──────────────────────────────────────┬────────────────────────────────────────────────────────┐
  │                Tool                  │                        Purpose                         │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ wifi-diagnostic.sh                   │ Full health check (signal, routing table, DNS, VPN)    │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ wifi-reconnect.sh                    │ Force WiFi reconnect (get new channel/AP)              │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ check-wifi-hardware.sh               │ Check for hardware/driver issues                       │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ netskope-test.sh                     │ A/B test: does disabling Netskope improve ping?        │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ ping-correlate.sh                    │ Log system state during ping spikes                    │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ check_netskope.py                    │ Netskope tunnel status + site reachability             │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ netskope-analyzer.py                 │ Analyze Netskope error logs                            │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ utun-cleanup.sh                      │ Manual: flush stale Netskope utun default routes       │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ install-utun-cleanup.sh              │ Install launchd daemon (auto-cleans every 2 min)       │
  ├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ IT_TICKET_netskope_utun_leak.md      │ IT ticket draft for Netskope utun leak bug             │
  └──────────────────────────────────────┴────────────────────────────────────────────────────────┘

  Root cause (confirmed 2026-04-15):
    Netskope leaks utun interfaces on session reconnect → 15 default routes accumulate
    → kernel cycles through dead routes → "No route to host" blackout every ~90s
    → staircase recovery (8000ms→0ms) as queued packets drain

  Permanent fix:
    1. sudo ./install-utun-cleanup.sh      (installs launchd auto-cleanup daemon)
    2. File IT ticket: IT_TICKET_netskope_utun_leak.md

  Monitor:
    tail -f /var/log/utun-cleanup.log
    netstat -nr | grep "^default" | wc -l   (should stay ≤ 4)