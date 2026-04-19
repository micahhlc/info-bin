#!/Users/micah.cheng/.pyenv/shims/python

import subprocess
import os
import re
import datetime

# ---------------------------------------------------------------------------
# TARGET SITES — the 4 sites that must be reachable
# All route via Netskope (utun4). Confluence/Git/Jira are internal IPs
# (10.6.16.x) served via Netskope's corporate gateway.
# ---------------------------------------------------------------------------
TARGET_SITES = [
    ("r-ai",       "https://r-ai.tsd.public.rakuten-it.com/en-US"),
    ("Confluence", "https://confluence.rakuten-it.com/confluence"),
    ("Git",        "https://git.rakuten-it.com"),
    ("Jira",       "https://jira.rakuten-it.com"),
]

LOG_FILE         = "/Library/Logs/Netskope/nsdebuglog.log"
CONFIG_FILE      = "/Library/Application Support/Netskope/STAgent/nsuserconfig.json"
NETSKOPE_RESTART = "sudo pkill -f NetskopeClientMacAppProxy"
CONFIG_FIX       = (
    'sudo sh -c \'printf "{}" > "/Library/Application Support/Netskope/STAgent/nsuserconfig.json"\''
    ' && sudo chown root:admin "/Library/Application Support/Netskope/STAgent/nsuserconfig.json"'
    ' && sudo chmod 644 "/Library/Application Support/Netskope/STAgent/nsuserconfig.json"'
)
CISCO_DISCONNECT = "/opt/cisco/secureclient/bin/vpn disconnect"

NETSKOPE_TUNNEL = "utun4"
CISCO_TUNNEL    = "utun3"

GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

IS_ROOT = (os.geteuid() == 0)


def ok(msg):   print(f"[{GREEN} OK {RESET}] {msg}")
def fail(msg): print(f"[{RED}FAIL{RESET}] {msg}")
def warn(msg): print(f"[{YELLOW}WARN{RESET}] {msg}")


