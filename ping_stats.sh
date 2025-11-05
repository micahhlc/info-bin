#!/bin/bash

# A script to measure network stability by calculating latency percentiles (p50, p90, p95, p99).
# It requires a hostname and ping count, and displays a real-time progress bar.

# --- Step 1: Validate Input Parameters ---
if [ "$#" -ne 2 ]; then
    echo "Error: Incorrect number of arguments." >&2
    echo "Usage: $0 <hostname> <count>" >&2
    echo "Example: $0 www.rakuten.co.jp 100" >&2
    exit 1
fi

TARGET=$1
COUNT=$2

# Check if COUNT is a valid number >= 10 for meaningful stats.
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 10 ]; then
    echo "Error: Ping count must be a number greater than or equal to 10." >&2
    exit 1
fi

# --- Step 2: Setup and Execution ---
echo "--- Starting Network Stability Test ---"
echo "Target:   $TARGET"
echo "Pinging:  $COUNT times"
echo -n "Progress: " # -n prevents a newline, so dots appear on the same line.

# Create secure temporary files. The `trap` command ensures they are deleted
# even if the script is interrupted (e.g., with Ctrl+C).
LATENCY_FILE=$(mktemp)
PING_OUTPUT_FILE=$(mktemp)
trap 'rm -f "$LATENCY_FILE" "$PING_OUTPUT_FILE"' EXIT

# --- MODIFIED LINE BELOW ---
# Run ping and process its output in real-time. We removed 'stdbuf -oL'.
# 'tee' duplicates the output: one copy to our file, one copy to the 'while' loop.
ping -c "$COUNT" "$TARGET" | tee "$PING_OUTPUT_FILE" | while IFS= read -r line; do
    # Check if the line contains a successful ping response.
    if [[ "$line" == *"time="* ]]; then
        # If yes, print a progress dot.
        echo -n "."
        # And extract just the latency number into our data file.
        echo "$line" | awk -F'[= ]' '{print $(NF-1)}' >> "$LATENCY_FILE"
    fi
done

# After the loop finishes, print a newline to move to the next line for the summary.
echo " Done."
echo ""

# --- Step 3: Analysis and Reporting ---

# Get the standard summary from the captured output file.
echo "--- Standard Ping Summary ---"
tail -n 4 "$PING_OUTPUT_FILE"
echo "-----------------------------"

# Count how many successful pings we logged.
SUCCESS_COUNT=$(wc -l < "$LATENCY_FILE" | tr -d ' ')

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "No successful pings were recorded. Cannot calculate statistics."
    exit 1
fi

# Sort the latencies numerically for percentile calculation.
SORTED_LATENCIES=$(sort -n "$LATENCY_FILE")

# Function to calculate percentile.
calculate_percentile() {
    local list="$1"
    local count="$2"
    local percentile="$3"
    # Calculate the rank/index for the desired percentile.
    local index=$(awk -v c="$count" -v p="$percentile" 'BEGIN { printf "%.0f\n", c * p / 100.0 }')
    # Get the latency value at that specific line number.
    echo "$list" | sed -n "${index}p"
}

# Calculate the key percentiles.
P50=$(calculate_percentile "$SORTED_LATENCIES" "$SUCCESS_COUNT" 50)
P90=$(calculate_percentile "$SORTED_LATENCIES" "$SUCCESS_COUNT" 90)
P95=$(calculate_percentile "$SORTED_LATENCIES" "$SUCCESS_COUNT" 95)
P99=$(calculate_percentile "$SORTED_LATENCIES" "$SUCCESS_COUNT" 99)

echo "\n--- Enhanced Stability Analysis (Percentiles) ---"
printf "Median Latency (p50):      %8.3f ms   (50%% of pings were faster than this)\n" "$P50"
printf "90th Percentile (p90):     %8.3f ms   (90%% of pings were faster than this)\n" "$P90"
printf "95th Percentile (p95):     %8.3f ms   (95%% of pings were faster than this)\n" "$P95"
printf "99th Percentile (p99):     %8.3f ms   (99%% of pings were faster, ignoring the worst 1%%)\n" "$P99"
echo "-------------------------------------------------"
