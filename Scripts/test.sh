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

args=()
for target in "$@"; do
    args+=(-only-testing:"$target")
done

echo "+ xcodebuild test -scheme Flipcash -destination 'platform=iOS Simulator,name=iPhone 17' ${args[*]}"
exec xcodebuild test \
    -scheme Flipcash \
    -destination "platform=iOS Simulator,name=iPhone 17" \
    "${args[@]}"
