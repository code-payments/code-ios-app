#!/usr/bin/env bash
#
# Build the Flipcash app for iOS.
# Use this to verify the app compiles without running tests.
#
# Usage:
#   ./Scripts/build.sh [extra xcodebuild args...]            # generic iOS build (default)
#   ./Scripts/build.sh --device [name] [extra args...]       # paired physical device
#   ./Scripts/build.sh --install [name] [extra args...]      # build, install, launch
#   ./Scripts/build.sh -destination <spec|sim name|UDID>     # only that destination
#   ./Scripts/build.sh --session <query> [other args...]     # build a session's worktree
#   ./Scripts/build.sh --session                             # list live sessions
#
# --device with no argument picks $FLIPCASH_DEVICE, or else the first paired
# iOS device. Pass a name substring to disambiguate (e.g. --device "Raul's iPhone").
# --install takes the same name and also installs and launches the build on it.
#
# Override the destination with `-destination <spec>` (replaces the default
# rather than adding to it) or the DESTINATION env var. The -destination value
# can also be a simulator name or UDID, e.g. -destination Flipcash.
#
# --session finds the Claude Code session matching <query> and runs the build.sh
# in the checkout that session is working in, with the remaining args. The query
# is a session id prefix, a PR number (915 or #915), a worktree directory name, a
# branch, or a substring of the session title, branch, or worktree name. Titles
# exist only once a session is named; unnamed sessions still match by branch, PR,
# worktree, or id. Desktop worktrees are reused across sessions, so a warning is
# printed when the worktree has since moved off the session's branch. A worktree
# whose build.sh predates --install (#928) rejects it.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Handle --session before anything else: the target's own build.sh does its own
# cd and arg parsing, so strip the flag and exec it with what is left.
SESSION=""
SESSION_QUERY=""
ARGS=()
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--session" ]]; then
        SESSION=1
        if [[ $# -gt 1 && "$2" != -* ]]; then
            SESSION_QUERY="$2"
            shift
        fi
        shift
        continue
    fi
    ARGS+=("$1")
    shift
done
set -- ${ARGS[@]+"${ARGS[@]}"}

if [[ -n "$SESSION" ]]; then
    REPO_ROOT="$(dirname "$(git -C "$SCRIPT_DIR/.." rev-parse --path-format=absolute --git-common-dir)")"
    if [[ -z "$SESSION_QUERY" ]]; then
        python3 "$SCRIPT_DIR/lib/claude_session.py" "$REPO_ROOT" list
        exit 0
    fi
    IFS=$'\t' read -r TARGET SESSION_BRANCH < <(
        python3 "$SCRIPT_DIR/lib/claude_session.py" "$REPO_ROOT" resolve "$SESSION_QUERY" || echo
    )
    [[ -n "${TARGET:-}" ]] || exit 1
    CURRENT_BRANCH="$(git -C "$TARGET" branch --show-current)"
    if [[ -n "$SESSION_BRANCH" && "$CURRENT_BRANCH" != "$SESSION_BRANCH" ]]; then
        echo "warning: session was on $SESSION_BRANCH; $(basename "$TARGET") now has ${CURRENT_BRANCH:-a detached HEAD} checked out." >&2
    fi
    echo "+ session → $TARGET"
    exec "$TARGET/Scripts/build.sh" "$@"
fi

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

# Resolve a simulator name or UDID to its UDID. A name shared across runtimes
# picks the booted one, else the newest runtime.
resolve_simulator_udid() {
    xcrun simctl list devices available -j | python3 -c '
import json, re, sys
want = sys.argv[1]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.rsplit(".", 1)[-1])]
matches = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for dev in devices:
        if dev["udid"].lower() == want.lower() or dev["name"] == want:
            matches.append((dev["state"] == "Booted", version(runtime), dev["udid"]))
if matches:
    print(max(matches)[2])
' "$1"
}

DESTINATION="${DESTINATION:-}"

INSTALL=""
UDID=""
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

# Lift a passed -destination out of the extra args so it replaces the default
# instead of being built alongside it; xcodebuild builds every destination given.
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-destination" ]]; then
        if [[ $# -lt 2 ]]; then
            echo "error: -destination needs a value." >&2
            exit 2
        fi
        if [[ -n "$UDID" ]]; then
            echo "error: -destination can't be combined with --device or --install." >&2
            exit 2
        fi
        DESTINATION="$2"
        # Anything that isn't a key=value spec is a simulator name or UDID.
        if [[ "$DESTINATION" != *=* && "$DESTINATION" != generic/* ]]; then
            SIM_UDID="$(resolve_simulator_udid "$DESTINATION")"
            if [[ -z "$SIM_UDID" ]]; then
                echo "error: no available simulator named or with UDID \"$DESTINATION\"." >&2
                echo "       List with: xcrun simctl list devices available" >&2
                exit 1
            fi
            DESTINATION="id=$SIM_UDID"
        fi
        shift 2
        continue
    fi
    EXTRA_ARGS+=("$1")
    shift
done
set -- ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

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
