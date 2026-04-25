#!/usr/bin/env bash
#
# Build the Flipcash app for iOS.
# Use this to verify the app compiles without running tests.
#
# Usage:
#   ./Scripts/build.sh [extra xcodebuild args...]
#
# Override the destination with DESTINATION env var (default: generic/platform=iOS).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

DESTINATION="${DESTINATION:-generic/platform=iOS}"

echo "+ xcodebuild build -scheme Flipcash -destination '$DESTINATION' $*"
exec xcodebuild build \
    -scheme Flipcash \
    -destination "$DESTINATION" \
    "$@"
