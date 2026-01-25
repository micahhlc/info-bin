#!/usr/bin/env python3
import sys
import os
import subprocess
import shutil
import time
import re

# =============================================================================
# CONFIGURATION
# =============================================================================
# Helper to find rsync
def find_rsync():
    # Prefer Homebrew rsync for progress features
    paths = ["/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]
    for p in paths:
        if os.path.exists(p) and os.access(p, os.X_OK):
            return p
    return "rsync" # Fallback to path

RSYNC_EXEC = find_rsync()

# ANSI Colors
CYAN = "\033[96m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"
BOLD = "\033[1m"
CLEAR_LINE = "\033[K"
UP = "\033[A"

# =============================================================================
# UTILS
# =============================================================================
def print_banner(source, dest, mode="SYNC"):
    print(f"{BOLD}============================================================{RESET}")
    print(f" {BOLD}🐍 Python Smart Rsync Manager{RESET} | Mode: {mode}")
    print(f"============================================================")
    print(f" {BOLD}Source:{RESET} {source}")
    print(f" {BOLD}Dest:  {RESET} {dest}")
    print(f" {BOLD}Rsync: {RESET} {RSYNC_EXEC}")
    print(f"============================================================\n")

def human_size(bytes_val):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:.2f} TB"

# =============================================================================
# MAIN SYNC LOGIC
# =============================================================================
def run_sync(source, dest, dry_run=False):
    # Construct Rsync Command
    # -a: archive
    # --partial: resume support
    # --no-perms etc: filesystem compatibility
    # --info=progress2: Total progress info
    # -v: Verbose (We need this to capture filenames, but we suppress them from UI)
    cmd = [
        RSYNC_EXEC, "-a", "--partial", "--no-perms", "--no-owner", "--no-group",
        "--info=progress2", "-v", 
        "--exclude=Photos Library.photoslibrary",
        "--exclude=.DS_Store"
    ]
    
    # Slash Logic (Match bash script behavior)
    # If source ends with /, rsync copies contents.
    # If source usually doesn't, rsync copies folder.
    # Python script passes arguments exactly as provided.
    cmd.append(source)
    
    # Dest usually needs slash stripped by convention in scripts, 
    # but rsync handles dest slash fine. We'll strip for consistency.
    cmd.append(dest.rstrip('/'))

    if dry_run:
        cmd.insert(1, "-n")
        print(f"{YELLOW}[DRY RUN] Executing: {' '.join(cmd)}{RESET}")

    # Launch Process
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,            # Line buffered
        universal_newlines=True
    )

    # State
    errors = []
    last_progress_line = ""
    current_file = "Initializing..."
    start_time = time.time()
    
    print(f"{CYAN}⏳ Starting Sync/Scan...{RESET}")
    print("") # Spacer for UI

    try:
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            
            line = line.strip()
            if not line:
                continue

            # Check if it's a progress line
            # Pattern: 1,024,000 12% 10.5MB/s 0:00:05 ...
            if "%" in line and "xfr#" in line:
                last_progress_line = line
                # Redraw Status Area
                # Move up 1 line, Print Status, Newline, Print Progress
                sys.stdout.write(f"\r{UP}{CLEAR_LINE}")
                sys.stdout.write(f"{BOLD}File:{RESET} {current_file[:80]}\n") # Truncate file if long
                sys.stdout.write(f"{CLEAR_LINE}{GREEN}{line}{RESET}")
                sys.stdout.flush()
            
            # Check if Error
            elif "error" in line.lower() or "failed" in line.lower():
                errors.append(line)
                # Print error immediately above the status area
                sys.stdout.write(f"\r{UP}{CLEAR_LINE}") 
                sys.stdout.write(f"{RED}❌ {line}{RESET}\n\n") # Push status down
                sys.stdout.flush()

            # Otherwise, it's likely a filename (since we used -v)
            # We don't print it to history, we just update 'current_file'
            elif not line.startswith("sending incremental"):
                 # Ignore the header lines
                 current_file = line

    except KeyboardInterrupt:
        print(f"\n\n{YELLOW}🛑 Operation cancelled by user.{RESET}")
        return

    return_code = process.poll()
    end_time = time.time()
    duration = end_time - start_time

    # Final Report
    print(f"\n\n{BOLD}============================================================{RESET}")
    print(f" {BOLD}Summary{RESET}")
    print(f"============================================================")
    print(f" Time Taken: {duration:.1f}s")
    
    if len(errors) > 0:
        print(f" {RED}Errors Found: {len(errors)}{RESET}")
        print(" ------------------------------------------------------------")
        for e in errors:
            print(f" - {e}")
        print(" ------------------------------------------------------------")
        print(f" {YELLOW}⚠️  Sync finished with errors. Please review above.{RESET}")
    elif return_code == 0:
        print(f" {GREEN}✅ Sync Completed Successfully.{RESET}")
    else:
        print(f" {RED}❌ Rsync exited with code {return_code}{RESET}")
    
    # Post-Sync Extra File Check
    print("\n🔍 Checking for extra files in Destination...")
    check_extras(source, dest.rstrip('/'))

# =============================================================================
# EXTRA FILE CHECKER
# =============================================================================
def check_extras(source, dest):
    # Force content comparison by ensuring trailing slashes
    src_clean = source.rstrip('/') + '/'
    dest_clean = dest.rstrip('/') + '/'
    
    cmd = [
        RSYNC_EXEC, "-avn", "--delete", "--ignore-errors", "--force",
        src_clean, dest_clean
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, _ = proc.communicate()
    
    # Count "deleting" lines
    extras = [line for line in out.split('\n') if line.startswith('deleting ')]
    count = len(extras)
    
    if count > 0:
        print(f" {YELLOW}⚠️  Found {count} extra files in Destination.{RESET}")
        print(f"    (Run ./rsync-compare.sh to view/cleanup)")
    else:
        print(f" {GREEN}✨ Destination is perfectly clean (Exact mirror).{RESET}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 rsync.py /source /dest")
        sys.exit(1)
        
    source_arg = sys.argv[1]
    dest_arg = sys.argv[2]
    
    print_banner(source_arg, dest_arg)
    run_sync(source_arg, dest_arg)
