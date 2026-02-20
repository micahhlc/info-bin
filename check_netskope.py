#!/Users/micah.cheng/.pyenv/shims/python

import subprocess
import os
import sys
import time

# --- CONFIGURATION ---
# The processes that MUST be running
PROCESSES = ["Netskope", "stAgentNE"]

# Domains to test connectivity
TARGETS = {
    "Internet (Google)": "8.8.8.8",
    "Company (Rakuten)": "rakuten.com"  # Adjust if you have a specific internal IP
}

# Log file to analyze
LOG_FILE = "/Library/Logs/Netskope/nsdebuglog.log"
CONFIG_FILE = "/Library/Application Support/Netskope/STAgent/nsuserconfig.json"

# Colors for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"

def print_status(message, status):
    if status == "OK":
        print(f"[{GREEN} OK {RESET}] {message}")
    elif status == "FAIL":
        print(f"[{RED}FAIL{RESET}] {message}")
    elif status == "WARN":
        print(f"[{YELLOW}WARN{RESET}] {message}")

def check_process(proc_name):
    """Checks if a process is running using pgrep."""
    try:
        # pgrep returns 0 if found, 1 if not
        subprocess.check_call(["pgrep", "-f", proc_name], stdout=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

def check_ping(host):
    """Pings a host once with a 1.5s timeout."""
    try:
        subprocess.check_call(
            ["ping", "-c", "1", "-W", "1500", host],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return True
    except subprocess.CalledProcessError:
        return False

def check_ipv6_status():
    """Checks if IPv6 is disabled on Wi-Fi (Start of your issues)."""
    try:
        result = subprocess.check_output(["networksetup", "-getinfo", "Wi-Fi"], text=True)
        if "IPv6: Automatic" in result:
            return False # Bad (It should be Off or Link-local)
        return True # Good
    except:
        return True # Skip if not on Wi-Fi

def analyze_logs():
    """Reads the last 50 lines of the log for errors."""
    if not os.path.exists(LOG_FILE):
        return "Log file not found."

    try:
        # Tail the log file
        logs = subprocess.check_output(["tail", "-n", "50", LOG_FILE], text=True)
        
        issues = []
        if "err:2" in logs:
            issues.append("Config Missing (err:2)")
        if "invalidated" in logs:
            issues.append("App Proxy Crash")
        if "is not bound" in logs:
            issues.append("IPv6 Binding Error")
        
        return issues
    except PermissionError:
        return "Permission Denied (Run with sudo)"

def main():
    print(f"\n--- 🛡️  NETSKOPE HEALTH CHECK ---")
    
    # 1. Check Processes
    all_procs_ok = True
    for proc in PROCESSES:
        if check_process(proc):
            print_status(f"Process '{proc}' is running", "OK")
        else:
            print_status(f"Process '{proc}' is DEAD", "FAIL")
            all_procs_ok = False

    # 2. Check Config File
    if os.path.exists(CONFIG_FILE):
        print_status("Config file exists", "OK")
    else:
        print_status("Config file missing (nsuserconfig.json)", "FAIL")

    # 3. Check IPv6 (The root cause of your crash)
    if check_ipv6_status():
        print_status("IPv6 is Disabled/Link-Local", "OK")
    else:
        print_status("IPv6 is AUTOMATIC (Potential Crash Risk!)", "WARN")

    # 4. Check Connectivity
    print("\n--- 🌐 CONNECTIVITY ---")
    internet = check_ping(TARGETS["Internet (Google)"])
    print_status(f"Internet Reachability", "OK" if internet else "FAIL")
    
    company = check_ping(TARGETS["Company (Rakuten)"])
    print_status(f"Company Network Reachability", "OK" if company else "FAIL")

    # 5. Log Analysis
    print("\n--- 📝 LOG ANALYSIS (Last 50 lines) ---")
    log_issues = analyze_logs()
    
    if isinstance(log_issues, list):
        if not log_issues:
            print_status("No critical errors found recently", "OK")
        else:
            for issue in log_issues:
                print_status(f"Log Error: {issue}", "FAIL")
    else:
        print_status(log_issues, "WARN")

    # 6. Diagnosis
    print("\n--- 🩺 DIAGNOSIS ---")
    if not all_procs_ok:
        print(f"{RED}CRITICAL:{RESET} Netskope is not running. Run: sudo open /Applications/Netskope Client.app")
    elif internet and not company:
        print(f"{YELLOW}ISSUE:{RESET} Internet works, but Company blocked. Check VPN/NPA Status.")
    elif not internet:
        print(f"{RED}CRITICAL:{RESET} Total Network Failure. Kill Netskope immediately.")
    else:
        print(f"{GREEN}ALL SYSTEMS NOMINAL.{RESET} You are good to go.")
    print("")

if __name__ == "__main__":
    main()
