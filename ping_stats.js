#!/Users/micah.cheng/.nvm/versions/node/v22.21.0/bin/node
// #!/usr/bin/env node

// Import the 'spawn' function from the built-in 'child_process' module.
// 'spawn' is used to run external commands and stream their input/output.
const { spawn } = require('child_process');

// --- Step 1: Set Default and User-Provided Parameters ---
const DEFAULT_TARGET = 'www.rakuten.co.jp';
const DEFAULT_COUNT = 20;

// process.argv contains command-line arguments.
// [0] is the node executable, [1] is the script path.
// Real arguments start at index [2].
const args = process.argv.slice(2);
const target = args[0] || DEFAULT_TARGET;
const count = parseInt(args[1] || DEFAULT_COUNT, 10);

// Check if count is a valid number >= 10.
// isNaN() checks if a value is "Not-a-Number".
if (isNaN(count) || count < 10) {
  console.error('Error: Ping count must be a number greater than or equal to 10.');
  process.exit(1); // Exit with an error code.
}

// --- Step 2: Setup and Execution ---
console.log('--- Starting Network Stability Test ---');
console.log(`Target:   ${target}`);
console.log(`Pinging:  ${count} times`);
process.stdout.write('Progress: '); // Use process.stdout.write to avoid a newline.

// We will store latencies in memory in this array, instead of a temp file.
const latencies = [];
let pingSummary = []; // To store the last few lines of output.

// Use spawn to run the 'ping' command. Arguments are passed as an array.
const pingProcess = spawn('ping', ['-c', count, target]);

// Listen for data coming from the command's standard output (stdout).
// This is the event-driven equivalent of the `| while read -r line` loop.
pingProcess.stdout.on('data', (data) => {
  // The 'data' object is a Buffer, so we convert it to a string.
  const output = data.toString();

  // Store the last 4 lines for the summary at the end.
  pingSummary = pingSummary.concat(output.trim().split('\n')).slice(-4);

  // Use a regular expression to find lines with latency info.
  // This is more robust than splitting by spaces/equals signs.
  const match = output.match(/time=([\d.]+)\s*ms/);

  if (match && match[1]) {
    // If a match is found, match[1] contains the captured number.
    const latency = parseFloat(match[1]);
    latencies.push(latency);
    process.stdout.write('.'); // Print progress dot.
  }
});

// Listen for any errors from the command.
pingProcess.stderr.on('data', (data) => {
  console.error(`\nPing Error: ${data.toString()}`);
});

// Listen for when the child process closes. This is where we do the analysis.
// The 'close' event fires after the command has finished completely.
pingProcess.on('close', (code) => {
  console.log(' Done.\n');

  // --- Step 3: Analysis and Reporting ---
  console.log('--- Standard Ping Summary ---');
  console.log(pingSummary.join('\n'));
  console.log('-----------------------------');

  if (latencies.length === 0) {
    console.log('No successful pings were recorded. Cannot calculate statistics.');
    process.exit(1);
  }

  // Sort the latencies numerically. The callback (a, b) => a - b is crucial for numeric sorting.
  latencies.sort((a, b) => a - b);

  // Function to calculate percentile from a sorted array.
  const calculatePercentile = (sortedArray, percentile) => {
    // Calculate the index for the desired percentile.
    // We use Math.ceil to round up and -1 for zero-based array indexing.
    const index = Math.ceil((percentile / 100.0) * sortedArray.length) - 1;
    return sortedArray[index];
  };

  const p50 = calculatePercentile(latencies, 50);
  const p90 = calculatePercentile(latencies, 90);
  const p95 = calculatePercentile(latencies, 95);
  const p99 = calculatePercentile(latencies, 99);

  console.log('\n--- Enhanced Stability Analysis (Percentiles) ---');
  // Using template literals and toFixed() for clean, formatted output.
  console.log(`Median Latency (p50):      ${p50.toFixed(3).padStart(8)} ms   (50% of pings were faster than this)`);
  console.log(`90th Percentile (p90):     ${p90.toFixed(3).padStart(8)} ms   (90% of pings were faster than this)`);
  console.log(`95th Percentile (p95):     ${p95.toFixed(3).padStart(8)} ms   (95% of pings were faster than this)`);
  console.log(
    `99th Percentile (p99):     ${p99.toFixed(3).padStart(8)} ms   (99% of pings were faster, ignoring the worst 1%)`
  );
  console.log('-------------------------------------------------');
});