def run_cmd(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def capture(cmd, **kwargs):
    return subprocess.check_output(cmd, **kwargs)


def auto_fix_sudo(description, cmd):
    """Run a sudo fix if root, else print the manual command."""
    if IS_ROOT:
        r = run_cmd(cmd, shell=True)
        if r.returncode == 0:
            ok(f"  Auto-fixed: {description}")
            return True
        fail(f"  Auto-fix failed: {description}")
        return False
    print(f"  {BOLD}Run to fix:{RESET} {cmd}")
    return False


# ---------------------------------------------------------------------------
# CHECKS
# ---------------------------------------------------------------------------

def check_process(name):
    try:
        run_cmd(["pgrep", "-f", name], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False


def get_iface_info(iface):
    """Returns (ipv4, mtu) or (None, None)."""
    try:
        out = capture(["ifconfig", iface], text=True, stderr=subprocess.DEVNULL)
        ip  = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", out)
        mtu = re.search(r"mtu (\d+)", out)
        return (ip.group(1) if ip else None), (int(mtu.group(1)) if mtu else None)
    except subprocess.CalledProcessError:
        return None, None


def get_cisco_vpn_stats():
    """Returns (connected, client_ip, server_ip)."""
    try:
        out = capture(["/opt/cisco/secureclient/bin/vpn", "stats"],
                      text=True, stderr=subprocess.DEVNULL)
        connected = "Connection State:            Connected" in out
        client_ip = re.search(r"Client Address \(IPv4\):\s+(\S+)", out)
        server_ip = re.search(r"Server Address:\s+(\S+)", out)
        return (connected,
                client_ip.group(1) if client_ip else None,
                server_ip.group(1) if server_ip else None)
    except Exception:
        return False, None, None


def check_https(url):
    """Returns True if site responds with any valid HTTP code (200/30x/401/403)."""
    try:
        code = capture(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "--connect-timeout", "5", "--max-time", "8", "-L", url],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        return int(code) in (200, 301, 302, 401, 403)
    except Exception:
        return False


def get_route_iface(host):
    try:
        out = capture(["route", "-n", "get", host], text=True, stderr=subprocess.DEVNULL)
        m = re.search(r"interface: (\S+)", out)
        return m.group(1) if m else None
    except Exception:
        return None


def analyze_recent_logs(minutes=5):
    """Scan only log lines from the last N minutes to avoid stale noise."""
    if not os.path.exists(LOG_FILE):
        return []
    try:
        lines = capture(["tail", "-n", "1000", LOG_FILE], text=True).splitlines()
        cutoff = datetime.datetime.now() - datetime.timedelta(minutes=minutes)
        issues = []
        seen = set()

        for line in lines:
            m = re.match(r"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", line)
            if m:
                try:
                    ts = datetime.datetime.strptime(m.group(1), "%Y/%m/%d %H:%M:%S")
                    if ts < cutoff:
                        continue
                except ValueError:
                    pass

            def add(key, msg):
                if key not in seen:
                    seen.add(key)
                    issues.append(msg)

            if "err:2" in line:
                add("err2", "err:2 — nsuserconfig.json missing/unreadable (recent)")
            if "invalidated" in line:
                add("invalidated", "App Proxy invalidated — AOAC reconnect triggered")
            if "ENETUNREACH" in line or "err:51" in line:
                add("enetunreach", "ENETUNREACH (err:51) — WiFi switch race condition")
            if "Cannot allocate memory" in line:
                add("oom", "Cannot allocate memory")

        return issues
    except PermissionError:
        return ["Permission denied reading log (run with sudo for full log analysis)"]


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main():
    tunnel_ok = True
    any_warn  = False

    print(f"\n{BOLD}--- 🛡️  NETSKOPE HEALTH CHECK ---{RESET}")

    # 1. Processes
    ne_ok = check_process("NetskopeClientMacAppProxy")
    if ne_ok:
        ok("Netskope extension (NetskopeClientMacAppProxy) running")
    else:
        fail("Netskope extension is DEAD")
        print(f"  {BOLD}Run to fix:{RESET} {NETSKOPE_RESTART}")
        tunnel_ok = False

    if not check_process("Netskope Client"):
        warn("Netskope Client app not running (menu bar agent — usually not critical)")

    # 2. nsuserconfig.json
    if os.path.exists(CONFIG_FILE) and os.path.getsize(CONFIG_FILE) >= 2:
        ok(f"nsuserconfig.json OK ({os.path.getsize(CONFIG_FILE)} bytes)")
    elif os.path.exists(CONFIG_FILE):
        fail("nsuserconfig.json is empty — will cause crashes on reconnect")
        auto_fix_sudo("recreate nsuserconfig.json", CONFIG_FIX)
    else:
        fail("nsuserconfig.json MISSING — will cause crashes on reconnect")
        auto_fix_sudo("create nsuserconfig.json", CONFIG_FIX)

    # 3. Netskope tunnel
    print(f"\n{BOLD}--- 🔒 TUNNEL INTERFACES ---{RESET}")
    ns_ip, ns_mtu = get_iface_info(NETSKOPE_TUNNEL)

    if ns_ip:
        ok(f"Netskope ({NETSKOPE_TUNNEL}) IP: {ns_ip}  MTU: {ns_mtu}")
        if ns_mtu and ns_mtu < 1300:
            warn(f"Netskope MTU {ns_mtu} is low — video calls / QUIC may degrade")
    else:
        fail(f"Netskope tunnel ({NETSKOPE_TUNNEL}) has no IP — all sites will fail")
        print(f"  {BOLD}Run to fix:{RESET} {NETSKOPE_RESTART}")
        tunnel_ok = False

    # 4. Cisco VPN — informational only, not required for the 4 target sites
    vpn_connected, vpn_client_ip, _ = get_cisco_vpn_stats()
    cisco_ip, cisco_mtu = get_iface_info(CISCO_TUNNEL)

    if vpn_connected:
        if cisco_ip:
            ok(f"Cisco VPN ({CISCO_TUNNEL}) connected  IP: {cisco_ip}  MTU: {cisco_mtu}")
        elif vpn_client_ip and ns_ip and vpn_client_ip == ns_ip:
            warn(f"Cisco VPN IP conflict: VPN and Netskope share the same IP ({vpn_client_ip})")
            warn("  This is a permanent conflict — reconnecting VPN will not fix it.")
            warn("  Netskope already provides internal access. Try: vpn disconnect and test your sites.")
            any_warn = True
        else:
            warn(f"Cisco VPN connected but {CISCO_TUNNEL} has no IPv4 (assigned: {vpn_client_ip})")
            any_warn = True
    else:
        warn("Cisco VPN disconnected (not required for the 4 target sites)")

    # 5. Target site checks — skip if tunnel is known-down to avoid redundant FAILs
    print(f"\n{BOLD}--- 🌐 TARGET SITE CHECKS ---{RESET}")

    if not tunnel_ok:
        warn("Skipping site checks — Netskope tunnel is down (fix tunnel first)")
        site_results = {label: False for label, _ in TARGET_SITES}
    else:
        site_results = {}
        for label, url in TARGET_SITES:
            host  = re.sub(r"https?://([^/]+).*", r"\1", url)
            iface = get_route_iface(host)
            up    = check_https(url)
            note  = f" via {iface}" if iface else ""
            if up:
                ok(f"{label}{note}")
            else:
                fail(f"{label} — NOT reachable{note}")
            site_results[label] = up

    # 6. Recent log scan (last 5 minutes only)
    print(f"\n{BOLD}--- 📝 RECENT LOG ACTIVITY (last 5 min) ---{RESET}")
    log_issues = analyze_recent_logs(minutes=5)
    if log_issues:
        for entry in log_issues:
            warn(f"Log: {entry}")
    else:
        ok("No issues in recent logs")

    # 7. Diagnosis
    print(f"\n{BOLD}--- 🩺 DIAGNOSIS ---{RESET}")
    failed_sites = [l for l, v in site_results.items() if not v]

    if not tunnel_ok:
        if not vpn_connected:
            # Cisco VPN disconnect triggers Netskope AOAC re-negotiation → utun4 briefly loses IP
            # In practice, reconnecting Cisco VPN is the reliable fix
            print(f"{RED}CRITICAL:{RESET} Netskope tunnel is down — Cisco VPN disconnection triggered re-negotiation.")
            print(f"  {BOLD}Fix:{RESET} Reconnect Cisco VPN via the menu bar app (Cisco Secure Client)")
        else:
            # VPN is connected but tunnel still has no IP — Netskope itself is broken
            print(f"{RED}CRITICAL:{RESET} Netskope tunnel is down (Cisco VPN is connected but tunnel has no IP).")
            print(f"  {BOLD}Step 1:{RESET} {NETSKOPE_RESTART}")
            print(f"  {BOLD}Step 2:{RESET} If still failing, verify nsuserconfig.json:")
            print(f"          {CONFIG_FIX}")

    elif failed_sites:
        print(f"{RED}CRITICAL:{RESET} Unreachable: {', '.join(failed_sites)}")
        iface = get_route_iface(re.sub(r"https?://([^/]+).*", r"\1", TARGET_SITES[0][1]))
        if iface and iface != NETSKOPE_TUNNEL:
            print(f"  Traffic is routing via {iface} instead of Netskope ({NETSKOPE_TUNNEL}).")
        print(f"  {BOLD}Step 1:{RESET} Reconnect Cisco VPN via the menu bar app (Cisco Secure Client)")
        print(f"  {BOLD}Step 2:{RESET} Wait 10s, then run this script again")
        print(f"  {BOLD}Step 3:{RESET} If still failing, restart Netskope: {NETSKOPE_RESTART}")
        print(f"  {BOLD}Step 4:{RESET} If still failing, verify nsuserconfig.json: {CONFIG_FIX}")

    elif any_warn:
        print(f"{YELLOW}OK with warnings:{RESET} All 4 sites reachable.")
        print(f"  Cisco VPN IP conflict is a known architectural issue (same IP pool as Netskope).")
        print(f"  Reconnecting VPN will not fix it. Consider staying on Netskope-only.")

    else:
        print(f"{GREEN}ALL SYSTEMS NOMINAL.{RESET} All 4 target sites are reachable.")

    print("")


if __name__ == "__main__":
    main()
