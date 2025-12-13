#!/bin/bash

# A script to fully reset macOS networking, especially after VPN disconnects.

echo "--- Step 1: Power-cycling Wi-Fi interface (en0) ---"
# This forces the Wi-Fi hardware to turn off and then on again.
networksetup -setairportpower en0 off
sleep 2 # Wait 2 seconds to ensure it's fully off
networksetup -setairportpower en0 on
echo "Wi-Fi has been reset. Waiting for it to reconnect..."

# Give the system time to find networks and re-establish a connection.
sleep 15

echo "\n--- Step 2: The Core of the Fix - Flushing DNS ---"
# This clears out old/stale DNS information left by the VPN.
sudo dscacheutil -flushcache
# This forces the core macOS DNS service to restart and reload its configuration.
sudo killall -HUP mDNSResponder
echo "DNS cache has been flushed and DNS service has been restarted."

echo "\n--- Step 3: Verifying Network Status ---"
echo "Your current DNS servers are:"
# Display the DNS servers your Mac is now using.
scutil --dns | grep 'nameserver\['

echo "\nPinging www.rakuten.co.jp to confirm internet connectivity..."
# Send 4 pings to a reliable external server to test the connection.
ping -c 10 www.rakuten.co.jp

echo "\n--- Network reset complete. ---"
