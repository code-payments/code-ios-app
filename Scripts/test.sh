#!/usr/bin/env bash
#
# Run targeted iOS Simulator tests via the Flipcash scheme.
#
# Usage:
#   ./Scripts/test.sh <Target>/<Suite>[/<TestName>] [<Target>/<Suite>[/<TestName>]...]
#
# Examples:
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests
#   ./Scripts/test.sh FlipcashCoreTests/ExchangedFiatTests/myTestCase
#
# Parallel testing is forced OFF (-parallel-testing-enabled NO) so Xcode does
# not spawn ephemeral "Clone N of ..." simulators that pile up on disk. Targeted
# runs here are small, so the lost parallelism is negligible.
#
# Each checkout runs on its own simulator, "Flipcash Tests <checkout dir>",
# created from the iPhone 17 device type on first use. Every worktree builds the
# same bundle ID, so on a shared simulator one session's install terminates
# another session's running test host mid-test.
#
# It fails when no test ran, and prints the result bundle's path and the count.
#
# This script intentionally does NOT support -testPlan AllTargets —
# the full suite is run from Xcode or CI, not from here.

set -e

if [ "$#" -eq 0 ]; then
    cat >&2 <<EOF
error: at least one test identifier is required.

Usage: $0 <Target>/<Suite>[/<TestName>] [<Target>/<Suite>[/<TestName>]...]

Examples:
  $0 FlipcashCoreTests/ExchangedFiatTests
  $0 FlipcashCoreTests/ExchangedFiatTests FlipcashCoreTests/FiatTests
  $0 FlipcashCoreTests/ExchangedFiatTests/myTestCase
EOF
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
source "$SCRIPT_DIR/lib/xcodebuild.sh"

args=()
for target in "$@"; do
    args+=(-only-testing:"$target")
done

sim_name="Flipcash Tests $(basename "$(git rev-parse --show-toplevel)")"
sim_udid="$(xcrun simctl list devices available \
    | grep -F "    $sim_name (" \
    | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' \
    | head -n 1 || true)"
if [ -z "$sim_udid" ]; then
    echo "+ xcrun simctl create '$sim_name' 'iPhone 17'"
    sim_udid="$(xcrun simctl create "$sim_name" "iPhone 17")"
fi

tmp="${TMPDIR:-/tmp}"
bundle="$(mktemp -d "${tmp%/}/flipcash-tests.XXXXXX")/Tests.xcresult"

echo "+ xcodebuild test -scheme Flipcash -destination 'id=$sim_udid' -parallel-testing-enabled NO ${args[*]}"
status=0
run_xcodebuild test \
    -scheme Flipcash \
    -destination "id=$sim_udid" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$bundle" \
    "${args[@]}" || status=$?
echo "+ result bundle: $bundle"
[ "$status" -eq 0 ] || exit "$status"

# xcodebuild exits 0 when no identifier matches a test, so a typo or a list
# passed as one argument would otherwise read as a pass.
count="$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null \
    | grep -oE '"totalTestCount":[0-9]+' | cut -d: -f2 || true)"
if [ -z "$count" ]; then
    echo "error: couldn't read the test count from $bundle" >&2
    exit 1
fi
if [ "$count" -eq 0 ]; then
    cat >&2 <<EOF
error: no tests ran. Pass each identifier as its own argument, as
<Target>/<Suite> or <Target>/<Suite>/<test>() (Swift Testing tests end in "()").
EOF
    exit 1
fi
echo "+ $count tests ran"
