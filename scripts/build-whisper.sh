#!/usr/bin/env bash
#
# Builds the on-device transcription engine (whisper.cpp) as a static
# xcframework for iOS device + simulator. The output is NOT committed to git —
# run this once on a Mac with Xcode, then enable the framework in project.yml
# (uncomment the whisper.xcframework dependency) and `make project`.
#
# The Swift engine code is guarded by `#if canImport(whisper)`, so the app
# builds and runs fine without this step (the on-device engine just reports
# "engine not built" until you run it).
#
# Usage: scripts/build-whisper.sh [whisper.cpp tag]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/Vendor/whisper.cpp"
TAG="${1:-v1.8.6}"
MIN_IOS="16.0"

if [ ! -d "$VENDOR_DIR/.git" ]; then
  echo "==> Cloning whisper.cpp $TAG into Vendor/whisper.cpp"
  git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/whisper.cpp "$VENDOR_DIR"
else
  echo "==> Reusing existing Vendor/whisper.cpp"
fi

cd "$VENDOR_DIR"

# The official build script defaults to a higher iOS min; match this app's 16.0.
if grep -q "IOS_MIN_OS_VERSION=16.4" build-xcframework.sh 2>/dev/null; then
  perl -0pi -e "s/IOS_MIN_OS_VERSION=16\\.4/IOS_MIN_OS_VERSION=$MIN_IOS/" build-xcframework.sh
fi

echo "==> Building static whisper.xcframework (device + simulator)"
BUILD_STATIC_XCFRAMEWORK=ON ./build-xcframework.sh

echo ""
echo "Done: $VENDOR_DIR/build-apple/whisper.xcframework"
echo "Next:"
echo "  1) Uncomment the whisper.xcframework dependency in project.yml"
echo "  2) make project   # regenerate the Xcode project"
echo "  3) Build/run on a device (simulator runs CPU-only)."
