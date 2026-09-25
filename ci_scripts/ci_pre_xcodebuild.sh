#!/bin/sh

# Stamp CI_COMMIT into the build. The scheme pre-action does the same, but it
# runs only for scheme-driven actions; this covers every xcodebuild Xcode Cloud
# runs, and it never fails the build.
"$CI_PRIMARY_REPOSITORY_PATH/Scripts/write_commit_xcconfig" "$CI_PRIMARY_REPOSITORY_PATH"
