#!/bin/bash

# ==============================================================================
# ==============================================================================
# GCI ALASKA NETWORK TELEMETRY - IMAGE SYNCHRONIZATION SCRIPT
# ==============================================================================
# This script runs on Machine A (Desktop, VPN-enabled control).
# It periodically regenerates and downloads the local SmokePing chart,
# retrieves the remote GCI-native SmokePing chart from Machine B (Laptop),
# builds the metadata.json timestamp, commits all changes, and pushes to GitHub.
#
# Usage:
#   ./sync_charts.sh          # Runs as a continuous daemon on an hourly loop
#   ./sync_charts.sh --once   # Runs a single sync operation (best for cron)
# ==============================================================================

# Ensure standard system commands are in the path for headless cron/systemd execution
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- CONFIGURATION SETTINGS ---

# Local SmokePing (Machine A - Seattle VPN)
LOCAL_TARGET="Roblox_TCP.Core_API_TCP"
LOCAL_CHART_3H="Core_API_TCP_last_10800.png"
LOCAL_CHART_10D="Core_API_TCP_last_864000.png"
LOCAL_OUTPUT_3H="roblox_vpn_seattle_3h.png"
LOCAL_OUTPUT_10D="roblox_vpn_seattle_10d.png"
LOCAL_SMOKEPING_URL="http://localhost/smokeping"

# Remote Laptop (Machine B - Raw GCI Native)
# Choose pull method: "ssh" (SCP over network) or "http" (Fetch via local webserver)
LAPTOP_PULL_METHOD="http"

# Laptop SSH Settings (For pull method: "ssh")
LAPTOP_SSH_HOST="192.168.68.72"
LAPTOP_SSH_USER="YOURUSERNAMEHERE"
LAPTOP_SSH_KEY="" # Optional path (e.g., ~/.ssh/id_rsa), leave blank for default agent
LAPTOP_SSH_PATH_3H="/home/YOURUSERNAMEHERE/projects/smokeping-monitoring/roblox_gci_native_3h.png"
LAPTOP_SSH_PATH_10D="/home/YOURUSERNAMEHERE/projects/smokeping-monitoring/roblox_gci_native_10d.png"
LAPTOP_SSH_RRD_PATH="/home/YOURUSERNAMEHERE/projects/smokeping-monitoring/smokeping/data/Roblox_TCP/Core_API_TCP.rrd"

# Laptop HTTP Settings (For pull method: "http")
LAPTOP_HTTP_CGI="http://192.168.68.72/smokeping/smokeping.cgi"
LAPTOP_HTTP_IMAGE_3H="http://192.168.68.72/smokeping/cache/Roblox_TCP/Core_API_TCP_last_10800.png"
LAPTOP_HTTP_IMAGE_10D="http://192.168.68.72/smokeping/cache/Roblox_TCP/Core_API_TCP_last_864000.png"
LAPTOP_HTTP_RRD="http://192.168.68.72/smokeping/Core_API_TCP.rrd"

# General Config
REPO_DIR="/home/YOURUSERNAMEHERE/projects/smokeping-monitoring"
INTERVAL_SECONDS=3600

# ------------------------------------------------------------------------------

# Ensure we are inside the git repository
cd "${REPO_DIR}" || { echo "Error: Directory ${REPO_DIR} not found."; exit 1; }

