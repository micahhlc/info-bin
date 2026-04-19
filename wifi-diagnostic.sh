#!/bin/bash

# Comprehensive WiFi Diagnostic Script for macOS
# Checks DNS, WiFi interface, VPN tunnels, and system logs

GREEN="\033[92m"
RED="\033[91m"
YELLOW="\033[93m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "\n${BOLD}=== 📡 WiFi Stability Diagnostic ===${RESET}\n"

# 1. WiFi Interface Status
echo -e "${BOLD}--- 1️⃣  WiFi Interface (en0) ---${RESET}"
WIFI_STATUS=$(networksetup -getairportpower en0 | awk '{print $4}')
if [ "$WIFI_STATUS" = "On" ]; then
    echo -e "[${GREEN} OK ${RESET}] WiFi is ON"
else
    echo -e "[${RED}FAIL${RESET}] WiFi is OFF"
fi

# Get current network info
SSID=$(networksetup -getairportnetwork en0 | awk -F': ' '{print $2}')
echo "Connected SSID: $SSID"

# WiFi signal strength and noise
WIFI_INFO=$(system_profiler SPAirPortDataType 2>/dev/null | grep -A 20 "Current Network Information" | head -25)
SIGNAL=$(echo "$WIFI_INFO" | grep "Signal / Noise" | awk -F': ' '{print $2}')
CHANNEL=$(echo "$WIFI_INFO" | grep "Channel:" | awk -F': ' '{print $2}')
RSSI=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "agrCtlRSSI:" | awk '{print $2}')
ACTUAL_CHANNEL=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "channel:" | awk '{print $2}')

echo "Signal/Noise: $SIGNAL"
echo "Channel: $CHANNEL"

# Interpret signal strength
echo ""
if [ -n "$RSSI" ]; then
    if [ "$RSSI" -ge -50 ]; then
        echo -e "[${GREEN}EXCELLENT${RESET}] Signal: ${RSSI} dBm (very strong)"
    elif [ "$RSSI" -ge -60 ]; then
        echo -e "[${GREEN} GOOD ${RESET}] Signal: ${RSSI} dBm (strong)"
    elif [ "$RSSI" -ge -67 ]; then
        echo -e "[${YELLOW} FAIR ${RESET}] Signal: ${RSSI} dBm (adequate, may have occasional issues)"
    elif [ "$RSSI" -ge -70 ]; then
        echo -e "[${YELLOW} WEAK ${RESET}] Signal: ${RSSI} dBm (marginal, consider moving closer to AP)"
    else
        echo -e "[${RED} POOR ${RESET}] Signal: ${RSSI} dBm (very weak, likely unstable)"
    fi
fi

# Note about channel
if [ -n "$ACTUAL_CHANNEL" ]; then
    if [ "$ACTUAL_CHANNEL" -ge 36 ]; then
        echo -e "[${GREEN} OK ${RESET}] Using 5GHz channel ${ACTUAL_CHANNEL} (typically less congested)"
    else
        echo -e "[${YELLOW}WARN${RESET}] Using 2.4GHz channel ${ACTUAL_CHANNEL} (more congested, consider 5GHz)"
    fi
fi

# Check for interface errors
ERRORS=$(netstat -I en0 | tail -1 | awk '{print "Input errors: " $6 ", Output errors: " $9}')
echo "$ERRORS"

# 2. DNS Configuration
echo -e "\n${BOLD}--- 2️⃣  DNS Configuration ---${RESET}"
echo "Current DNS servers:"
scutil --dns | grep 'nameserver\[' | head -5

# Check for DNS responsiveness
echo -e "\nDNS resolution test:"
for domain in google.com rakuten.co.jp r-ai.tsd.public.rakuten-it.com; do
    START=$(python3 -c 'import time; print(int(time.time()*1000))')
    if host $domain &>/dev/null; then
        END=$(python3 -c 'import time; print(int(time.time()*1000))')
        DURATION=$((END - START))
        echo -e "[${GREEN} OK ${RESET}] $domain - ${DURATION}ms"
    else
        echo -e "[${RED}FAIL${RESET}] $domain - DNS resolution failed"
    fi
done

