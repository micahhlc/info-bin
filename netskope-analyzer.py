#!/usr/bin/env python3
"""
Netskope Log Analyzer
Simplifies troubleshooting of Netskope logs by filtering noise and highlighting issues.
"""

import argparse
import re
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import List, Pattern

# ANSI color codes
class Colors:
    RED = '\033[91m'
    YELLOW = '\033[93m'
    GREEN = '\033[92m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

# Log file paths
LOG_DIR = Path("/Library/Logs/Netskope")
LOGS = {
    'debug': LOG_DIR / "nsdebuglog.log",
    'aux': LOG_DIR / "nsAuxiSvc.log",
    'driver': LOG_DIR / "nsDriverLogs.log",
}

# Filter presets
PRESETS = {
    'errors': {
        'include': ['error', 'failed', 'fail', 'disconnect', 'timeout', 'ENETUNREACH'],
        'exclude': ['Unable to open UDP flow'],
        'description': 'All errors and failures (recommended default)'
    },
    'tunnel': {
        'include': ['tunnel', 'established', 'sessId', 'TLS', 'handshake', 'gateway'],
        'exclude': ['Unable to open UDP flow'],
        'description': 'Tunnel connection state and establishment'
    },
    'dns': {
        'include': ['DNS', 'resolution', 'getaddrinfo', 'lookup', 'resolve'],
        'exclude': ['Unable to open UDP flow'],
        'description': 'DNS resolution issues'
    },
    'aoac': {
        'include': ['AOAC', 'App Proxy Connection', 'invalidated', 'reconnect', 'network change'],
        'exclude': ['Unable to open UDP flow'],
        'description': 'Auto-reconnect on network change'
    },
    'config': {
        'include': ['nsconfig', 'nsuserconfig', 'nssteering', 'policy', 'download'],
        'exclude': [],
        'description': 'Configuration loading and updates'
    },
    'rakuten': {
        'include': ['rakuten', 'r-vpn', 'r-ai', 'confluence', 'git', 'jira'],
        'exclude': ['Unable to open UDP flow'],
        'description': 'Rakuten-specific traffic'
    },
    'vpn': {
        'include': ['utun', 'VPN', 'Cisco', '10.83', '10.84', '10.85', '10.86', '10.87'],
        'exclude': [],
        'description': 'VPN and tunnel interface issues'
    },
    'all': {
        'include': [],
        'exclude': ['Unable to open UDP flow'],
        'description': 'Show everything (excluding UDP spam)'
    }
}


def colorize(text: str, color: str) -> str:
    """Add color to text if stdout is a TTY."""
    if sys.stdout.isatty():
        return f"{color}{text}{Colors.RESET}"
    return text


def highlight_line(line: str) -> str:
    """Apply color highlighting to important patterns in log lines."""
    if not sys.stdout.isatty():
        return line

    # Error patterns - RED
    if re.search(r'\b(error|failed|fail|disconnect|timeout|ENETUNREACH)\b', line, re.IGNORECASE):
        line = re.sub(r'\b(error|failed|fail|disconnect|timeout|ENETUNREACH)\b',
                      lambda m: colorize(m.group(0), Colors.RED + Colors.BOLD), line, flags=re.IGNORECASE)

    # Warning patterns - YELLOW
    if re.search(r'\b(warning|warn|retry|attempt)\b', line, re.IGNORECASE):
        line = re.sub(r'\b(warning|warn|retry|attempt)\b',
                      lambda m: colorize(m.group(0), Colors.YELLOW), line, flags=re.IGNORECASE)

    # Success patterns - GREEN
    if re.search(r'\b(established|success|connected|ok)\b', line, re.IGNORECASE):
        line = re.sub(r'\b(established|success|connected|ok)\b',
                      lambda m: colorize(m.group(0), Colors.GREEN), line, flags=re.IGNORECASE)

    # Session/tunnel IDs - CYAN
    line = re.sub(r'\b(sessId|tunnelId|session)[:\s]+([a-zA-Z0-9\-]+)',
                  lambda m: f"{colorize(m.group(1), Colors.CYAN)}: {colorize(m.group(2), Colors.BOLD + Colors.CYAN)}",
                  line, flags=re.IGNORECASE)

    # IP addresses - BLUE
    line = re.sub(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b',
                  lambda m: colorize(m.group(1), Colors.BLUE), line)

    return line


