#!/usr/bin/env bash
#
# Fetches the sherpa-onnx on-device ASR backend (M7) into Vendor/sherpa-onnx/:
#   - sherpa-onnx.xcframework        (from the official iOS release tarball)
#   - onnxruntime.xcframework        (matching ONNX Runtime build)
#   - SherpaOnnx.swift + bridging header (the vendored Swift wrapper)
#
# Output is NOT committed (Vendor/ is gitignored). After running this, enable
# sherpa in project.yml per the printed instructions, then `make project`.
# The engine code is gated by the SHERPA_ONNX_ENABLED compile flag, so the app
# builds fine without this step.
#
# Usage: scripts/fetch-sherpa-libs.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/Vendor/sherpa-onnx"
SHERPA_VER="v1.13.2"
ORT_VER="1.17.1"
mkdir -p "$VENDOR"
cd "$VENDOR"

echo "==> Downloading sherpa-onnx $SHERPA_VER iOS libraries"
curl -L "https://github.com/k2-fsa/sherpa-onnx/releases/download/$SHERPA_VER/sherpa-onnx-$SHERPA_VER-ios.tar.bz2" -o sherpa-ios.tar.bz2
tar xjf sherpa-ios.tar.bz2
# Locate the produced xcframework and lift it to a stable path.
SHERPA_XC="$(find . -type d -name 'sherpa-onnx.xcframework' | head -1)"
[ -n "$SHERPA_XC" ] && [ "$SHERPA_XC" != "./sherpa-onnx.xcframework" ] && rm -rf ./sherpa-onnx.xcframework && cp -R "$SHERPA_XC" ./sherpa-onnx.xcframework

echo "==> Downloading onnxruntime $ORT_VER xcframework"
curl -L "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v$ORT_VER/onnxruntime.xcframework-$ORT_VER.tar.bz2" -o ort.tar.bz2
tar xjf ort.tar.bz2
ORT_XC="$(find . -type d -name 'onnxruntime.xcframework' | head -1)"
[ -n "$ORT_XC" ] && [ "$ORT_XC" != "./onnxruntime.xcframework" ] && rm -rf ./onnxruntime.xcframework && cp -R "$ORT_XC" ./onnxruntime.xcframework

echo "==> Fetching vendored Swift wrapper + bridging header"
BASE="https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/$SHERPA_VER/swift-api-examples"
curl -L "$BASE/SherpaOnnx.swift" -o SherpaOnnx.swift
curl -L "$BASE/SherpaOnnx-Bridging-Header.h" -o SherpaOnnx-Bridging-Header.h

echo ""
echo "Done. Vendored into $VENDOR:"
echo "  sherpa-onnx.xcframework, onnxruntime.xcframework, SherpaOnnx.swift, SherpaOnnx-Bridging-Header.h"
echo ""
echo "Next — in project.yml under the MediaDler target:"
echo "  1) Uncomment the two sherpa framework deps."
echo "  2) Add to sources:   - path: Vendor/sherpa-onnx/SherpaOnnx.swift"
echo "  3) Add to settings.base:"
echo "       SWIFT_ACTIVE_COMPILATION_CONDITIONS: \"\$(inherited) SHERPA_ONNX_ENABLED\""
echo "       SWIFT_OBJC_BRIDGING_HEADER: Vendor/sherpa-onnx/SherpaOnnx-Bridging-Header.h"
echo "       OTHER_LDFLAGS: \"\$(inherited) -lc++\""
echo "  4) make project   # regenerate"
echo ""
echo "Verify the model file names match SherpaModelManager.SherpaModelSpec after"
echo "the first model downloads (sherpa release layouts occasionally change)."
