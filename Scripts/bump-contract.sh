#!/usr/bin/env bash
#
# Bump a contract package pin in FlipcashAPI/Package.swift and update the
# workspace Package.resolved to match, so the two land in one commit.
# Xcode Cloud resolves only from Package.resolved and refuses to update it; the
# pre-commit hook rejects a pin that disagrees with it.
#
# Usage:
#   ./Scripts/bump-contract.sh <ocp|flipcash2> <version>
#
# Run it only after the version's tag is published on the client-protocol repo.
# The script checks with `git ls-remote` and refuses otherwise.
#
# FLIPCASH_PROTO_LOCAL / FLIPCASH_PROTO_LOCAL_PACKAGES are unset for the run: local
# mode drops the contract entries from Package.resolved, which would make the
# result wrong. Your shell keeps its own values.
#
# On success both files are staged. If resolution changes anything in
# Package.resolved besides that package's entry (and originHash), both files are
# restored and the script exits 1.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PACKAGE_SWIFT="FlipcashAPI/Package.swift"
PACKAGE_RESOLVED="Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

usage() {
    echo "Usage: ./Scripts/bump-contract.sh <ocp|flipcash2> <version>" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
PKG="$1"
VERSION="$2"

case "$PKG" in
    ocp) IDENTITY="ocp-client-protocol" ;;
    flipcash2) IDENTITY="flipcash2-client-protocol" ;;
    *) usage ;;
esac

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: '$VERSION' is not a X.Y.Z version." >&2
    exit 2
fi

if ! git diff --quiet -- "$PACKAGE_SWIFT" "$PACKAGE_RESOLVED" || ! git diff --cached --quiet -- "$PACKAGE_SWIFT" "$PACKAGE_RESOLVED"; then
    echo "error: $PACKAGE_SWIFT or Package.resolved already has uncommitted changes; commit or restore them first." >&2
    exit 1
fi

if [[ -z "$(git ls-remote --tags "https://github.com/code-payments/$IDENTITY" "$VERSION")" ]]; then
    echo "error: tag $VERSION not found on code-payments/$IDENTITY. Publish the release first." >&2
    exit 1
fi

restore() {
    git checkout -- "$PACKAGE_SWIFT" "$PACKAGE_RESOLVED"
    git restore --staged -- "$PACKAGE_SWIFT" "$PACKAGE_RESOLVED" 2>/dev/null || true
}

# Only the `case .<pkg>: return "X.Y.Z"` line in `version` changes; directoryName's
# `return "<identity>"` lines don't match the digits pattern.
sed -i.bak -E "s/^([[:space:]]*case \.$PKG:[[:space:]]*return \")[0-9]+\.[0-9]+\.[0-9]+[^\"]*(\")/\1$VERSION\2/" "$PACKAGE_SWIFT"
rm -f "$PACKAGE_SWIFT.bak"

PINNED="$(sed -nE "s/^[[:space:]]*case \.$PKG:[[:space:]]*return \"([0-9]+\.[0-9]+\.[0-9]+[^\"]*)\"[[:space:]]*$/\1/p" "$PACKAGE_SWIFT")"
if [[ "$PINNED" != "$VERSION" ]]; then
    echo "error: could not set the $PKG pin in $PACKAGE_SWIFT." >&2
    restore
    exit 1
fi

echo "Resolving $IDENTITY $VERSION..."
if ! env -u FLIPCASH_PROTO_LOCAL -u FLIPCASH_PROTO_LOCAL_PACKAGES \
    xcodebuild -resolvePackageDependencies -project Code.xcodeproj -scheme Flipcash >/dev/null; then
    echo "error: xcodebuild -resolvePackageDependencies failed." >&2
    restore
    exit 1
fi

# Flatten each pin to "identity location revision version" so the committed and the
# resolved file compare line by line. Everything except this identity must be
# identical; originHash isn't a pin, so it never enters the comparison.
flatten_pins() {
    awk '
        /"identity" :/ { gsub(/.*: "|",?$/, ""); id = $0; loc = rev = ver = "-" }
        /"location" :/ { gsub(/.*: "|",?$/, ""); loc = $0 }
        /"revision" :/ { gsub(/.*: "|",?$/, ""); rev = $0 }
        /"version" :/ { gsub(/.*: "|",?$/, ""); ver = $0; print id, loc, rev, ver }
    '
}
UNEXPECTED="$(diff \
    <(git show "HEAD:$PACKAGE_RESOLVED" | flatten_pins | grep -v "^$IDENTITY ") \
    <(flatten_pins < "$PACKAGE_RESOLVED" | grep -v "^$IDENTITY ") || true)"
if [[ -n "$UNEXPECTED" ]]; then
    echo "error: resolving changed Package.resolved beyond $IDENTITY:" >&2
    echo "$UNEXPECTED" >&2
    restore
    exit 1
fi

NEW="$(awk -v id="$IDENTITY" '
    $0 ~ "\"identity\" : \"" id "\"" { found = 1; next }
    found && /"version" :/ { gsub(/.*: "|".*/, ""); print; exit }
' "$PACKAGE_RESOLVED")"
if [[ "$NEW" != "$VERSION" ]]; then
    echo "error: Package.resolved records ${NEW:-<missing>} for $IDENTITY, expected $VERSION." >&2
    restore
    exit 1
fi

git add "$PACKAGE_SWIFT" "$PACKAGE_RESOLVED"
echo "✓ $IDENTITY pinned to $VERSION in both files, staged"
