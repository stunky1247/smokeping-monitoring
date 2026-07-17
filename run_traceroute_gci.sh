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

echo "Starting GCI Traceroute Loop..."
echo "Output path: ${TARGET_FILE}"

# Run in an infinite loop every hour
while true; do
    echo "[$(date)] Executing traceroute trace..."
    mkdir -p "$(dirname "${TARGET_FILE}")"
    "${WIN_TRACERT}" -d -h 15 clientsettings.roblox.com > "${TARGET_FILE}" 2>&1
    echo "[$(date)] Traceroute completed. Sleeping for 1 hour."
    sleep 3600
done