def compile_patterns(patterns: List[str]) -> List[Pattern]:
    """Compile a list of string patterns into regex patterns."""
    return [re.compile(p, re.IGNORECASE) for p in patterns]


def matches_any_pattern(line: str, patterns: List[Pattern]) -> bool:
    """Check if line matches any of the given patterns."""
    return any(p.search(line) for p in patterns)


def filter_line(line: str, include_patterns: List[Pattern], exclude_patterns: List[Pattern]) -> bool:
    """Return True if line should be displayed based on include/exclude patterns."""
    # First check excludes (higher priority)
    if exclude_patterns and matches_any_pattern(line, exclude_patterns):
        return False

    # If no include patterns, show everything (except excludes)
    if not include_patterns:
        return True

    # Check includes
    return matches_any_pattern(line, include_patterns)


def tail_file(file_path: Path, include_patterns: List[Pattern], exclude_patterns: List[Pattern],
              lines: int = 10):
    """Tail a file in real-time (like tail -f)."""
    try:
        with open(file_path, 'r') as f:
            # Start from end if lines > 0, else start from beginning
            if lines > 0:
                f.seek(0, 2)  # Go to end
                file_size = f.tell()

                # Read backwards to get last N lines
                block_size = 1024
                blocks = []
                num_lines = 0

                while file_size > 0 and num_lines < lines:
                    if file_size < block_size:
                        block_size = file_size

                    f.seek(file_size - block_size)
                    blocks.append(f.read(block_size))
                    file_size -= block_size
                    num_lines = ''.join(blocks).count('\n')

                # Get the lines
                all_lines = ''.join(reversed(blocks)).splitlines()
                recent_lines = all_lines[-lines:] if len(all_lines) > lines else all_lines

                # Print recent lines
                for line in recent_lines:
                    if filter_line(line, include_patterns, exclude_patterns):
                        print(highlight_line(line))

            # Now follow the file
            print(colorize(f"\n=== Following {file_path.name} (Ctrl+C to stop) ===", Colors.BOLD + Colors.CYAN))
            while True:
                line = f.readline()
                if line:
                    if filter_line(line.rstrip(), include_patterns, exclude_patterns):
                        print(highlight_line(line.rstrip()))
                else:
                    time.sleep(0.1)
    except KeyboardInterrupt:
        print(colorize("\n\n=== Stopped monitoring ===", Colors.BOLD + Colors.YELLOW))
    except Exception as e:
        print(colorize(f"Error reading file: {e}", Colors.RED), file=sys.stderr)
        sys.exit(1)


def analyze_file(file_path: Path, include_patterns: List[Pattern], exclude_patterns: List[Pattern],
                 last_lines: int = None):
    """Analyze historical log file."""
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()

            if last_lines:
                lines = lines[-last_lines:]

            matched_count = 0
            for line in lines:
                line = line.rstrip()
                if filter_line(line, include_patterns, exclude_patterns):
                    print(highlight_line(line))
                    matched_count += 1

            print(colorize(f"\n=== {matched_count} matching lines found ===", Colors.BOLD + Colors.GREEN))
    except Exception as e:
        print(colorize(f"Error reading file: {e}", Colors.RED), file=sys.stderr)
        sys.exit(1)


