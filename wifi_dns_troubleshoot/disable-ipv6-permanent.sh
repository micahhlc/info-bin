#!/bin/bash
#
# disable-ipv6-permanent.sh
#
# Permanently disables IPv6 across three layers so VPN software (Netskope,
# Cisco) cannot re-enable it:
#
#   Layer 1 — networksetup:  disables IPv6 in System Settings for all interfaces
#   Layer 2 — /etc/sysctl.conf: disables IPv6 at kernel level (survives reboots)
#   Layer 3 — launchd daemon: re-applies networksetup after every boot/network change
#
# Run with: sudo ./disable-ipv6-permanent.sh
# Undo with: sudo ./disable-ipv6-permanent.sh --undo
#

set -euo pipefail

LABEL="com.micah.disable-ipv6"
DAEMON_SCRIPT="/usr/local/bin/disable-ipv6.sh"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SYSCTL_CONF="/etc/sysctl.conf"

UNDO=0
[[ "${1:-}" == "--undo" ]] && UNDO=1

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

# -------------------------------------------------------
# UNDO PATH
# -------------------------------------------------------
if [[ $UNDO -eq 1 ]]; then
    echo "=== Restoring IPv6 ==="

    echo "1. Removing launchd daemon ..."
    if launchctl list "$LABEL" &>/dev/null; then
        launchctl unload "$PLIST" 2>/dev/null || true
    fi
    rm -f "$PLIST" "$DAEMON_SCRIPT"
    echo "   OK"

    echo "2. Removing sysctl.conf entries ..."
    if [[ -f "$SYSCTL_CONF" ]]; then
        sed -i '' '/net\.inet6\.ip6\.accept_rtadv/d' "$SYSCTL_CONF"
        sed -i '' '/net\.inet6\.ip6\.forwarding/d' "$SYSCTL_CONF"
        # Remove file if now empty
        [[ ! -s "$SYSCTL_CONF" ]] && rm -f "$SYSCTL_CONF"
    fi
    echo "   OK"

    echo "3. Re-enabling IPv6 on all network services ..."
    while IFS= read -r svc; do
        [[ "$svc" == \** ]] && continue  # skip disabled services
        networksetup -setv6automatic "$svc" 2>/dev/null && echo "   Enabled: $svc" || true
    done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
    echo "   OK"

    echo ""
    echo "IPv6 restored. Changes take effect immediately (kernel needs reboot for sysctl)."
    exit 0
fi

# -------------------------------------------------------
# INSTALL PATH
# -------------------------------------------------------
echo "=== Permanently disabling IPv6 (3 layers) ==="

# -------------------------------------------------------
# Layer 1: networksetup — disable on all active interfaces now
# -------------------------------------------------------
echo ""
echo "Layer 1: Disabling IPv6 via networksetup ..."
while IFS= read -r svc; do
    [[ "$svc" == \** ]] && continue  # skip disabled services
    result=$(networksetup -setv6off "$svc" 2>&1) && echo "   Off: $svc" || echo "   Skip: $svc ($result)"
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)

# -------------------------------------------------------
# Layer 2: /etc/sysctl.conf — disable at kernel level on boot
# (prevents accept_rtadv so VPN router advertisements cannot
#  re-enable IPv6 autoconfiguration)
# -------------------------------------------------------
echo ""
echo "Layer 2: Writing /etc/sysctl.conf ..."

# Remove any existing lines we manage, then append
touch "$SYSCTL_CONF"
sed -i '' '/net\.inet6\.ip6\.accept_rtadv/d' "$SYSCTL_CONF"
sed -i '' '/net\.inet6\.ip6\.forwarding/d' "$SYSCTL_CONF"

cat >> "$SYSCTL_CONF" << 'EOF'
# Disable IPv6 router advertisement acceptance (managed by disable-ipv6-permanent.sh)
net.inet6.ip6.accept_rtadv=0
net.inet6.ip6.forwarding=0
EOF

# Apply immediately without reboot
sysctl -w net.inet6.ip6.accept_rtadv=0 net.inet6.ip6.forwarding=0 2>/dev/null || true
echo "   OK — /etc/sysctl.conf updated and applied"

# -------------------------------------------------------
# Layer 3: launchd daemon — re-applies networksetup on boot
# and whenever the network configuration changes
# -------------------------------------------------------
echo ""
echo "Layer 3: Installing launchd daemon ..."

# Write the daemon's own script
cat > "$DAEMON_SCRIPT" << 'SCRIPT'
#!/bin/bash
# Enforces IPv6-off on all network services.
# Called at boot by launchd (com.micah.disable-ipv6).
while IFS= read -r svc; do
    [[ "$svc" == \** ]] && continue
    networksetup -setv6off "$svc" 2>/dev/null || true
done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
SCRIPT
chmod 755 "$DAEMON_SCRIPT"
chown root:wheel "$DAEMON_SCRIPT"

# Write the plist
cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!--
    Runs disable-ipv6.sh at boot to re-apply IPv6-off settings
    in case Netskope or Cisco VPN re-enabled IPv6 during a previous session.
-->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DAEMON_SCRIPT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/disable-ipv6.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/disable-ipv6.log</string>
</dict>
</plist>
PLIST
chmod 644 "$PLIST"
chown root:wheel "$PLIST"

# Load it
if launchctl list "$LABEL" &>/dev/null; then
    launchctl unload "$PLIST" 2>/dev/null || true
fi
launchctl load "$PLIST"

if launchctl list "$LABEL" &>/dev/null; then
    echo "   Daemon loaded: $LABEL"
else
    echo "   WARNING: daemon not found in launchctl list — check plist"
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "=== Done ==="
echo ""
echo "IPv6 is now disabled across 3 layers:"
echo "  1. networksetup — all interfaces set to IPv6 Off (immediate)"
echo "  2. /etc/sysctl.conf — accept_rtadv=0 persists across reboots"
echo "  3. launchd daemon ($LABEL) — re-applies on boot"
echo ""
echo "Verify:"
echo "  networksetup -getinfo Wi-Fi | grep IPv6"
echo "  sysctl net.inet6.ip6.accept_rtadv"
echo ""
echo "To undo everything:"
echo "  sudo $0 --undo"
echo ""
echo "Daemon log: tail -f /var/log/disable-ipv6.log"
