#!/bin/bash
# performance_metric_uploading_daemon.sh
# handles -march= / -mtune= architecture-specific distribution
set -euxo pipefail

# 1. Define variables
PERF_BIN=$(ls /usr/bin/perf_* | head -n 1 || echo "perf")
NEXUS_URL="http://performance_metric_merging_service.innovanon.com:9321/submit"
STAGING_DIR="/tmp/chimera-staging"
mkdir -p "$STAGING_DIR"

echo "⏳ Sampling global performance (focusing on containerized targets)..."

# 2. Record performance data
# -a: all CPUs, -b: branch stacks, -e: specific cycle event
$PERF_BIN record -a -b -e br_inst_retired.near_taken:pp --output=perf.data --quiet -- sleep 60

# 3. Extract paths (The Multi-Stage Hunt)
echo "🔎 Extracting maps from perf.data..."

# Strategy A: Use mmap events to find exactly where binaries are loaded
MAPS=$($PERF_BIN script -i perf.data --show-mmap-events 2>/dev/null | grep "MMAP" | awk '{print $NF}' | grep '^/' | grep -vE "(deleted|anon|\[)" | sort -u || echo "")

# Strategy B: Fallback to report DSOs if Strategy A is empty
if [ -z "$MAPS" ]; then
    MAPS=$($PERF_BIN report -i perf.data --stdio --dsos 2>/dev/null | grep '/' | awk '{print $NF}' | sort -u || echo "")
fi

# Strategy C: Standard field parsing
if [ -z "$MAPS" ]; then
    MAPS=$($PERF_BIN script -i perf.data 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}' | grep -E "\.so|bin/|lib/" | sort -u || echo "")
fi

echo "🔎 Found active binaries: $MAPS"

# 4. Process each binary
for BIN_PATH in $MAPS; do
    # Strip any potential '/host' prefix to help apt-file inside the container
    CLEAN_PATH=${BIN_PATH#/host}
    
    # Identify the package
    PACKAGE=$(apt-file search "$CLEAN_PATH" | head -n1 | cut -d: -f1 || echo "")

    if [ -n "$PACKAGE" ]; then
        echo "🎯 Target: $PACKAGE (Path: $BIN_PATH)"
        AFDO_FILE="$STAGING_DIR/$PACKAGE.afdo"

        # Check if binary is visible locally or through the host mount
        REAL_BIN="$BIN_PATH"
        [ ! -f "$REAL_BIN" ] && REAL_BIN="/host$BIN_PATH"

        if [ -f "$REAL_BIN" ]; then
            echo "🧪 Generating AFDO profile for $PACKAGE..."
            # create_gcov uses the binary symbols + the perf data to create the profile
            if create_gcov --binary="$REAL_BIN" --profile=perf.data --gcov="$AFDO_FILE"; then
                
                if [ -f "$AFDO_FILE" ]; then
                    echo "🚀 Uploading $PACKAGE profile to Nexus..."
                    curl -X POST "$NEXUS_URL/$PACKAGE" \
                         -H "X-Arch: $(uname -m)" \
                         -H "X-Compiler: gcc" \
                         -F "file=@$AFDO_FILE"
                    rm "$AFDO_FILE"
                fi
            else
                echo "⚠️ Failed to create gcov for $PACKAGE"
            fi
        else
            echo "📂 Skipping: Binary not found at $REAL_BIN"
        fi
    fi
done

# Cleanup the binary data for the next loop
rm -f perf.data
echo "🏁 Cycle complete. Waiting for next window..."
