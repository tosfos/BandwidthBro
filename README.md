# README for Bandwidth Bro

## Overview

**Bandwidth Bro** is a comprehensive Bash script designed to diagnose and monitor internet connectivity issues. It performs a variety of tests to assess network performance, including ping tests, DNS resolution, HTTP connection checks, speed tests, and more. The script is highly configurable and logs detailed results for analysis.

## Features

- **Ping Tests**: Measures packet loss and latency to multiple hosts with different packet sizes.
- **DNS Resolution**: Tests DNS resolution speed and reliability, including alternate DNS servers.
- **HTTP Connection**: Checks the ability to connect to a specified URL.
- **Network Interface Status**: Reports on the status of network interfaces.
- **Gateway Connectivity**: Tests connectivity to the default gateway.
- **First Hop Beyond Gateway**: Identifies and tests connectivity to the first hop beyond the gateway.
- **WiFi Signal Strength**: Measures WiFi signal strength and quality.
- **Router Status Messages**: Checks system logs for network-related messages.
- **MTU Issues**: Tests for Maximum Transmission Unit (MTU) issues with different packet sizes.
- **Speed Tests**: Performs internet speed tests using `speedtest-cli` if available, or falls back to a curl-based test.
- **Traceroute**: Runs traceroute to analyze the path to a specified host.
- **Bandwidth Usage**: Monitors current bandwidth usage on network interfaces.

## Installation

1. **Download the Script**:
   ```bash
   wget https://raw.githubusercontent.com/tosfos/BandwidthBro/main/bandwidth_bro.sh -O bandwidth_bro.sh
   ```

2. **Make the Script Executable**:
   ```bash
   chmod +x bandwidth_bro.sh
   ```

3. **Install Required Tools**:
   Ensure the following tools are installed on your system:
   - `ping`
   - `curl`
   - `dig`
   - `iwconfig`
   - `traceroute`
   - `netstat`
   - `speedtest-cli` (optional, for more accurate speed tests)

   On Debian/Ubuntu systems, you can install these tools with:
   ```bash
   sudo apt-get update
   sudo apt-get install -y iputils-ping curl dnsutils wireless-tools traceroute net-tools speedtest-cli
   ```

   On Red Hat/CentOS systems:
   ```bash
   sudo yum install -y iputils curl bind-utils wireless-tools traceroute net-tools speedtest-cli
   ```

## Usage

Run the script with default settings:
```bash
./bandwidth_bro.sh
```

The script will continuously run tests at specified intervals until interrupted with `Ctrl+C`. Results are logged to a file (default: `~/internet_debug.log`) and displayed in the terminal with color-coded output for easy reading.

### Configuration

You can customize the script's behavior by setting environment variables or creating a configuration file at `/etc/bandwidth_bro.conf`. The following variables can be configured:

- `CONFIG_FILE`: Path to the configuration file (default: `/etc/bandwidth_bro.conf`).
- `LOGFILE`: Path to the log file (default: `~/internet_debug.log`).
- `TEST_HOST`, `TEST_HOST2`, `TEST_HOST3`: IP addresses for ping tests (default: `8.8.8.8`, `1.1.1.1`, `208.67.222.222`).
- `TEST_URL`: URL for DNS and HTTP tests (default: `google.com`).
- `PING_COUNT`: Number of pings per test (default: `10`).
- `INTERVAL`: Seconds between test cycles (default: `5`).
- `SPEED_TEST_INTERVAL`: Minutes between speed tests (default: `3`).
- `TRACEROUTE_INTERVAL`: Minutes between traceroute tests (default: `5`).
- `ALTERNATE_DNS`: Alternate DNS server for comparison (default: `1.1.1.1`).
- `DEBUG_MODE`: Enable debug output (default: `false`).

Example configuration file (`/etc/bandwidth_bro.conf`):
```bash
LOGFILE="/var/log/bandwidth_bro.log"
TEST_HOST="8.8.4.4"
INTERVAL=10
DEBUG_MODE=true
```

### Logging

All test results are logged to the specified log file with timestamps. The log file is created if it doesn't exist, and the directory is created if necessary.

### Debug Mode

Set `DEBUG_MODE=true` to enable detailed debug output, which can help in troubleshooting the script itself.

## Troubleshooting

- **Missing Tools**: If any required tools are missing, the script will exit with an error message. Install the missing tools as described in the Installation section.
- **Permission Issues**: Some tests (like checking system logs) may require `sudo` privileges. Run the script with elevated permissions if needed.
- **Log File Access**: Ensure the script has write access to the log file directory.

## Contributing

If you have suggestions for improvements or bug fixes, please submit them as issues or pull requests on the project's repository (if applicable).

## License

This script is provided under the MIT License. See the script's comments or repository for full license details.
