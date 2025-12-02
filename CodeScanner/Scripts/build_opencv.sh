#!/bin/bash
#
# build_opencv.sh
#
# Builds OpenCV as an XCFramework for iOS with the correct structure for Swift Package Manager.
#
# This script:
# 1. Clones OpenCV (or uses existing clone)
# 2. Builds for iOS device (arm64) and simulator (arm64 + x86_64)
# 3. Creates an XCFramework
# 4. Flattens the framework structure for iOS shallow bundles
# 5. Adds module maps for Swift/Clang module support
#
# Usage:
#   ./build_opencv.sh [--version <tag>] [--clean]
#
# Examples:
#   ./build_opencv.sh                    # Build latest release
#   ./build_opencv.sh --version 4.10.0   # Build specific version
#   ./build_opencv.sh --clean            # Clean and rebuild
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODESCANNER_DIR="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$CODESCANNER_DIR/Frameworks"
BUILD_DIR="/tmp/opencv_build_$$"
OPENCV_DIR="/tmp/opencv_source"

# Default OpenCV version (empty = latest release tag)
OPENCV_VERSION=""
CLEAN_BUILD=false

# OpenCV modules to EXCLUDE (reduces size significantly)
EXCLUDED_MODULES=(
    "objc"
    "java"
    "python"
    "video"
    "videoio"
    "highgui"
    "ml"
    "dnn"
    "photo"
    "stitching"
    "gapi"
    "ts"
    "world"
)

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

check_dependencies() {
    log "Checking dependencies..."

    command -v git >/dev/null 2>&1 || error "git is required but not installed"
    command -v python3 >/dev/null 2>&1 || error "python3 is required but not installed"
    command -v cmake >/dev/null 2>&1 || error "cmake is required. Install with: brew install cmake"
    command -v xcodebuild >/dev/null 2>&1 || error "Xcode command line tools required"

    # Check cmake version (need 3.18.5+)
    CMAKE_VERSION=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    log "Found cmake version: $CMAKE_VERSION"
}

get_latest_opencv_version() {
    log "Fetching latest OpenCV release tag..."
    git ls-remote --tags --refs https://github.com/opencv/opencv.git \
        | grep -oE 'refs/tags/[0-9]+\.[0-9]+\.[0-9]+$' \
        | sed 's|refs/tags/||' \
        | sort -V \
        | tail -1
}

clone_opencv() {
    local version="$1"

    if [ -d "$OPENCV_DIR" ]; then
        log "OpenCV source exists at $OPENCV_DIR"
        cd "$OPENCV_DIR"

        # Fetch latest tags
        git fetch --tags

        # Check if we need to checkout a different version
        CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$CURRENT_TAG" != "$version" ]; then
            log "Switching from $CURRENT_TAG to $version"
            git checkout "$version"
        else
            log "Already on version $version"
        fi
    else
        log "Cloning OpenCV $version..."
        git clone --depth 1 --branch "$version" https://github.com/opencv/opencv.git "$OPENCV_DIR"
    fi
}

build_xcframework() {
    log "Building OpenCV XCFramework..."

    cd "$OPENCV_DIR"

    # Build the --without arguments
    local WITHOUT_ARGS=""
    for module in "${EXCLUDED_MODULES[@]}"; do
        WITHOUT_ARGS="$WITHOUT_ARGS --without $module"
    done

    # Run the build script
    python3 platforms/apple/build_xcframework.py \
        --out "$BUILD_DIR" \
        --iphoneos_archs arm64 \
        --iphonesimulator_archs arm64,x86_64 \
        --build_only_specified_archs \
        $WITHOUT_ARGS

    log "XCFramework built successfully"
}

