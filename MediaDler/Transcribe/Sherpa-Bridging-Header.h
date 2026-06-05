// Bridging header for the sherpa-onnx backend (M7), used only when the
// SHERPA_ONNX_ENABLED flag + vendored xcframeworks are wired in (see project.yml
// and scripts/fetch-sherpa-libs.sh). Exposes:
//   - the sherpa-onnx C API (consumed by the vendored SherpaOnnx.swift wrapper)
//   - system libbz2 (fast C bzip2) for streaming .tar.bz2 model extraction,
//     avoiding the slow pure-Swift decompressor.
#ifndef MEDIADLER_SHERPA_BRIDGING_HEADER_H_
#define MEDIADLER_SHERPA_BRIDGING_HEADER_H_

#import "sherpa-onnx/c-api/c-api.h"
#import <bzlib.h>

#endif