# 3. VPN/Tunnel Interfaces
echo -e "\n${BOLD}--- 3️⃣  VPN/Tunnel Interfaces ---${RESET}"
for iface in utun0 utun1 utun2 utun3 utun4 utun5; do
    if ifconfig $iface &>/dev/null; then
        IP=$(ifconfig $iface 2>/dev/null | grep "inet " | awk '{print $2}')
        MTU=$(ifconfig $iface 2>/dev/null | grep "mtu" | awk '{print $4}')
        if [ -n "$IP" ]; then
            echo -e "[${GREEN} UP ${RESET}] $iface - IP: $IP  MTU: $MTU"
        else
            echo -e "[${YELLOW}WARN${RESET}] $iface exists but has no IP"
        fi
    fi
done

# 4. Routing Table
echo -e "\n${BOLD}--- 4️⃣  Routing Table (Default Gateway) ---${RESET}"
netstat -nr | grep default | head -5

# 5. Connection Quality Test
echo -e "\n${BOLD}--- 5️⃣  Connection Quality Test ---${RESET}"
echo "Testing ping stability (10 packets to 8.8.8.8)..."
PING_RESULT=$(ping -c 10 8.8.8.8 2>&1)
LOSS=$(echo "$PING_RESULT" | grep "packet loss" | awk '{print $7}')
AVG_RTT=$(echo "$PING_RESULT" | grep "min/avg/max" | awk -F'/' '{print $5}')
echo "Packet loss: $LOSS"
echo "Average RTT: ${AVG_RTT}ms"

if [[ "$LOSS" == "0.0%" ]]; then
    echo -e "[${GREEN} OK ${RESET}] No packet loss"
elif [[ "$LOSS" =~ ^[0-9.]+% ]]; then
    LOSS_NUM=$(echo "$LOSS" | sed 's/%//')
    if (( $(echo "$LOSS_NUM > 5" | bc -l) )); then
        echo -e "[${RED}FAIL${RESET}] High packet loss detected: $LOSS"
    else
        echo -e "[${YELLOW}WARN${RESET}] Some packet loss: $LOSS"
    fi
fi

# Interpret latency
if [ -n "$AVG_RTT" ]; then
    AVG_INT=$(printf "%.0f" "$AVG_RTT" 2>/dev/null || echo "0")
    if [ "$AVG_INT" -lt 30 ]; then
        echo -e "[${GREEN}EXCELLENT${RESET}] Latency is very low (${AVG_RTT}ms)"
    elif [ "$AVG_INT" -lt 50 ]; then
        echo -e "[${GREEN} GOOD ${RESET}] Latency is good (${AVG_RTT}ms)"
    elif [ "$AVG_INT" -lt 100 ]; then
        echo -e "[${YELLOW} FAIR ${RESET}] Latency is acceptable (${AVG_RTT}ms)"
    else
        echo -e "[${RED} POOR ${RESET}] Latency is high (${AVG_RTT}ms) - may indicate congestion"
    fi
fi

# 6. WiFi Errors in System Log (last 5 minutes)
echo -e "\n${BOLD}--- 6️⃣  Recent WiFi Errors (last 5 min) ---${RESET}"
WIFI_ERRORS=$(log show --predicate 'processImagePath contains "airportd" OR subsystem contains "com.apple.wifi"' \
    --style syslog --last 5m 2>/dev/null | grep -iE "error|fail|disconnect|timeout|unable" | tail -10)

if [ -n "$WIFI_ERRORS" ]; then
    echo "$WIFI_ERRORS" | while read -r line; do
        echo -e "[${YELLOW}WARN${RESET}] $line"
    done
else
    echo -e "[${GREEN} OK ${RESET}] No WiFi errors in recent logs"
fi

# 7. Network Extension Interference
echo -e "\n${BOLD}--- 7️⃣  Active Network Extensions ---${RESET}"
systemextensionsctl list 2>/dev/null | grep -iE "netskope|cisco|vpn|network" | head -10

# 8. mDNSResponder Status
echo -e "\n${BOLD}--- 8️⃣  mDNSResponder (DNS Service) Status ---${RESET}"
if pgrep -x mDNSResponder > /dev/null; then
    echo -e "[${GREEN} OK ${RESET}] mDNSResponder is running"
else
    echo -e "[${RED}FAIL${RESET}] mDNSResponder is NOT running"
fi

# Check mDNSResponder stability by uptime (not log parsing which gives false positives)
# The previous method incorrectly counted log entries containing "start"

