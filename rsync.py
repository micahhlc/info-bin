#!/usr/bin/env python3
"""
=============================================================================
 SMART RSYNC MANAGER
=============================================================================
1. WHAT IS IT?
   A smart Python wrapper for 'rsync'. It runs your transfers with a clean, 
   modern UI (no scrolling text wall), captures errors for a final summary, 
   and performs an AUTOMATIC POST-SYNC AUDIT to verify exactly which files 
   are Missing or Extra.

2. PREREQUISITES
   - Python 3 (Included on macOS).
   - Modern 'rsync' (v3.1+) recommended for progress bars.
     Install via: brew install rsync

3. HOW TO USE
   Run from terminal:
   ./rsync.py /path/to/source /path/to/dest

   IMPORTANT - TRAILING SLASH BEHAVIOR:
   - Source ends with / (e.g. /Pictures/): Copies CONTENTS of Pictures into Dest.
   - Source NO slash    (e.g. /Pictures):  Copies the FOLDER Pictures into Dest.

=============================================================================
"""
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
# =============================================================================
# UTILS & UI
# =============================================================================
def print_banner(source, dest, mode="SYNC"):
    print(f"{BOLD}============================================================{RESET}")
    print(f" {BOLD}🐍 Python Smart Rsync Manager{RESET} | Mode: {mode}")
    print(f"============================================================")
    print(f" {BOLD}Source:{RESET} {source}")
    print(f" {BOLD}Dest:  {RESET} {dest}")
    print(f" {BOLD}Rsync: {RESET} {RSYNC_EXEC}")
    print(f"============================================================\n")
    print_legend()

def print_legend():
    print(f"{BOLD}LEGEND:{RESET}")
    print(f" ⏳ Starting   ✅ Success   ❌ Error/Failure   ⚠️  Warning")
    print(f" {BOLD}xfr#:{RESET} File Transfer Count   {BOLD}ir-chk:{RESET} Checked/Total Files (Indexing)")
    print(f"============================================================\n")

# =============================================================================
# CORE LOGIC
# =============================================================================
def build_rsync_cmd(source, dest, dry_run=False):
    # Construct Rsync Command
    cmd = [
        RSYNC_EXEC, "-a", "--partial", "--no-perms", "--no-owner", "--no-group",
        "--info=progress2", "-v", 
        "--exclude=Photos Library.photoslibrary",
        "--exclude=.DS_Store"
    ]
    
    # Slash Logic (Pass verbatim so user controls folder vs content)
    cmd.append(source)
    # Dest slash usually irrelevant, strip strictly for consistency
    cmd.append(dest.rstrip('/'))

    if dry_run:
        cmd.insert(1, "-n")
        print(f"{YELLOW}[DRY RUN] Executing: {' '.join(cmd)}{RESET}")
    
    return cmd

def update_ui_status(filename, progress_line):
    # Move up 1 line, Clear, Print Filename
    sys.stdout.write(f"\r{UP}{CLEAR_LINE}")
    # Truncate filename nicely if too long
    display_name = (filename[:75] + '..') if len(filename) > 75 else filename
    sys.stdout.write(f"{BOLD}File:{RESET} {display_name}\n") 
    
    # Print Progress Line
    sys.stdout.write(f"{CLEAR_LINE}{GREEN}{progress_line}{RESET}")
    sys.stdout.flush()

def print_error_alert(line):
    # Print error immediately above the status area
    sys.stdout.write(f"\r{UP}{CLEAR_LINE}") 
    sys.stdout.write(f"{RED}❌ {line}{RESET}\n\n") # Push status down 2 lines to make room
    sys.stdout.flush()

def run_sync(source, dest, dry_run=False):
    cmd = build_rsync_cmd(source, dest, dry_run)
    
    # Launch Process
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,            # Line buffered
        universal_newlines=True
    )

    # State tracking
    errors = []
    current_file = "Initializing..."
    start_time = time.time()
    
    print(f"{CYAN}⏳ Starting Sync/Scan...{RESET}")
    print("") # Reserve space for status UI

    try:
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            
            line = line.strip()
            if not line:
                continue

            # 1. Progress Line? (Contains % and xfr#)
            if "%" in line and "xfr#" in line:
                update_ui_status(current_file, line)
            
            # 2. Error Line? (Strict check)
            elif line.startswith("rsync:") or line.startswith("rsync error:") or "No space left" in line:
                errors.append(line)
                print_error_alert(line)

            # 3. Filename? (Everything else)
            elif not line.startswith("sending incremental"):
                 current_file = line

    except KeyboardInterrupt:
        print(f"\n\n{YELLOW}🛑 Operation cancelled by user.{RESET}")
        return

    # Finish & Report
    duration = time.time() - start_time
    return_code = process.poll()
    
    print_summary(duration, return_code, errors)
    
    # Post-Sync Audit
    print("\n🔍 Running Post-Sync Verification & Audit...")
    run_audit(source, dest)

def print_summary(duration, return_code, errors):
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

# =============================================================================
# AUDIT & VERIFICATION
# =============================================================================
def run_audit(source, dest):
    # Force content comparison by ensuring trailing slashes
    src_clean = source.rstrip('/') + '/'
    dest_clean = dest.rstrip('/') + '/'
    
    # We use -n (dry run) + -i (itemize) + --delete (to see extras)
    cmd = [
        RSYNC_EXEC, "-avn", "-i", "--delete", "--ignore-errors", "--force",
        src_clean, dest_clean
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, _ = proc.communicate()
    
    lines = out.split('\n')
    
    # Parse rsync itemize output:
    # >f+++++++++ : File missing in dest (Transfer needed)
    # *deleting   : Extra file in dest
    
    missing = []
    extras = []
    
    for line in lines:
        if not line: continue
        parts = line.split(' ', 1)
        if len(parts) < 2: continue
        
        code = parts[0]
        filename = parts[1]
        
        if line.startswith('*deleting'):
             # "deleting filename" -> filename is the extra
             extras.append(line.replace('*deleting   ', ''))
        elif code.startswith('>f') and '+++++++++' in code:
             # Purely new file transfer >f+++++++++
             missing.append(filename)
        # Note: We ignore changed files (.d..t...) to focus on Missing/Extra
        
    # REPORTING
    if len(missing) == 0 and len(extras) == 0:
        print(f" {GREEN}✨ Perfect Match! Source and Destination are identical.{RESET}")
        return

    print(f"{BOLD}------------------------------------------------------------{RESET}")
    print(f" {BOLD}Audit Report{RESET}")
    print(f"{BOLD}------------------------------------------------------------{RESET}")
    
    if len(missing) > 0:
        print(f" {RED}❌ MISSING in Dest ({len(missing)} files):{RESET}")
        print(f"    (These failed to copy or were skipped)")
        for f in missing[:15]:
            print(f"    - {f}")
        if len(missing) > 15:
            print(f"    ... and {len(missing)-15} more.")
        print("")

    if len(extras) > 0:
        print(f" {YELLOW}⚠️  EXTRA in Dest ({len(extras)} files):{RESET}")
        print(f"    (These exist in Dest but not Source)")
        for f in extras[:15]:
            print(f"    - {f}")
        if len(extras) > 15:
            print(f"    ... and {len(extras)-15} more.")
        print("")
        
    print(f" {BOLD}Tip:{RESET} Use --delete to remove extras, or check errors for missing files.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 rsync.py /source /dest")
        sys.exit(1)
        
    source_arg = sys.argv[1]
    dest_arg = sys.argv[2]
    
    print_banner(source_arg, dest_arg)
    run_sync(source_arg, dest_arg)
