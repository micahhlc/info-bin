#!/Users/micah.cheng/anaconda3/bin/python
## !/usr/bin/env python3

import subprocess #Runs external commands (like ping) from within the Python script.
import re #Finds patterns in text using "Regular Expressions" (used here to find time=...).
import sys #Interacts with the Python system itself (used for exiting the script and handling errors).
import numpy as np #A powerful math library for fast statistical calculations (mean, std dev, percentiles).
import argparse #Parses command-line arguments provided by the user (like the target and count).
import matplotlib.pyplot as plt #Creates graphs and plots from data.

def conduct_ping_test(target: str, count: int) -> list[float]:
    """
    Runs the ping command and extracts the latency values.
    
    Args:
        target: The hostname or IP to ping.
        count: The number of pings to send.
        
    Returns:
        A list of floats, where each float is a successful ping's latency in ms.
        Returns an empty list if no pings succeed.
    """
    print("--- Conducting Ping Test ---")
    print(f"Target: {target} ")
    print(f"Pinging: {count} times")
    print(f"Progress: ", end='', flush= True)

    ping_command = ["ping", "-c", str(count), target]
    latencies = []
    
    try:
        # We use subprocess.run to wait for the command to complete.
        # result = subprocess.run(ping_command, capture_output=True, text=True, check=False)

        # Popen runs the command asynchronously, giving you access to its output line-by-line.
        # for line in process.stdout: reads output in real-time.
        # Each time a line containing time= appears, it prints a . immediately.
        # flush=True forces Python to display the dot right away (no buffering).
        # After all pings, it waits for completion with process.wait().

        process = subprocess.Popen(ping_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        

        for line in process.stdout:
            line = line.strip()
            if "time=" in line:
                print(".", end="", flush=True)  # print one dot per successful ping
                match = re.search(r"time=([\d.]+)", line)
                if match:
                    latencies.append(float(match.group(1)))
        process.wait()
                
    except FileNotFoundError:
        print("Error: 'ping' command not found.", file=sys.stderr)
        sys.exit(1)
    print(f" Done.\n")
    # print(f"Ping test complete. {len(latencies)} successful pings recorded.")
    # print(latencies)
    return latencies


def analyze_ping_results(latencies: list[float]) -> dict:
    """
    Takes a list of latencies and computes detailed statistics.
    
    Args:
        latencies: A list of latency values.
        
    Returns:
        A dictionary containing all calculated statistics (min, max, avg, std, percentiles).
    """
    # print("--- Analyzing Ping Results ---")
    if not latencies:
        return {}

    # Use NumPy for efficient and easy statistical calculations.
    latencies_np = np.array(latencies)
    
    stats = {
        'min': np.min(latencies_np),
        'max': np.max(latencies_np),
        'avg': np.mean(latencies_np),
        'std': np.std(latencies_np),
        'p50': np.percentile(latencies_np, 50),
        'p90': np.percentile(latencies_np, 90),
        'p95': np.percentile(latencies_np, 95),
        'p99': np.percentile(latencies_np, 99),
    }
    # print("Analysis complete.")
    # print("\n\n")
    return stats


def print_report(analyzed_results: dict):
    """
    Prints the formatted statistical report to the console.
    """
    print("--- Standard Ping Summary ---")
    # print(f"round-trip min/avg/max/stddev = {analyzed_results['min']:.3f}/{analyzed_results['avg']:.3f}/{analyzed_results['max']:.3f}/{analyzed_results['std']:.3f} ms")
    print(f"min: {analyzed_results['min']:.3f}")
    print(f"avg: {analyzed_results['avg']:.3f}")
    print(f"max: {analyzed_results['max']:.3f}")
    print(f"stddev: {analyzed_results['std']:.3f}")
    
    print("\n")

    print("--- Enhanced Stability Analysis (Percentiles) ---")
    print(f"Median Latency (p50):      {analyzed_results['p50']:>8.3f} ms")
    print(f"95th Percentile (p95):     {analyzed_results['p95']:>8.3f} ms")
    print(f"99th Percentile (p99):     {analyzed_results['p99']:>8.3f} ms")
    print(f"One stddev:                 {analyzed_results['p50'] + analyzed_results['std']:>8.3f} ms")
    print(f"Two stddev:                 {analyzed_results['p50'] + (analyzed_results['std'] * 2):>8.3f} ms")
    print("\n")


def plot_graph(latencies: list[float], analyzed_results: dict, target: str, save_path: str = None):
    """
    Generates and displays/saves a plot of the latency results.
    
    Args:
        latencies: The raw list of latencies for the main plot line.
        analyzed_results: The dictionary of stats for plotting horizontal lines.
        target: The ping target hostname for the plot title.
        save_path: Optional path to save the file. If None, shows an interactive plot.
    """
    print("--- Generating Plot ---")
    
    fig, ax = plt.subplots(figsize=(12, 7))

    ax.plot(range(1, len(latencies) + 1), latencies, label='Ping Latency', color='royalblue', alpha=0.8, linewidth=1.5)

    ax.axhline(y=analyzed_results['avg'], color='green', linestyle='--', label=f"Average ({analyzed_results['avg']:.2f} ms)")
    ax.axhline(y=analyzed_results['p95'], color='orange', linestyle='--', label=f"p95 ({analyzed_results['p95']:.2f} ms)")
    ax.axhline(y=analyzed_results['p99'], color='red', linestyle='--', label=f"p99 ({analyzed_results['p99']:.2f} ms)")
    ax.axhline(y=analyzed_results['std'], color='gold', linestyle='--', label=f"stddev ({analyzed_results['std']:.2f} ms)")

    ax.set_title(f"Ping Latency Over Time for '{target}'", fontsize=16)
    ax.set_xlabel("Ping Number", fontsize=12)
    ax.set_ylabel("Latency (ms)", fontsize=12)
    ax.legend()
    ax.grid(True, linestyle=':', alpha=0.6)
    ax.set_ylim(bottom=0)
    ax.set_xlim(left=1)

    if save_path:
        plt.savefig(save_path, dpi=150)
        print(f"Plot saved successfully to '{save_path}'")
    else:
        print("Displaying interactive plot window...")
        plt.show()


# ==============================================================================
# Main Program Execution
# ==============================================================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Measure network stability with detailed statistics and optional plotting.")
    parser.add_argument("--target", "-t", default="www.rakuten.co.jp", help="The hostname or IP address to ping. Default= www.rakuten.co.jp")
    parser.add_argument("--count", "-c", default=20, type=int, help="The number of times to ping. Default= 20")
    parser.add_argument("--plot", action="store_true", help="Display an interactive plot of the results.")
    parser.add_argument("--save", metavar="FILENAME", help="Save the plot to a file (e.g., plot.png).")
    
    args = parser.parse_args()
    print(args)

    if args.count < 10:
        print("Error: Ping count must be at least 10 for meaningful statistics.", file=sys.stderr)
        sys.exit(1)

    # --- Main Program Flow ---
    # 1. Conduct the test to get raw data.
    ping_results = conduct_ping_test(args.target, args.count)

    if not ping_results:
        print("\nTest finished, but no data was collected. Exiting.", file=sys.stderr)
        sys.exit(1)

    # 2. Analyze the raw data to get statistics.
    analyzed_data = analyze_ping_results(ping_results)

    # 3. Print the text-based report.
    print_report(analyzed_data)

    # 4. Conditionally generate a plot.
    if args.plot or args.save:
        # Note: plot_graph needs both the raw results (for the line) and the analyzed data (for the averages).
        plot_graph(ping_results, analyzed_data, args.target, save_path=args.save)
        
    print("\n--- All tasks complete. ---")