# 9. Routing Table Audit (VPN route churn detection)
echo -e "\n${BOLD}--- 9️⃣  Routing Table Audit ---${RESET}"

DEFAULT_ROUTES=$(netstat -nr 2>/dev/null | grep "^default")
DEFAULT_COUNT=$(echo "$DEFAULT_ROUTES" | grep -c "^default" || echo 0)

echo "Default routes active: $DEFAULT_COUNT"

# Healthy = 1 (en0) + up to 2 IPv6 link-locals for utun. >4 is a red flag.
if [ "$DEFAULT_COUNT" -gt 4 ]; then
    echo -e "[${RED}WARN${RESET}] $DEFAULT_COUNT default routes detected — VPN tunnel accumulation"
    echo "  This causes periodic 'No route to host' blackouts every ~90 seconds"
    echo "  as Netskope/Cisco rotate utun interfaces and briefly drop the route."
    echo ""
    echo "  Active default routes:"
    echo "$DEFAULT_ROUTES" | while read -r line; do
        iface=$(echo "$line" | awk '{print $NF}')
        if echo "$line" | grep -q "en0"; then
            echo -e "  [${GREEN} OK ${RESET}] $line  (WiFi — primary)"
        else
            echo -e "  [${YELLOW}WARN${RESET}] $line  (tunnel)"
        fi
    done
    ROUTING_ISSUE=1
else
    echo -e "[${GREEN} OK ${RESET}] Routing table looks clean ($DEFAULT_COUNT default routes)"
    echo "$DEFAULT_ROUTES" | sed 's/^/  /'
    ROUTING_ISSUE=0
fi

# Count utun interfaces (each Netskope/Cisco session creates one; stale ones accumulate)
UTUN_COUNT=$(ifconfig 2>/dev/null | grep -c "^utun")
echo ""
echo "Active utun (tunnel) interfaces: $UTUN_COUNT"
if [ "$UTUN_COUNT" -gt 5 ]; then
    echo -e "[${YELLOW}WARN${RESET}] $UTUN_COUNT utun interfaces — stale tunnels accumulating"
    echo "  Normal: 2-3 (macOS creates utun0/utun1/utun2 for system use)"
    echo "  Fix: Restart Netskope and Cisco to clean up stale interfaces"
fi

# 10. DNS Diagnostic
echo -e "\n${BOLD}--- 🔟  DNS Diagnostic ---${RESET}"

DNS_SERVERS=$(scutil --dns 2>/dev/null | grep "nameserver\[" | awk '{print $3}' | sort -u)
echo "Active DNS servers:"
DNS_ISSUES=0