def list_presets():
    """Print available filter presets."""
    print(colorize("\nAvailable presets:", Colors.BOLD + Colors.CYAN))
    for name, preset in PRESETS.items():
        print(f"\n  {colorize(name, Colors.BOLD + Colors.GREEN)}: {preset['description']}")
        if preset['include']:
            print(f"    Include: {', '.join(preset['include'][:5])}" +
                  (f" ... ({len(preset['include'])} total)" if len(preset['include']) > 5 else ""))
        if preset['exclude']:
            print(f"    Exclude: {', '.join(preset['exclude'])}")
    print()


def main():
    parser = argparse.ArgumentParser(
        description='Netskope Log Analyzer - Filter and analyze Netskope logs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Real-time monitoring of errors
  %(prog)s --follow --preset errors

  # Real-time tunnel status monitoring
  %(prog)s -f -p tunnel

  # Analyze last 100 lines for AOAC issues
  %(prog)s -n 100 -p aoac

  # Custom filter for Rakuten traffic with errors
  %(prog)s -f -i rakuten -i error -e "UDP flow"

  # Check config issues in auxiliary service log
  %(prog)s -p config -l aux

  # List all available presets
  %(prog)s --list-presets
        '''
    )

    parser.add_argument('-l', '--log', choices=['debug', 'aux', 'driver'], default='debug',
                        help='Log file to analyze (default: debug)')
    parser.add_argument('-f', '--follow', action='store_true',
                        help='Follow log file in real-time (like tail -f)')
    parser.add_argument('-n', '--lines', type=int, metavar='N',
                        help='Number of lines to show (default: 10 with --follow, all without)')
    parser.add_argument('-p', '--preset', choices=list(PRESETS.keys()),
                        help='Use a filter preset (see --list-presets)')
    parser.add_argument('-i', '--include', action='append', metavar='PATTERN',
                        help='Include lines matching pattern (can be used multiple times)')
    parser.add_argument('-e', '--exclude', action='append', metavar='PATTERN',
                        help='Exclude lines matching pattern (can be used multiple times)')
    parser.add_argument('--list-presets', action='store_true',
                        help='List all available filter presets and exit')
    parser.add_argument('--no-color', action='store_true',
                        help='Disable colored output')

    args = parser.parse_args()

    # Disable colors if requested
    if args.no_color:
        for attr in dir(Colors):
            if not attr.startswith('_'):
                setattr(Colors, attr, '')

    # List presets and exit
    if args.list_presets:
        list_presets()
        return

    # Determine include/exclude patterns
    include_patterns = []
    exclude_patterns = []

    if args.preset:
        preset = PRESETS[args.preset]
        include_patterns.extend(preset['include'])
        exclude_patterns.extend(preset['exclude'])

    if args.include:
        include_patterns.extend(args.include)

    if args.exclude:
        exclude_patterns.extend(args.exclude)

    # Compile patterns
    include_compiled = compile_patterns(include_patterns) if include_patterns else []
    exclude_compiled = compile_patterns(exclude_patterns) if exclude_patterns else []

    # Get log file path
    log_path = LOGS[args.log]

    if not log_path.exists():
        print(colorize(f"Error: Log file not found: {log_path}", Colors.RED), file=sys.stderr)
        sys.exit(1)

    # Show what we're doing
    preset_info = f" (preset: {args.preset})" if args.preset else ""
    mode = "Following" if args.follow else "Analyzing"
    print(colorize(f"{mode} {log_path.name}{preset_info}", Colors.BOLD + Colors.CYAN))

    if include_patterns:
        print(colorize(f"Include: {', '.join(include_patterns[:5])}" +
                      (f" ... ({len(include_patterns) > 5 and f' ({len(include_patterns)} total)' or ''}"),
                      Colors.GREEN))
    if exclude_patterns:
        print(colorize(f"Exclude: {', '.join(exclude_patterns)}", Colors.YELLOW))
    print()

    # Execute
    if args.follow:
        lines = args.lines if args.lines else 10
        tail_file(log_path, include_compiled, exclude_compiled, lines)
    else:
        analyze_file(log_path, include_compiled, exclude_compiled, args.lines)


if __name__ == '__main__':
    main()
