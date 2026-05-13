#!/usr/bin/env bash
#
# Build the Flipcash app for iOS.
# Use this to verify the app compiles without running tests.
#
# Usage:
#   ./Scripts/build.sh [extra xcodebuild args...]            # generic iOS build (default)
#   ./Scripts/build.sh --device [name] [extra args...]       # paired physical device
#
# --device with no argument picks the first paired iOS device. Pass a name
# substring to disambiguate (e.g. --device "Raul's iPhone").
#
# Override the destination directly with DESTINATION env var.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

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

DESTINATION="${DESTINATION:-}"

if [[ "${1:-}" == "--device" ]]; then
    shift
    MATCH=""
    if [[ $# -gt 0 && "$1" != -* ]]; then
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

DESTINATION="${DESTINATION:-generic/platform=iOS}"

echo "+ xcodebuild build -scheme Flipcash -destination '$DESTINATION' $*"
exec xcodebuild build \
    -scheme Flipcash \
    -destination "$DESTINATION" \
    "$@"
