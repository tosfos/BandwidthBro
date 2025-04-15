#!/bin/bash

# Script to debug unstable internet connection
# Credit: Ike Hecht (tosfos on GitHub)

# Exit on unset variables and pipe failures, but NOT on command errors to prevent unexpected exits
set -uo pipefail
# Explicitly NOT using 'set -e' to prevent script from exiting on command failure

# CONFIGURATION - Can be overridden by environment variables or config file
CONFIG_FILE="${CONFIG_FILE:-/etc/bandwidth_bro.conf}"
LOGFILE="${LOGFILE:-${HOME}/bandwidth_bro.log}"
TEST_HOST="${TEST_HOST:-8.8.8.8}" # Google DNS for ping test
TEST_HOST2="${TEST_HOST2:-1.1.1.1}" # Cloudflare DNS as secondary test host
TEST_HOST3="${TEST_HOST3:-208.67.222.222}" # OpenDNS as tertiary test host
TEST_URL="${TEST_URL:-google.com}" # For DNS and HTTP tests
PING_COUNT="${PING_COUNT:-10}"
INTERVAL="${INTERVAL:-5}" # Seconds between tests
SPEED_TEST_INTERVAL="${SPEED_TEST_INTERVAL:-3}" # Minutes between speed tests
TRACEROUTE_INTERVAL="${TRACEROUTE_INTERVAL:-5}" # Minutes between traceroute tests
ALTERNATE_DNS="${ALTERNATE_DNS:-1.1.1.1}" # Cloudflare DNS for comparison
DEBUG_MODE="${DEBUG_MODE:-false}" # Set to true for debug output

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global variables
SPEEDTEST_AVAILABLE=false
TIMESTAMP_START=$(date '+%Y-%m-%d %H:%M:%S')
ERROR_COUNT=0

# Function to log messages with consistent formatting
log() {
    local CURRENT_TIME
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CURRENT_TIME}: $1" | tee -a "${LOGFILE}" 2>/dev/null || echo "${CURRENT_TIME}: $1"
}

# Function to log with color for terminal visibility
log_color() {
    local CURRENT_TIME
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${2}${CURRENT_TIME}: $1${NC}" | tee -a "${LOGFILE}" 2>/dev/null || echo "${CURRENT_TIME}: $1"
}

# Function to log errors and track them without exiting
log_error() {
    local CURRENT_TIME
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    ((ERROR_COUNT++))
    echo -e "${RED}${CURRENT_TIME}: ERROR (${ERROR_COUNT}): $1${NC}" | tee -a "${LOGFILE}" 2>/dev/null || echo "${CURRENT_TIME}: ERROR (${ERROR_COUNT}): $1"
}

# Debug logging function - only outputs if DEBUG_MODE is true
debug_log() {
    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "[DEBUG] $1"
    fi
}

# Load configuration from file if it exists
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        debug_log "Loading configuration from ${CONFIG_FILE}"
        source "${CONFIG_FILE}" 2>/dev/null || log_color "Warning: Could not load config file ${CONFIG_FILE}, continuing with default settings" "${YELLOW}"
    fi
}

# Validate configuration values
validate_config() {
    if ! [[ "${PING_COUNT}" =~ ^[0-9]+$ ]] || [[ "${PING_COUNT}" -lt 1 ]]; then
        log_color "Error: PING_COUNT must be a positive integer, resetting to 10" "${RED}"
        PING_COUNT=10
    fi
    if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || [[ "${INTERVAL}" -lt 1 ]]; then
        log_color "Error: INTERVAL must be a positive integer, resetting to 5" "${RED}"
        INTERVAL=5
    fi
    if ! [[ "${SPEED_TEST_INTERVAL}" =~ ^[0-9]+$ ]] || [[ "${SPEED_TEST_INTERVAL}" -lt 1 ]]; then
        log_color "Error: SPEED_TEST_INTERVAL must be a positive integer, resetting to 3" "${RED}"
        SPEED_TEST_INTERVAL=3
    fi
    if ! [[ "${TRACEROUTE_INTERVAL}" =~ ^[0-9]+$ ]] || [[ "${TRACEROUTE_INTERVAL}" -lt 1 ]]; then
        log_color "Error: TRACEROUTE_INTERVAL must be a positive integer, resetting to 5" "${RED}"
        TRACEROUTE_INTERVAL=5
    fi
}