for ns in $DNS_SERVERS; do
    # Test both A and AAAA response times (3 samples each)
    a_times=()
    aaaa_times=()
    for i in 1 2 3; do
        t=$(dig @"$ns" google.com A +timeout=3 +tries=1 2>&1 | grep "Query time" | awk '{print $4}')
        [ -n "$t" ] && a_times+=("$t")
        t=$(dig @"$ns" google.com AAAA +timeout=3 +tries=1 2>&1 | grep "Query time" | awk '{print $4}')
        [ -n "$t" ] && aaaa_times+=("$t")
    done

    # Calculate averages
    if [ ${#a_times[@]} -gt 0 ]; then
        a_avg=$(echo "${a_times[@]}" | tr ' ' '\n' | awk '{s+=$1}END{printf "%d", s/NR}')
        a_max=$(echo "${a_times[@]}" | tr ' ' '\n' | sort -n | tail -1)
    else
        a_avg="timeout"; a_max="timeout"
    fi
    if [ ${#aaaa_times[@]} -gt 0 ]; then
        aaaa_avg=$(echo "${aaaa_times[@]}" | tr ' ' '\n' | awk '{s+=$1}END{printf "%d", s/NR}')
        aaaa_max=$(echo "${aaaa_times[@]}" | tr ' ' '\n' | sort -n | tail -1)
    else
        aaaa_avg="timeout"; aaaa_max="timeout"
    fi

    # Flag if AAAA is slow (>200ms avg) or much slower than A
    aaaa_flag=""
    if [ "$aaaa_avg" = "timeout" ]; then
        aaaa_flag=" [${RED}AAAA DEAD${RESET}]"
        DNS_ISSUES=$((DNS_ISSUES + 1))
    elif [ "$aaaa_avg" -gt 200 ] 2>/dev/null; then
        aaaa_flag=" [${YELLOW}AAAA SLOW${RESET}]"
        DNS_ISSUES=$((DNS_ISSUES + 1))
    fi

    if [ "$a_avg" = "timeout" ]; then
        echo -e "  [${RED}DEAD${RESET}] $ns  A=timeout  AAAA=timeout"
        DNS_ISSUES=$((DNS_ISSUES + 1))
    elif [ "$a_avg" -gt 150 ] 2>/dev/null; then
        echo -e "  [${YELLOW}SLOW${RESET}] $ns  A=avg ${a_avg}ms max ${a_max}ms  |  AAAA=avg ${aaaa_avg}ms max ${aaaa_max}ms${aaaa_flag}"
        DNS_ISSUES=$((DNS_ISSUES + 1))
    else
        echo -e "  [${GREEN} OK ${RESET}] $ns  A=avg ${a_avg}ms max ${a_max}ms  |  AAAA=avg ${aaaa_avg}ms max ${aaaa_max}ms${aaaa_flag}"
    fi
done

if [ "$DNS_ISSUES" -gt 0 ]; then
    echo ""
    echo -e "  [${YELLOW}WARN${RESET}] Slow/dead DNS servers add latency to every new connection."
    echo "  macOS queries all servers in parallel; a slow AAAA response can force"
    echo "  connections onto a slow IPv6 path even when IPv4 is fast."
    echo "  Quick test: networksetup -setdnsservers Wi-Fi 10.0.63.3 10.0.2.1 10.0.1.20"
    echo "  (omits the slow server; revert with: networksetup -setdnsservers Wi-Fi \"Empty\")"
else
    echo -e "  [${GREEN} OK ${RESET}] All DNS servers responding within acceptable latency"
fi

# Check Cisco Umbrella dnscryptproxy (intercepts DNS even when VPN is disconnected)
if pgrep -f "dnscryptproxy" > /dev/null; then
    echo ""
    UMBRELLA_NS=$(ps aux | grep dnscryptproxy | grep -o "resolverAddress=[^ ]*" | cut -d= -f2)
    echo -e "  [${YELLOW}NOTE${RESET}] Cisco Umbrella dnscryptproxy is running (upstream: ${UMBRELLA_NS:-unknown})"
    echo "  This proxy is active even when Cisco VPN is disconnected."
    # Check if its upstream resolv.conf has stale IPv6 entries
    UMBRELLA_RESOLV="/opt/cisco/secureclient/umbrella/resolv.conf"
    if [ -f "$UMBRELLA_RESOLV" ]; then
        STALE_V6=$(grep "fe80::" "$UMBRELLA_RESOLV" 2>/dev/null)
        if [ -n "$STALE_V6" ]; then
            echo -e "  [${RED}WARN${RESET}] Stale link-local IPv6 nameserver in Umbrella config: $STALE_V6"
            echo "  This server is unreachable and will time out on every lookup."
        fi
    fi
fi

# 12. Diagnosis & Recommendations
echo -e "\n${BOLD}=== 🩺 DIAGNOSIS & RECOMMENDATIONS ===${RESET}\n"

# Overall assessment
ISSUES_FOUND=0

# Routing table issue (highest priority — this causes hard blackouts)
if [ "${ROUTING_ISSUE:-0}" -eq 1 ]; then
    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║  ❌  ROUTING TABLE CHURN DETECTED                          ║${RESET}"
    echo -e "${RED}${BOLD}╠════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${RED}║  $DEFAULT_COUNT default routes are competing.                     ║${RESET}"
    echo -e "${RED}║  Netskope/Cisco periodically swaps utun routes, causing        ║${RESET}"
    echo -e "${RED}║  ~5-10s 'No route to host' blackouts every 60-90 seconds.      ║${RESET}"
    echo -e "${RED}║                                                                ║${RESET}"
    echo -e "${RED}║  Fix: Restart Netskope to flush stale utun interfaces:         ║${RESET}"
    echo -e "${RED}║    sudo pkill -f NetskopeClientMacAppProxy                    ║${RESET}"
    echo -e "${RED}║  Then reopen the Netskope Client app.                          ║${RESET}"
    echo -e "${RED}║                                                                ║${RESET}"
    echo -e "${RED}║  If it recurs, report to IT: Netskope is leaking utun routes.  ║${RESET}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    ISSUES_FOUND=1
fi

if [ -n "$RSSI" ] && [ "$RSSI" -lt -67 ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║  ⚠️  Weak Signal Detected (${RSSI} dBm)                      ║${RESET}"
    echo -e "${YELLOW}${BOLD}╠════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${YELLOW}║  → Try: Moving closer to AP                                ║${RESET}"
    echo -e "${YELLOW}║  → Or run: ./wifi-reconnect.sh to get better AP           ║${RESET}"
    echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    ISSUES_FOUND=1
fi

if [ -n "$AVG_RTT" ]; then
    AVG_INT=$(printf "%.0f" "$AVG_RTT" 2>/dev/null || echo "0")
    if [ "$AVG_INT" -gt 100 ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${YELLOW}${BOLD}║  ⚠️  High Latency Detected (${AVG_RTT}ms)                     ║${RESET}"
        echo -e "${YELLOW}${BOLD}╠════════════════════════════════════════════════════════════╣${RESET}"
        echo -e "${YELLOW}║  Possible causes:                                          ║${RESET}"
        echo -e "${YELLOW}║    • Channel congestion                                    ║${RESET}"
        echo -e "${YELLOW}║    • Weak signal or AP overload                            ║${RESET}"
        echo -e "${YELLOW}║  → Try: ./wifi-reconnect.sh to get different channel/AP   ║${RESET}"
        echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        ISSUES_FOUND=1
    fi
fi

if [[ "$LOSS" != "0.0%" ]] && [[ -n "$LOSS" ]]; then
    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║  ❌  PACKET LOSS DETECTED (${LOSS})                           ║${RESET}"
    echo -e "${RED}${BOLD}╠════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${RED}║  This indicates WiFi instability!                          ║${RESET}"
    echo -e "${RED}║                                                            ║${RESET}"
    echo -e "${RED}║  → Try: ./wifi-reconnect.sh                               ║${RESET}"
    echo -e "${RED}║  → Or: Check for interference (microwave, Bluetooth)      ║${RESET}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    ISSUES_FOUND=1
fi

if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║                                                            ║${RESET}"
    echo -e "${GREEN}${BOLD}║  ✅  WiFi Connection Looks Healthy!                        ║${RESET}"
    echo -e "${GREEN}${BOLD}║                                                            ║${RESET}"
    if [ -n "$RSSI" ] && [ -n "$AVG_RTT" ]; then
        printf "${GREEN}${BOLD}║      Signal: %-8s  Latency: %-10s  Loss: %-6s ║${RESET}\n" "${RSSI} dBm" "${AVG_RTT}ms" "${LOSS}"
    fi
    echo -e "${GREEN}${BOLD}║                                                            ║${RESET}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
fi

echo ""

# Check if Netskope is running
if pgrep -f "NetskopeClientMacAppProxy" > /dev/null; then
    echo -e "${YELLOW}Note: Netskope VPN is active${RESET}"
    echo "  Run: ${BOLD}./check_netskope.py${RESET} for detailed Netskope diagnostics"
fi

# Correct the mDNSResponder check - look for actual process restarts, not log lines
MDNS_PID=$(pgrep -x mDNSResponder)
if [ -n "$MDNS_PID" ]; then
    MDNS_UPTIME=$(ps -o etime= -p "$MDNS_PID" | tr -d ' ')
    echo "  mDNSResponder uptime: $MDNS_UPTIME (stable if > 1 hour)"
fi

# DNS flush recommendation
echo -e "\n${BOLD}Quick Fixes to Try:${RESET}"
echo "1. Flush DNS cache:"
echo "   ${BOLD}sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder${RESET}"
echo ""
echo "2. Renew DHCP lease:"
echo "   ${BOLD}sudo ipconfig set en0 DHCP${RESET}"
echo ""
echo "3. Reset WiFi interface:"
echo "   ${BOLD}./net-reset.sh${RESET}"
echo ""
echo "4. Check detailed Netskope logs:"
echo "   ${BOLD}./netskope-analyzer.py --follow --preset errors${RESET}"
echo ""
echo "5. Disable/re-enable WiFi (nuclear option):"
echo "   ${BOLD}networksetup -setairportpower en0 off && sleep 3 && networksetup -setairportpower en0 on${RESET}"

echo -e "\n${BOLD}=== End of Diagnostic ===${RESET}\n"