flatten_framework() {
    local fw_path="$1"
    log "Flattening framework: $fw_path"

    # Check if it has a Versions directory (macOS-style, needs flattening)
    if [ -d "$fw_path/Versions" ]; then
        # Remove symlinks
        rm -f "$fw_path/Headers" "$fw_path/Modules" "$fw_path/opencv2" "$fw_path/Resources" 2>/dev/null || true

        # Copy contents from Versions/A (or Versions/Current) to root
        local version_dir=""
        if [ -d "$fw_path/Versions/A" ]; then
            version_dir="$fw_path/Versions/A"
        elif [ -d "$fw_path/Versions/Current" ]; then
            version_dir="$fw_path/Versions/Current"
        else
            error "Could not find version directory in $fw_path/Versions"
        fi

        # Copy everything from version dir to framework root
        cp -R "$version_dir/"* "$fw_path/"

        # Remove the Versions directory
        rm -rf "$fw_path/Versions"

        # Move Info.plist from Resources to root (iOS shallow bundle requirement)
        if [ -f "$fw_path/Resources/Info.plist" ]; then
            mv "$fw_path/Resources/Info.plist" "$fw_path/Info.plist"
        fi

        # Remove Resources if empty or only has non-essential files
        if [ -d "$fw_path/Resources" ]; then
            # Keep PrivacyInfo.xcprivacy if it exists, but we need Info.plist at root
            if [ ! -f "$fw_path/Resources/Info.plist" ]; then
                # Resources is fine to keep for privacy manifest
                :
            fi
        fi

        log "Framework flattened: $fw_path"
    else
        log "Framework already flat: $fw_path"
    fi
}

add_modulemap() {
    local fw_path="$1"
    local modules_dir="$fw_path/Modules"

    log "Adding modulemap to: $fw_path"

    mkdir -p "$modules_dir"

    cat > "$modules_dir/module.modulemap" << 'EOF'
framework module opencv2 {
    umbrella header "opencv2.hpp"

    export *
    module * { export * }

    link framework "Accelerate"
    link framework "CoreGraphics"
    link framework "CoreVideo"
    link framework "QuartzCore"
    link framework "UIKit"
}
EOF

    log "Modulemap added"
}

process_xcframework() {
    local xcfw_path="$1"

    log "Processing XCFramework: $xcfw_path"

    # Find all .framework directories inside the xcframework
    find "$xcfw_path" -type d -name "*.framework" | while read -r fw; do
        flatten_framework "$fw"
        add_modulemap "$fw"
    done

    log "XCFramework processing complete"
}

install_xcframework() {
    local source="$BUILD_DIR/opencv2.xcframework"
    local dest="$FRAMEWORKS_DIR/opencv2.xcframework"

    log "Installing XCFramework to $dest"

    # Backup existing if present
    if [ -d "$dest" ]; then
        local backup="$dest.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backing up existing framework to $backup"
        mv "$dest" "$backup"
    fi

    # Copy new framework
    cp -R "$source" "$dest"

    log "Installation complete"
}

cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        log "Cleaning up build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
}

print_summary() {
    local xcfw_path="$FRAMEWORKS_DIR/opencv2.xcframework"

    echo ""
    echo "=============================================="
    echo "OpenCV XCFramework Build Complete"
    echo "=============================================="
    echo ""
    echo "Version:  $OPENCV_VERSION"
    echo "Location: $xcfw_path"
    echo ""
    echo "Size:"
    du -sh "$xcfw_path"
    echo ""
    echo "Architectures:"
    echo "  - iOS Device: arm64"
    echo "  - iOS Simulator: arm64, x86_64"
    echo ""
    echo "Excluded modules: ${EXCLUDED_MODULES[*]}"
    echo ""
    echo "To update the main project:"
    echo "  1. Clean build folder in Xcode (Cmd+Shift+K)"
    echo "  2. Build the project (Cmd+B)"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                OPENCV_VERSION="$2"
                shift 2
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--version <tag>] [--clean]"
                echo ""
                echo "Options:"
                echo "  --version <tag>  Specify OpenCV version (e.g., 4.10.0)"
                echo "  --clean          Remove cached OpenCV source and rebuild"
                echo ""
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    log "Starting OpenCV build for iOS..."

    # Check dependencies
    check_dependencies

    # Clean if requested
    if [ "$CLEAN_BUILD" = true ] && [ -d "$OPENCV_DIR" ]; then
        log "Cleaning OpenCV source directory..."
        rm -rf "$OPENCV_DIR"
    fi

    # Determine version
    if [ -z "$OPENCV_VERSION" ]; then
        OPENCV_VERSION=$(get_latest_opencv_version)
    fi
    log "Target OpenCV version: $OPENCV_VERSION"

    # Create build directory
    mkdir -p "$BUILD_DIR"
    mkdir -p "$FRAMEWORKS_DIR"

    # Clone/update OpenCV
    clone_opencv "$OPENCV_VERSION"

    # Build XCFramework
    build_xcframework

    # Process XCFramework (flatten + add modulemaps)
    process_xcframework "$BUILD_DIR/opencv2.xcframework"

    # Install to Frameworks directory
    install_xcframework

    # Cleanup
    cleanup

    # Print summary
    print_summary

    log "Done!"
}

# Run main function
main "$@"
