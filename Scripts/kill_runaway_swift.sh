#!/bin/bash
#
# Monitors swift-frontend processes and kills them if they exceed memory limit.
# Usage: ./kill_runaway_swift.sh [memory_limit_gb]
#
# Default limit: 15GB per process

LIMIT_GB=${1:-15}
LIMIT_KB=$((LIMIT_GB * 1024 * 1024))
INTERVAL=2

echo "Monitoring swift-frontend processes..."
echo "Memory limit: ${LIMIT_GB}GB per process"
echo "Checking every ${INTERVAL} seconds"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Get swift-frontend processes with their PID and RSS (resident memory in KB)
    ps -eo pid,rss,comm | grep 'swift-frontend' | while read pid rss comm; do
        if [ -n "$pid" ] && [ "$rss" -gt "$LIMIT_KB" ] 2>/dev/null; then
            mem_gb=$(echo "scale=2; $rss / 1024 / 1024" | bc)
            echo "[$(date '+%H:%M:%S')] Killing swift-frontend (PID: $pid) using ${mem_gb}GB"
            kill -9 "$pid" 2>/dev/null
        fi
    done
    sleep $INTERVAL
done
