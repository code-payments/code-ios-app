#!/usr/bin/env bash

# Install grpc-swift 1.x protoc plugin from source
# This is needed because Homebrew only provides version 2.x

set -e

TEMP_DIR=$(mktemp -d)

# Prefer Homebrew bin (no sudo needed), fall back to /usr/local/bin
if [ -d "/opt/homebrew/bin" ]; then
    INSTALL_DIR="/opt/homebrew/bin"
else
    INSTALL_DIR="/usr/local/bin"
fi

echo "Installing grpc-swift 1.x plugin..."
echo "Temporary directory: $TEMP_DIR"

cd "$TEMP_DIR"

# Clone grpc-swift repository
git clone https://github.com/grpc/grpc-swift.git
cd grpc-swift

# Checkout the latest 1.x version (1.23.1 is the last 1.x release)
git checkout 1.23.1

# Build the plugin
swift build -c release --product protoc-gen-grpc-swift

# Copy to install location
echo "Installing protoc-gen-grpc-swift to $INSTALL_DIR"
cp .build/release/protoc-gen-grpc-swift "$INSTALL_DIR/protoc-gen-grpc-swift"
chmod +x "$INSTALL_DIR/protoc-gen-grpc-swift"

# Clean up
cd /
rm -rf "$TEMP_DIR"

echo "✓ Successfully installed grpc-swift 1.x plugin"
echo "Location: $INSTALL_DIR/protoc-gen-grpc-swift"
protoc-gen-grpc-swift --version
