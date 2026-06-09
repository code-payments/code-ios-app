#!/usr/bin/env bash

# Install the grpc-swift 2.x protoc plugin from source.
#
# The plugin moved to the grpc-swift-protobuf repo in v2 and its executable
# product is named `protoc-gen-grpc-swift-2` — so it coexists with the v1
# `protoc-gen-grpc-swift` binary installed by install-grpc-swift-1-plugin.sh.
# protoc derives the `--grpc-swift-2_out` / `--grpc-swift-2_opt` flags from the
# binary name. Keep both installed during the v1 -> v2 migration; the v1 plugin
# is retired in the final teardown phase.

set -e

# Pin to the version validated during the migration spike.
GRPC_PROTOBUF_TAG="2.4.0"

TEMP_DIR=$(mktemp -d)

# Prefer Homebrew bin (no sudo needed), fall back to /usr/local/bin
if [ -d "/opt/homebrew/bin" ]; then
    INSTALL_DIR="/opt/homebrew/bin"
else
    INSTALL_DIR="/usr/local/bin"
fi

echo "Installing grpc-swift 2.x plugin (grpc-swift-protobuf $GRPC_PROTOBUF_TAG)..."
echo "Temporary directory: $TEMP_DIR"

cd "$TEMP_DIR"

git clone https://github.com/grpc/grpc-swift-protobuf.git
cd grpc-swift-protobuf
git checkout "$GRPC_PROTOBUF_TAG"

# Build the plugin
swift build -c release --product protoc-gen-grpc-swift-2

# Copy to install location
echo "Installing protoc-gen-grpc-swift-2 to $INSTALL_DIR"
cp .build/release/protoc-gen-grpc-swift-2 "$INSTALL_DIR/protoc-gen-grpc-swift-2"
chmod +x "$INSTALL_DIR/protoc-gen-grpc-swift-2"

# Clean up
cd /
rm -rf "$TEMP_DIR"

echo "✓ Successfully installed grpc-swift 2.x plugin"
echo "Location: $INSTALL_DIR/protoc-gen-grpc-swift-2"
protoc-gen-grpc-swift-2 --version
