#!/bin/bash
# Removes the FlipcashCore/FlipcashUI SwiftPM resource bundles Xcode copies into an app extension.
# The extension reads the containing app's copy instead (Bundle.packageResources(named:fallback:)),
# so each bundle ships once rather than once per target. Runs as an appex's last build phase,
# before Xcode signs it.
set -euo pipefail

resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
for bundle in FlipcashCore_FlipcashCore.bundle FlipcashUI_FlipcashUI.bundle; do
    rm -rf "${resources:?}/${bundle}"
done