# Initialize script - create log file directory if needed
initialize() {
    local log_dir
    log_dir=$(dirname "${LOGFILE}")
    if [[ ! -d "${log_dir}" ]]; then
        if ! mkdir -p "${log_dir}" 2>/dev/null; then
            log_color "Warning: Could not create log directory ${log_dir}. Try running with sudo if this is a permissions issue. Will attempt to log to console only." "${YELLOW}"
            LOGFILE="/dev/stdout"
        fi
    fi
    if [[ ! -w "${log_dir}" ]]; then
        log_color "Warning: Log directory ${log_dir} is not writable. Try running with sudo if this is a permissions issue. Will attempt to log to console only." "${YELLOW}"
        LOGFILE="/dev/stdout"
    fi
    log_color "Internet Debug Script started at ${TIMESTAMP_START}" "${GREEN}"
    log "Logging to ${LOGFILE}"
    log_color "Note: Some diagnostics require root privileges. Run with 'sudo' for complete results if you encounter permission issues. Script will continue with available tests." "${YELLOW}"
}

# Test internet speed using speedtest-cli if available, otherwise fallback
test_speed() {
    log "Testing internet speed..."
    if ${SPEEDTEST_AVAILABLE}; then
        debug_log "Using speedtest-cli for speed test"
        if ! SPEED_RESULT=$(speedtest-cli --simple 2>&1); then
            log_color "Speed test failed: ${SPEED_RESULT}" "${RED}"
            return 1
        fi
        log_color "Speed test results:\n${SPEED_RESULT}" "${GREEN}"
    else
        debug_log "Falling back to curl-based speed test"
        # Fallback to simple download test
        if ! SPEED_RESULT=$(curl -s -w '%{speed_download} bytes/sec\n' -o /dev/null http://speedtest.wdc01.softlayer.com/downloads/test100.zip 2>&1); then
            log_color "Speed test (fallback) failed: ${SPEED_RESULT}" "${RED}"
            return 1
        fi
        log "Speed test (fallback) results: ${SPEED_RESULT}"
    fi
    return 0
}

# Check WiFi signal strength and quality
check_wifi_signal() {
    debug_log "Checking WiFi signal strength"
    if ! command -v iwconfig &> /dev/null; then
        log "iwconfig not available, cannot check WiFi signal"
        return 1
    fi

    local WIFI_INTERFACE WIFI_INFO WIFI_SIGNAL WIFI_FREQ WIFI_CHANNEL QUALITY
    WIFI_INTERFACE=$(iwconfig 2>/dev/null | grep -oP '^\S+' | head -1 || echo "")
    if [[ -z "${WIFI_INTERFACE}" ]]; then
        log "No WiFi interface found"
        return 1
    fi

    WIFI_INFO=$(iwconfig "${WIFI_INTERFACE}" 2>/dev/null | grep -i "signal level" || echo "")
    WIFI_SIGNAL=$(echo "${WIFI_INFO}" | grep -oP 'Signal level=\K[-0-9]+' || echo "")
    WIFI_FREQ=$(iwconfig "${WIFI_INTERFACE}" 2>/dev/null | grep -oP 'Frequency:\K[0-9.]+' || echo "N/A")
    WIFI_CHANNEL=$(iwconfig "${WIFI_INTERFACE}" 2>/dev/null | grep -oP 'Access Point: \K\S+' | xargs -I {} iwlist {} channel 2>/dev/null | grep -oP 'Current Frequency:[0-9.]+ GHz \(Channel \K\d+\)' || echo "N/A")

    if [[ -z "${WIFI_SIGNAL}" ]]; then
        log "WiFi Signal: Unable to determine signal strength"
        return 1
    fi

    # Convert signal level to quality percentage (assuming -100 is 0% and -50 is 100%)
    if [[ "${WIFI_SIGNAL}" -ge -50 ]]; then
        QUALITY=100
    elif [[ "${WIFI_SIGNAL}" -le -100 ]]; then
        QUALITY=0
    else
        QUALITY=$((2 * (WIFI_SIGNAL + 100)))
    fi

    if [[ "${QUALITY}" -ge 70 ]]; then
        log_color "WiFi Signal: ${WIFI_INFO} (Quality: ${QUALITY}%, Freq: ${WIFI_FREQ} GHz, Channel: ${WIFI_CHANNEL})" "${GREEN}"
    elif [[ "${QUALITY}" -ge 40 ]]; then
        log_color "WiFi Signal: ${WIFI_INFO} (Quality: ${QUALITY}%, Freq: ${WIFI_FREQ} GHz, Channel: ${WIFI_CHANNEL})" "${YELLOW}"
    else
        log_color "WiFi Signal: ${WIFI_INFO} (Quality: ${QUALITY}%, Freq: ${WIFI_FREQ} GHz, Channel: ${WIFI_CHANNEL})" "${RED}"
    fi
    return 0
}

# Perform traceroute to test URL
test_traceroute() {
    debug_log "Performing traceroute to ${TEST_URL}"
    if ! command -v traceroute &> /dev/null; then
        log "Traceroute not available, skipping test"
        return 1
    fi

    local TRACEROUTE_RESULT
    log "Running traceroute to ${TEST_URL}..."
    if ! TRACEROUTE_RESULT=$(traceroute -n -m 10 "${TEST_URL}" 2>&1 | tail -n +2); then
        log_color "Traceroute failed: ${TRACEROUTE_RESULT}" "${RED}"
        return 1
    fi
    log "Traceroute results:\n${TRACEROUTE_RESULT}"
    return 0
}

# Test current bandwidth usage
test_bandwidth() {
    debug_log "Checking bandwidth usage"
    if ! command -v netstat &> /dev/null; then
        log "netstat not available, cannot check bandwidth usage"
        return 1
    fi

    local PREV_RX=0 PREV_TX=0 PREV_TIME CURRENT_RX CURRENT_TX CURRENT_TIME TIME_DIFF RX_DIFF TX_DIFF RX_SPEED TX_SPEED
    log "Checking current bandwidth usage..."
    # Check if we have a previous reading
    if [[ -f "/tmp/bandwidth_prev" ]]; then
        read -r PREV_RX PREV_TX < /tmp/bandwidth_prev
        PREV_TIME=$(stat -c %Y /tmp/bandwidth_prev 2>/dev/null || stat -f %m /tmp/bandwidth_prev 2>/dev/null)
    else
        PREV_RX=0
        PREV_TX=0
        PREV_TIME=$(date +%s)
    fi

    # Get current bytes in/out - handle different /proc/net/dev formats
    CURRENT_RX=$(awk '/wlan|eth|enp|wlp/ {sum += $2} END {print sum}' /proc/net/dev)
    CURRENT_TX=$(awk '/wlan|eth|enp|wlp/ {sum += $10} END {print sum}' /proc/net/dev)
    CURRENT_TIME=$(date +%s)

    # Calculate difference and speed
    TIME_DIFF=$((CURRENT_TIME - PREV_TIME))
    if [[ "${TIME_DIFF}" -gt 0 ]]; then
        # Check if we have valid numbers before calculation
        if [[ -z "${CURRENT_RX}" || -z "${PREV_RX}" || -z "${CURRENT_TX}" || -z "${PREV_TX}" ]]; then
            log "Bandwidth usage: Unable to calculate - invalid data from network statistics"
        else
            # Use bc for floating point arithmetic to handle large numbers
            RX_DIFF=$(echo "${CURRENT_RX} - ${PREV_RX}" | bc 2>/dev/null || echo "0")
            TX_DIFF=$(echo "${CURRENT_TX} - ${PREV_TX}" | bc 2>/dev/null || echo "0")
            RX_SPEED=$(echo "scale=2; ${RX_DIFF} / ${TIME_DIFF} / 1024" | bc 2>/dev/null || echo "0.00")
            TX_SPEED=$(echo "scale=2; ${TX_DIFF} / ${TIME_DIFF} / 1024" | bc 2>/dev/null || echo "0.00")

            log "Bandwidth usage: Download ${RX_SPEED} KB/s, Upload ${TX_SPEED} KB/s"
        fi
    else
        log "Bandwidth usage: Time difference too small to calculate speed"
    fi

    # Store current values for next check, only if they're valid
    if [[ -n "${CURRENT_RX}" && -n "${CURRENT_TX}" ]]; then
        echo "${CURRENT_RX} ${CURRENT_TX}" > /tmp/bandwidth_prev
    fi
    return 0
}

# Test DNS resolution with alternate server
test_alternate_dns() {
    debug_log "Testing alternate DNS server ${ALTERNATE_DNS}"
    local DNS_START DNS_RESULT DNS_END DNS_TIME
    log "Testing DNS resolution with alternate server ${ALTERNATE_DNS}..."
    DNS_START=$(date +%s.%N)
    DNS_RESULT=$(dig "@${ALTERNATE_DNS}" +short +timeout=5 "${TEST_URL}" 2>&1 || echo "")
    DNS_END=$(date +%s.%N)
    DNS_TIME=$(echo "${DNS_END} - ${DNS_START}" | bc)
    if [[ -n "${DNS_RESULT}" ]]; then
        log_color "Alternate DNS resolved in ${DNS_TIME}s: ${DNS_RESULT}" "${GREEN}"
    else
        log_color "Alternate DNS resolution failed for ${TEST_URL} in ${DNS_TIME}s" "${RED}"
    fi
    return 0
}

# Test DNS server availability
test_dns_server() {
    debug_log "Testing DNS server availability"
    local DNS_SERVER DNS_PING DNS_LOSS
    log "Testing DNS server availability..."
    DNS_SERVER=$(grep -m 1 nameserver /etc/resolv.conf | awk '{print $2}' || echo "")
    if [[ -n "${DNS_SERVER}" ]]; then
        if ! DNS_PING=$(ping -c 3 "${DNS_SERVER}" 2>&1); then
            log_color "DNS server (${DNS_SERVER}) ping failed: ${DNS_PING}" "${RED}"
            return 1
        fi
        DNS_LOSS=$(echo "${DNS_PING}" | grep -oP '\d+% packet loss' || echo "N/A")
        if [[ "${DNS_LOSS}" == "0% packet loss" ]]; then
            log_color "DNS server (${DNS_SERVER}) reachable - ${DNS_LOSS}" "${GREEN}"
        else
            log_color "DNS server (${DNS_SERVER}) ping issues: ${DNS_LOSS}" "${RED}"
        fi
    else
        log_color "No DNS server found in configuration" "${RED}"
    fi
    return 0
}

# Test for MTU issues with different packet sizes
test_mtu_issues() {
    debug_log "Testing for MTU issues"
    local size MTU_RESULT MTU_LOSS
    log "Testing for MTU issues with different packet sizes to ${TEST_HOST}..."
    for size in 1472 1400 1300 1200; do
        log "Trying packet size ${size}..."
        if ! MTU_RESULT=$(ping -s "${size}" -M do -c 3 "${TEST_HOST}" 2>&1); then
            log_color "MTU test failed at size ${size}: ${MTU_RESULT}" "${RED}"
            continue
        fi
        MTU_LOSS=$(echo "${MTU_RESULT}" | grep -oP '\d+% packet loss' || echo "N/A")
        if [[ "${MTU_LOSS}" == "0% packet loss" ]]; then
            log_color "MTU test: Size ${size} successful - ${MTU_LOSS}" "${GREEN}"
        else
            log_color "MTU test: Packet loss at size ${size} - ${MTU_LOSS} - possible MTU issue" "${RED}"
        fi
        sleep 1
    done
    return 0
}

# Check system logs for router status messages
check_router_status() {
    debug_log "Checking router status messages"
    local ROUTER_MESSAGES
    log "Checking for router status messages..."
    # Check dmesg for network-related messages (requires sudo for full access, may be limited)
    if ! ROUTER_MESSAGES=$(dmesg | grep -i 'wlan\|wifi\|network\|dhcp\|internet' | tail -n 5 2>/dev/null); then
        log_color "Unable to access system messages (may require sudo). Run script with 'sudo' for full system diagnostics. Continuing with other tests..." "${YELLOW}"
        return 1
    fi
    if [[ -n "${ROUTER_MESSAGES}" ]]; then
        log "Recent system messages about network:\n${ROUTER_MESSAGES}"
    else
        log "No recent network-related system messages found"
    fi
    return 0
}

# Test ping with specific packet size and measure timing
test_ping_with_size() {
    local host="$1"
    local size="$2"
    local START_TIME PING_RESULT END_TIME TIME_TAKEN PACKET_LOSS LATENCY
    debug_log "Testing ping to ${host} with size ${size}"
    log "Running ping test to ${host} with packet size ${size}..."
    START_TIME=$(date +%s.%N)
    PING_RESULT=$(ping -s "${size}" -c "${PING_COUNT}" "${host}" 2>&1) || true
    END_TIME=$(date +%s.%N)
    TIME_TAKEN=$(echo "${END_TIME} - ${START_TIME}" | bc)
    if echo "${PING_RESULT}" | grep -q "packets transmitted"; then
        PACKET_LOSS=$(echo "${PING_RESULT}" | grep -oP '\d+% packet loss' || echo "N/A")
        LATENCY=$(echo "${PING_RESULT}" | grep -oP 'rtt min/avg/max/mdev = [\d.\/]+' | cut -d'=' -f2 || echo "N/A")
        if [[ "${PACKET_LOSS}" == "0% packet loss" ]]; then
            log_color "Ping result (${host}, size ${size}): ${PACKET_LOSS}, Latency: ${LATENCY} ms, Time: ${TIME_TAKEN}s" "${GREEN}"
        else
            log_color "Ping result (${host}, size ${size}): ${PACKET_LOSS}, Latency: ${LATENCY} ms, Time: ${TIME_TAKEN}s" "${RED}"
        fi
    else
        log_color "Ping failed (${host}, size ${size}): ${PING_RESULT}, Time: ${TIME_TAKEN}s" "${RED}"
    fi
    return 0
}

# Test connectivity to first hop beyond gateway
test_first_hop_beyond_gateway() {
    debug_log "Testing first hop beyond gateway"
    local GATEWAY FIRST_HOP HOP_PING HOP_LOSS
    log "Attempting to identify and test first hop beyond gateway..."
    GATEWAY=$(ip route | grep default | awk '{print $3}' || echo "")
    if [[ -n "${GATEWAY}" ]]; then
        # Try to get the first hop from traceroute to a common host
        FIRST_HOP=$(traceroute -n -m 2 "${TEST_HOST}" 2>/dev/null | tail -n 1 | awk '{print $2}' | grep -v '*' | grep -v "${GATEWAY}" || echo "")
        if [[ -n "${FIRST_HOP}" && "${FIRST_HOP}" != "${GATEWAY}" ]]; then
            log "First hop beyond gateway identified as ${FIRST_HOP}, testing..."
            if ! HOP_PING=$(ping -c 5 "${FIRST_HOP}" 2>&1); then
                log_color "First hop (${FIRST_HOP}) ping failed: ${HOP_PING}" "${RED}"
                return 1
            fi
            HOP_LOSS=$(echo "${HOP_PING}" | grep -oP '\d+% packet loss' || echo "N/A")
            if [[ "${HOP_LOSS}" == "0% packet loss" ]]; then
                log_color "First hop (${FIRST_HOP}) reachable - ${HOP_LOSS}" "${GREEN}"
            else
                log_color "First hop (${FIRST_HOP}) ping issues: ${HOP_LOSS}" "${RED}"
            fi
        else
            log "Could not identify first hop beyond gateway"
        fi
    else
        log "No gateway found, cannot test first hop"
    fi
    return 0
}

# Check if required tools are installed
check_tools() {
    debug_log "Checking for required tools"
    local cmd missing_tools=()
    for cmd in ping curl dig iwconfig traceroute netstat; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_color "Warning: ${cmd} is not installed. Some tests will be skipped. Install it for full diagnostics." "${YELLOW}"
            log_color "See README.md for installation instructions." "${YELLOW}"
            missing_tools+=("${cmd}")
        fi
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_color "Script will continue with limited functionality. Install missing tools or run with sudo if permissions are the issue." "${YELLOW}"
    fi

    # Check for speedtest-cli if available
    if command -v speedtest-cli &> /dev/null; then
        SPEEDTEST_AVAILABLE=true
        debug_log "speedtest-cli found"
    else
        log "speedtest-cli not found, falling back to basic download test"
        debug_log "speedtest-cli not found, using fallback"
    fi
    return 0
}

# Log current DNS configuration
log_dns_config() {
    debug_log "Logging DNS configuration"
    local DNS_CONFIG
    log "Current DNS configuration:"
    DNS_CONFIG=$(grep nameserver /etc/resolv.conf 2>/dev/null || echo 'No nameserver found')
    log "${DNS_CONFIG}"
    return 0
}

# Check if current time matches a condition for periodic tests
check_time_condition() {
    local format="$1"  # Format for date command (%M for minutes, %S for seconds)
    local condition="$2"  # Condition to check (e.g., "< 30" or "% 2 == 0")
    local value

    value=$(date "+$format")
    if [[ "$condition" == *"%"* ]]; then
        # Handle modulo operations
        local modulo_result=$(echo "$condition" | cut -d' ' -f2)
        if (( 10#$value % $modulo_result == 0 )); then
            return 0  # True, condition met
        fi
    else
        # Handle less than comparisons
        local threshold=$(echo "$condition" | cut -d' ' -f2)
        if (( 10#$value < $threshold )); then
            return 0  # True, condition met
        fi
    fi
    return 1  # False, condition not met
}

# Main test loop
main_loop() {
    debug_log "Starting main test loop"
    local TIMESTAMP GATEWAY IFACE_STATUS HTTP_STATUS DNS_START DNS_RESULT DNS_END DNS_TIME
    # Run tests in a loop (Ctrl+C to stop)
    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # Test 1: Ping test for packet loss and latency to primary host with different packet sizes
        test_ping_with_size "${TEST_HOST}" 56
        test_ping_with_size "${TEST_HOST}" 512

        # Test 1b: Ping test to secondary host with different packet sizes
        test_ping_with_size "${TEST_HOST2}" 56
        test_ping_with_size "${TEST_HOST2}" 512

        # Test 1c: Ping test to tertiary host with different packet sizes
        test_ping_with_size "${TEST_HOST3}" 56
        test_ping_with_size "${TEST_HOST3}" 512

        # Test 2: DNS resolution and response time
        log "Testing DNS resolution for ${TEST_URL}..."
        DNS_START=$(date +%s.%N)
        DNS_RESULT=$(dig +short +timeout=5 "${TEST_URL}" 2>&1 || echo "")
        DNS_END=$(date +%s.%N)
        DNS_TIME=$(echo "${DNS_END} - ${DNS_START}" | bc)
        if [[ -n "${DNS_RESULT}" ]]; then
            log_color "DNS resolved in ${DNS_TIME}s: ${DNS_RESULT}" "${GREEN}"
        else
            log_color "DNS resolution failed for ${TEST_URL} in ${DNS_TIME}s" "${RED}"
        fi

        # Test 2b: Alternate DNS server test (every minute for comparison)
        if check_time_condition "%S" "< 30"; then
            test_alternate_dns
        fi

        # Test 2c: DNS server availability test
        test_dns_server

        # Test 3: HTTP connection
        log "Testing HTTP connection to ${TEST_URL}..."
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${TEST_URL}" 2>&1 || echo "000")
        if [[ "${HTTP_STATUS}" -eq 200 || "${HTTP_STATUS}" -eq 301 || "${HTTP_STATUS}" -eq 302 ]]; then
            log_color "HTTP connection successful: Status ${HTTP_STATUS}" "${GREEN}"
        else
            log_color "HTTP connection failed: Status ${HTTP_STATUS}" "${RED}"
        fi

        # Test 4: Check network interface status
        log "Checking network interface status..."
        IFACE_STATUS=$(ip link show | grep 'state UP' || echo "No active interfaces")
        if [[ "${IFACE_STATUS}" != "No active interfaces" ]]; then
            log_color "Active interfaces: ${IFACE_STATUS}" "${GREEN}"
        else
            log_color "Active interfaces: ${IFACE_STATUS}" "${RED}"
        fi

        # Test 5: Check gateway connectivity
        GATEWAY=$(ip route | grep default | awk '{print $3}' || echo "")
        if [[ -n "${GATEWAY}" ]]; then
            log "Testing gateway ${GATEWAY}..."
            if GATEWAY_PING=$(ping -c 3 "${GATEWAY}" 2>&1); then
                GATEWAY_LOSS=$(echo "${GATEWAY_PING}" | grep -oP '\d+% packet loss' || echo "N/A")
                if [[ "${GATEWAY_LOSS}" == "0% packet loss" ]]; then
                    log_color "Gateway reachable - ${GATEWAY_LOSS}" "${GREEN}"
                else
                    log_color "Gateway ping issues: ${GATEWAY_LOSS}" "${RED}"
                fi
            else
                log_color "Gateway ping failed: ${GATEWAY_PING}" "${RED}"
            fi
        else
            log_color "No default gateway found" "${RED}"
        fi

        # Test 6: Check first hop beyond gateway (every minute)
        if check_time_condition "%S" "< 30"; then
            test_first_hop_beyond_gateway
        fi

        # Test 7: Check WiFi signal strength
        check_wifi_signal

        # Test 8: Check router status messages (every minute)
        if check_time_condition "%S" "< 30"; then
            check_router_status
        fi

        # Test 9: Test for MTU issues (every 2 minutes)
        if check_time_condition "%M" "% 2 == 0"; then
            test_mtu_issues
        fi

        # Test 10: Speed test (runs every SPEED_TEST_INTERVAL minutes)
        if check_time_condition "%M" "% $SPEED_TEST_INTERVAL == 0"; then
            test_speed
        fi

        # Test 11: Traceroute (runs every TRACEROUTE_INTERVAL minutes)
        if check_time_condition "%M" "% $TRACEROUTE_INTERVAL == 0"; then
            test_traceroute
        fi

        # Test 12: Current bandwidth usage
        test_bandwidth

        log "--------------------------------"
        sleep "${INTERVAL}"
    done
}

# Main execution
main() {
    load_config
    validate_config
    initialize
    check_tools
    log_dns_config
    main_loop
}

# Trap Ctrl+C and exit gracefully
trap 'log_color "Script interrupted by user. Exiting..." "${YELLOW}"; exit 0' INT

# Run main
main