sync_telemetry() {
    echo "=== Starting Telemetry Synchronization: $(date) ==="

    local sync_success=true
    local local_success=true
    local remote_success=true

    # 0. CHECK CONTAINER AND VOLUME MOUNTS SANITY
    echo "[Docker] Verifying that SmokePing container is running with custom configurations..."

    # Check if container is running at all
    if ! docker ps --format '{{.Names}}' | grep -q '^smokeping$'; then
        echo "[Docker] Warning: SmokePing container is not running. Starting container..."
        docker compose up -d
        sleep 5
    fi

    # Check if custom configs are mounted inside the container
    if ! docker exec smokeping [ -f /config/Targets ] 2>/dev/null; then
        echo "[Docker] Warning: Container volume mounts are broken or empty. Restarting container to remount..."
        docker compose down
        docker compose up -d
        sleep 5
    fi

    # 1. FORCE LOCAL REGENERATION & DOWNLOAD CHART
    echo "[Local Node] Requesting local SmokePing CGI to force graph regeneration..."
    curl -s -o /dev/null "${LOCAL_SMOKEPING_URL}/smokeping.cgi?target=${LOCAL_TARGET}"

    # Wait briefly for RRDtool to write the chart image
    sleep 2

    echo "[Local Node] Downloading local chart images..."
    curl -s -f -o "${REPO_DIR}/${LOCAL_OUTPUT_3H}" "${LOCAL_SMOKEPING_URL}/cache/Roblox_TCP/${LOCAL_CHART_3H}"
    curl -s -f -o "${REPO_DIR}/${LOCAL_OUTPUT_10D}" "${LOCAL_SMOKEPING_URL}/cache/Roblox_TCP/${LOCAL_CHART_10D}"

    if [ -s "${REPO_DIR}/${LOCAL_OUTPUT_3H}" ] && [ -s "${REPO_DIR}/${LOCAL_OUTPUT_10D}" ]; then
        echo "[Local Node] Successfully synchronized local charts (3h and 10d)."
    else
        echo "[Local Node] Error: Failed to retrieve local charts from cache."
        local_success=false
        sync_success=false
    fi

    # 2. PULL REMOTE LAPTOP CHARTS AND DATABASE (RAW GCI NATIVE)
    echo "[Remote Node] Retrieving remote charts using method: ${LAPTOP_PULL_METHOD}"

    if [ "${LAPTOP_PULL_METHOD}" = "ssh" ]; then
        local SCP_CMD="scp -B"
        if [ -n "${LAPTOP_SSH_KEY}" ]; then
            SCP_CMD="scp -B -i ${LAPTOP_SSH_KEY}"
        fi

        $SCP_CMD "${LAPTOP_SSH_USER}@${LAPTOP_SSH_HOST}:${LAPTOP_SSH_PATH_3H}" "${REPO_DIR}/roblox_gci_native_3h.png" 2>/dev/null
        $SCP_CMD "${LAPTOP_SSH_USER}@${LAPTOP_SSH_HOST}:${LAPTOP_SSH_PATH_10D}" "${REPO_DIR}/roblox_gci_native_10d.png" 2>/dev/null
        $SCP_CMD "${LAPTOP_SSH_USER}@${LAPTOP_SSH_HOST}:${LAPTOP_SSH_RRD_PATH}" "${REPO_DIR}/smokeping/data/Roblox_TCP/Core_API_TCP_laptop.rrd" 2>/dev/null

    elif [ "${LAPTOP_PULL_METHOD}" = "http" ]; then
        # Force remote regeneration by hitting CGI
        curl -s -m 5 -o /dev/null "${LAPTOP_HTTP_CGI}?target=${LOCAL_TARGET}"
        sleep 2
        # Download charts and RRD database
        curl -s -f -m 10 -o "${REPO_DIR}/roblox_gci_native_3h.png" "${LAPTOP_HTTP_IMAGE_3H}"
        curl -s -f -m 10 -o "${REPO_DIR}/roblox_gci_native_10d.png" "${LAPTOP_HTTP_IMAGE_10D}"
        curl -s -f -m 15 -o "${REPO_DIR}/smokeping/data/Roblox_TCP/Core_API_TCP_laptop.rrd" "${LAPTOP_HTTP_RRD}"

    else
        echo "[Remote Node] Error: Invalid pull method configured: ${LAPTOP_PULL_METHOD}"
        remote_success=false
    fi

    if [ -s "${REPO_DIR}/roblox_gci_native_3h.png" ] && [ -s "${REPO_DIR}/roblox_gci_native_10d.png" ]; then
        echo "[Remote Node] Successfully synchronized remote charts (3h and 10d)."
    else
        echo "[Remote Node] Warning: Failed to retrieve remote charts. Keeping existing or skipping."
        remote_success=false
    fi

    # 3. EXTRACT STATS VIA RRDTOOL FROM DATABASES
    echo "[Stats] Extracting dynamic statistics from RRD databases..."

    local vpn_loss="N/A"
    local vpn_latency="N/A"
    local vpn_success="N/A"
    local vpn_jitter="N/A"
    if [ -s "${REPO_DIR}/smokeping/data/Roblox_TCP/Core_API_TCP.rrd" ]; then
        local vpn_loss_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:loss=/data/Roblox_TCP/Core_API_TCP.rrd:loss:AVERAGE VDEF:avgloss=loss,AVERAGE PRINT:avgloss:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')
        local vpn_lat_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:median=/data/Roblox_TCP/Core_API_TCP.rrd:median:AVERAGE VDEF:avgmedian=median,AVERAGE PRINT:avgmedian:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')
        local vpn_jit_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:median=/data/Roblox_TCP/Core_API_TCP.rrd:median:AVERAGE VDEF:devmedian=median,STDEV PRINT:devmedian:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')

        if [[ "$vpn_loss_val" =~ ^[0-9\.]+$ ]]; then
            vpn_loss=$(echo "$vpn_loss_val" | awk '{printf "%.1f", $1 * 5}')
            vpn_success=$(echo "$vpn_loss" | awk '{printf "%.1f", 100 - $1}')
        fi
        if [[ "$vpn_lat_val" =~ ^[0-9\.]+$ ]]; then
            vpn_latency=$(echo "$vpn_lat_val" | awk '{
                val = $1 * 1000;
                if (val >= 1000) {
                    printf "%.2fs", val/1000;
                } else {
                    printf "%.1fms", val;
                }
            }')
        fi
        if [[ "$vpn_jit_val" =~ ^[0-9\.]+$ ]]; then
            vpn_jitter=$(echo "$vpn_jit_val" | awk '{
                val = $1 * 1000;
                if (val >= 1000) {
                    printf "%.2fs", val/1000;
                } else {
                    printf "%.1fms", val;
                }
            }')
        fi
    fi

    local gci_loss="N/A"
    local gci_latency="N/A"
    local gci_success="N/A"
    local gci_jitter="N/A"
    if [ -s "${REPO_DIR}/smokeping/data/Roblox_TCP/Core_API_TCP_laptop.rrd" ]; then
        local gci_loss_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:loss=/data/Roblox_TCP/Core_API_TCP_laptop.rrd:loss:AVERAGE VDEF:avgloss=loss,AVERAGE PRINT:avgloss:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')
        local gci_lat_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:median=/data/Roblox_TCP/Core_API_TCP_laptop.rrd:median:AVERAGE VDEF:avgmedian=median,AVERAGE PRINT:avgmedian:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')
        local gci_jit_val=$(docker exec smokeping rrdtool graph /dev/null --start -3h DEF:median=/data/Roblox_TCP/Core_API_TCP_laptop.rrd:median:AVERAGE VDEF:devmedian=median,STDEV PRINT:devmedian:"%lf" 2>/dev/null | tail -n 1 | tr -d '\r')

        if [[ "$gci_loss_val" =~ ^[0-9\.]+$ ]]; then
            gci_loss=$(echo "$gci_loss_val" | awk '{printf "%.1f", $1 * 5}')
            gci_success=$(echo "$gci_loss" | awk '{printf "%.1f", 100 - $1}')
        fi
        if [[ "$gci_lat_val" =~ ^[0-9\.]+$ ]]; then
            gci_latency=$(echo "$gci_lat_val" | awk '{
                val = $1 * 1000;
                if (val >= 1000) {
                    printf "%.2fs", val/1000;
                } else {
                    printf "%.1fms", val;
                }
            }')
        fi
        if [[ "$gci_jit_val" =~ ^[0-9\.]+$ ]]; then
            gci_jitter=$(echo "$gci_jit_val" | awk '{
                val = $1 * 1000;
                if (val >= 1000) {
                    printf "%.2fs", val/1000;
                } else {
                    printf "%.1fms", val;
                }
            }')
        fi
    fi

    # 4. WRITE METADATA TIMESTAMP
    # Store local timezone and UTC timestamps so the client browser knows precisely how fresh the data is.
    local utc_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local local_time=$(date +"%Y-%m-%dT%H:%M:%S%z")

    cat <<EOF > "${REPO_DIR}/metadata.json"
{
  "last_updated_utc": "${utc_time}",
  "last_updated_local": "${local_time}",
  "local_sync_ok": ${local_success},
  "remote_sync_ok": ${remote_success},
  "vpn_loss_pct": "${vpn_loss}",
  "vpn_latency": "${vpn_latency}",
  "vpn_success_pct": "${vpn_success}",
  "vpn_jitter": "${vpn_jitter}",
  "gci_loss_pct": "${gci_loss}",
  "gci_latency": "${gci_latency}",
  "gci_success_pct": "${gci_success}",
  "gci_jitter": "${gci_jitter}"
}
EOF
    echo "[Metadata] Updated metadata.json with timestamp and parsed RRD statistics."

    # 4. GIT COMMIT AND PUSH
    echo "[Git] Checking for modified telemetry tracking assets..."

    # Only add files if they exist to avoid git fatal pathspec error on first run
    local files_to_add=""
    for file in "${REPO_DIR}/${LOCAL_OUTPUT_3H}" "${REPO_DIR}/${LOCAL_OUTPUT_10D}" "${REPO_DIR}/roblox_gci_native_3h.png" "${REPO_DIR}/roblox_gci_native_10d.png" "${REPO_DIR}/metadata.json"; do
        if [ -f "$file" ]; then
            files_to_add="$files_to_add $file"
        fi
    done

    git add $files_to_add

    # Check if anything is staged to commit
    if git diff --cached --quiet; then
        echo "[Git] Telemetry charts and metadata are already up-to-date. Skipping commit."
    else
        echo "[Git] Staged changes detected. Committing telemetry assets..."
        git commit -m "chore(telemetry): auto-update monitoring charts $(date -u +'%Y-%m-%d %H:%M:%S') UTC"

        local current_branch=$(git rev-parse --abbrev-ref HEAD)
        echo "[Git] Pushing updates to origin ${current_branch}..."
        git push origin HEAD
        if [ $? -eq 0 ]; then
            echo "[Git] Successfully pushed live telemetry assets to GitHub Pages repository!"
        else
            echo "[Git] Error: Failed to push to remote repository."
            sync_success=false
        fi
    fi

    echo "=== Telemetry Synchronization Completed: $(date) ==="
    return 0
}

# --- PROCESS EXECUTION CONTROL ---

if [ "$1" = "--once" ]; then
    sync_telemetry
    exit 0
else
    # Continuous loop
    echo "Running GCI Alaska telemetry sync daemon. Interval: ${INTERVAL_SECONDS}s..."
    while true; do
        sync_telemetry
        echo "Waiting for ${INTERVAL_SECONDS} seconds before next sync..."
        sleep "${INTERVAL_SECONDS}"
    done
fi
