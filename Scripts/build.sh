#!/usr/bin/env bash
#
# Build the Flipcash app for iOS.
# Use this to verify the app compiles without running tests.
#
# Usage:
#   ./Scripts/build.sh [extra xcodebuild args...]            # generic iOS build (default)
#   ./Scripts/build.sh --device [name] [extra args...]       # paired physical device
#   ./Scripts/build.sh --install [name] [extra args...]      # build, install, launch
#
# --device with no argument picks $FLIPCASH_DEVICE, or else the first paired
# iOS device. Pass a name substring to disambiguate (e.g. --device "Raul's iPhone").
# --install takes the same name and also installs and launches the build on it.
#
# Override the destination directly with DESTINATION env var.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
source "$SCRIPT_DIR/lib/xcodebuild.sh"

# Ensure the repo's versioned pre-commit hook is active. Idempotent — first
# build of a fresh clone wires it up; subsequent runs are silent.
if [[ "$(git config --get core.hooksPath 2>/dev/null || true)" != "Scripts/git-hooks" ]]; then
    git config core.hooksPath Scripts/git-hooks
    echo "✓ git hooks installed: core.hooksPath = Scripts/git-hooks"
fi

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

INSTALL=""
if [[ "${1:-}" == "--device" || "${1:-}" == "--install" ]]; then
    [[ "$1" == "--install" ]] && INSTALL=1
    shift
    MATCH="${FLIPCASH_DEVICE:-}"
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
run_xcodebuild build \
    -scheme Flipcash \
    -destination "$DESTINATION" \
    "$@"

[[ -z "$INSTALL" ]] && exit 0

# Ask xcodebuild where the product landed rather than assuming a DerivedData
# path, so extra args like -configuration or -derivedDataPath still resolve.
IFS=$'\t' read -r APP_PATH BUNDLE_ID < <(
    xcodebuild -showBuildSettings -json -scheme Flipcash -destination "$DESTINATION" "$@" 2>/dev/null |
    python3 -c '
import json, sys
for target in json.load(sys.stdin):
    s = target["buildSettings"]
    if s.get("WRAPPER_EXTENSION") == "app":
        print(s["TARGET_BUILD_DIR"] + "/" + s["WRAPPER_NAME"], s["PRODUCT_BUNDLE_IDENTIFIER"], sep="\t")
        break
'
)
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
    echo "error: could not locate the built app${APP_PATH:+ at $APP_PATH}." >&2
    exit 1
fi

# A locked device can make devicectl hang or fail with IXRemoteErrorDomain 6.
echo "+ installing $APP_PATH on $UDID (unlock the device if this stalls)"
xcrun devicectl device install app --device "$UDID" "$APP_PATH" >/dev/null
echo "✓ installed $BUNDLE_ID"
if xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "✓ launched $BUNDLE_ID"
else
    echo "warning: installed but could not launch; the device is probably locked." >&2
fi
