#!/bin/bash

# Simple background loop to run GCI traceroute hourly on the remote laptop.
# This script executes Windows native tracert.exe via WSL interoperability to bypass Hyper-V NAT.

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET_FILE="${REPO_DIR}/smokeping/data/Roblox_TCP/traceroute_gci.txt"

# Locate tracert.exe dynamically
WIN_TRACERT=""
if [ -f "/mnt/c/Windows/System32/tracert.exe" ]; then
    WIN_TRACERT="/mnt/c/Windows/System32/tracert.exe"
elif [ -f "/c/Windows/System32/tracert.exe" ]; then
    WIN_TRACERT="/c/Windows/System32/tracert.exe"
elif command -v tracert.exe &>/dev/null; then
    WIN_TRACERT="tracert.exe"
fi

if [ -z "${WIN_TRACERT}" ]; then
    echo "Error: Windows tracert.exe could not be located in this WSL environment."
    echo "Make sure Windows interoperability is enabled and Windows drives are mounted."
    exit 1
fi

HISTORY_FILE="${REPO_DIR}/smokeping/data/Roblox_TCP/traceroute_gci_history.log"

echo "Starting GCI 5-Minute Traceroute Loop..."
echo "Output path: ${TARGET_FILE}"
echo "History path: ${HISTORY_FILE}"

# Run in an infinite loop every 5 minutes (300 seconds)
while true; do
    echo "[$(date)] Executing 5-minute MTR probe..."
    mkdir -p "$(dirname "${TARGET_FILE}")"
    
    # Run MTR (or tracert fallback) to temporary file
    TEMP_TRACE="${TARGET_FILE}.tmp"
    if command -v mtr &>/dev/null; then
        mtr --report --report-cycles 10 --no-dns edge-term4-sea1.roblox.com > "${TEMP_TRACE}" 2>&1
    elif [ -n "${WIN_TRACERT}" ]; then
        "${WIN_TRACERT}" -d -h 15 edge-term4-sea1.roblox.com > "${TEMP_TRACE}" 2>&1
    fi

    if [ -s "${TEMP_TRACE}" ]; then
        # Generic PII Sanitization: Rewrite MTR HOST headers to generic node label
        sed -i 's/^HOST: .*/HOST: GCI-Native-Node                 Loss%   Snt   Last   Avg  Best  Wrst StDev/' "${TEMP_TRACE}" 2>/dev/null
        mv "${TEMP_TRACE}" "${TARGET_FILE}"
        # Append timestamped entry to host history file
        echo "=== MTR Probe: $(date -u +'%Y-%m-%dT%H:%M:%SZ') ===" >> "${HISTORY_FILE}"
        cat "${TARGET_FILE}" >> "${HISTORY_FILE}"
        echo "" >> "${HISTORY_FILE}"
        
        # Keep history file trimmed to last ~5000 lines (~24 hours of data)
        tail -n 5000 "${HISTORY_FILE}" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "${HISTORY_FILE}"
    fi

    echo "[$(date)] Probe completed. Sleeping for 5 minutes (300s)..."
    sleep 300
done
