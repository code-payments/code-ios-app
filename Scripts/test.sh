#!/usr/bin/env bash
#
# Run targeted iOS tests via the Flipcash scheme.
#
# Usage:
#   ./Scripts/test.sh [--device [name]] <Target>/<Suite>[/<TestName>] [...]
#
# Default destination is the iPhone 17 simulator. Pass --device (optionally
# followed by a name substring) to run against a paired physical device.
#
# Examples:
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests/myTestCase
#   ./Scripts/test.sh --device FlipcashTests/SomeUITests
#   ./Scripts/test.sh --device "Raul's iPhone" FlipcashTests/SomeUITests
#
# This script intentionally does NOT support -testPlan AllTargets —
# the full suite is run from Xcode or CI, not from here.

set -e

# Resolve a paired iOS device UDID via devicectl.
#
# Use devicectl, NOT `xcrun xctrace list devices` — xctrace often labels
# paired iPhones as "Offline" even when they are connected and available
# to xcodebuild via the network-paired CoreDevice transport.
resolve_device_udid() {
    local match="${1:-}"
    local tmp
    tmp=$(mktemp)
    if ! xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        return 1
    fi
    python3 - "$match" "$tmp" <<'PY'
import json, sys
match = sys.argv[1].lower()
data = json.load(open(sys.argv[2]))
for dev in data["result"]["devices"]:
    hw = dev.get("hardwareProperties", {})
    if hw.get("platform") != "iOS":
        continue
    name = dev.get("deviceProperties", {}).get("name", "")
    if match and match not in name.lower():
        continue
    udid = hw.get("udid", "")
    if udid:
        print(udid)
        break
PY
    rm -f "$tmp"
}

DESTINATION="platform=iOS Simulator,name=iPhone 17"

if [[ "${1:-}" == "--device" ]]; then
    shift
    MATCH=""
    if [[ $# -gt 0 && "$1" != -* && "$1" != */* ]]; then
        MATCH="$1"
        shift
    fi
    UDID="$(resolve_device_udid "$MATCH")"
    if [[ -z "$UDID" ]]; then
        echo "error: no paired iOS device found${MATCH:+ matching \"$MATCH\"}." >&2
        echo "       List with: xcrun devicectl list devices" >&2
        exit 1
    fi
    DESTINATION="platform=iOS,id=$UDID"
fi

if [ "$#" -eq 0 ]; then
    cat >&2 <<EOF
error: at least one test identifier is required.

Usage: $0 [--device [name]] <Target>/<Suite>[/<TestName>] [<Target>/<Suite>[/<TestName>]...]

Examples:
  $0 FlipcashCoreTests/ExchangedFiatTests
  $0 FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests
  $0 FlipcashCoreTests/ExchangedFiatTests/myTestCase
  $0 --device FlipcashTests/SomeUITests
EOF
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

args=()
for target in "$@"; do
    args+=(-only-testing:"$target")
done

echo "+ xcodebuild test -scheme Flipcash -destination '$DESTINATION' ${args[*]}"
exec xcodebuild test \
    -scheme Flipcash \
    -destination "$DESTINATION" \
    "${args[@]}"
