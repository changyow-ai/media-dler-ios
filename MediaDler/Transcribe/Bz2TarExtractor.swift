import Foundation

// Fast, low-memory `.tar.bz2` extraction using system libbz2 (C) for the bzip2
// step — the pure-Swift decompressor was far too slow for 160MB+ model
// archives. Streams bz2 → a temp .tar on disk, then streams the tar into the
// destination, so neither the ~228MB decompressed tar nor any single model file
// is ever fully resident in memory.
//
// Gated by SHERPA_ONNX_ENABLED because the libbz2 symbols come via the sherpa
// bridging header (#import <bzlib.h>), which is only set when sherpa is wired in.

#if SHERPA_ONNX_ENABLED
enum Bz2TarError: LocalizedError {
    case bz2Init(Int32)
    case bz2Decompress(Int32)
    case truncated
    case io(String)

    var errorDescription: String? {
        switch self {
        case .bz2Init(let c): return "bzip2 初始化失敗（\(c)）"
        case .bz2Decompress(let c): return "bzip2 解壓失敗（\(c)）"
        case .truncated: return "壓縮檔不完整。"
        case .io(let m): return "解壓 IO 失敗：\(m)"
        }
    }
}

enum Bz2TarExtractor {
    /// Extracts `archive` (.tar.bz2) into `destDir`, stripping the leading
    /// `stripPrefix` path component from each entry. Only regular files are
    /// written.
    static func extract(archive: URL, into destDir: URL, stripPrefix: String) throws {
        let tmpTar = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".tar")
        defer { try? FileManager.default.removeItem(at: tmpTar) }
        try bunzip2(src: archive, dst: tmpTar)
        try untar(tar: tmpTar, into: destDir, stripPrefix: stripPrefix)
    }

    // MARK: bzip2 (system libbz2, streaming)

    private static func bunzip2(src: URL, dst: URL) throws {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: dst.path, contents: nil) else {
            throw Bz2TarError.io("無法建立暫存 tar")
        }
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }

        var stream = bz_stream()
        guard BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK else { throw Bz2TarError.bz2Init(-1) }
        defer { BZ2_bzDecompressEnd(&stream) }

        let outCap = 1 << 20
        var outBuf = [Int8](repeating: 0, count: outCap)
        var finished = false

        while !finished {
            let chunk = input.readData(ofLength: 1 << 20)
            if chunk.isEmpty { throw Bz2TarError.truncated }
            try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let base = UnsafeMutablePointer(mutating: raw.bindMemory(to: CChar.self).baseAddress)
                stream.next_in = base
                stream.avail_in = UInt32(chunk.count)
                while stream.avail_in > 0 {
                    var produced = 0
                    let ret: Int32 = outBuf.withUnsafeMutableBufferPointer { ob -> Int32 in
                        stream.next_out = ob.baseAddress
                        stream.avail_out = UInt32(outCap)
                        let r = BZ2_bzDecompress(&stream)
                        produced = outCap - Int(stream.avail_out)
                        return r
                    }
                    if produced > 0 {
                        output.write(Data(bytes: outBuf, count: produced))
                    }
                    if ret == BZ_STREAM_END { finished = true; break }
                    guard ret == BZ_OK else { throw Bz2TarError.bz2Decompress(ret) }
                }
            }
        }
    }

    // MARK: tar (ustar/gnu, streaming)

    private static func untar(tar: URL, into destDir: URL, stripPrefix: String) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destDir)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let handle = try FileHandle(forReadingFrom: tar)
        defer { try? handle.close() }

        while true {
            let header = handle.readData(ofLength: 512)
            if header.count < 512 { break }
            // Two consecutive zero blocks mark the end.
            if header.allSatisfy({ $0 == 0 }) { break }

            let name = tarString(header, 0, 100)
            let sizeStr = tarString(header, 124, 12)
            let size = Int(sizeStr.trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
            let typeFlag = header[156]

            let padded = (size + 511) / 512 * 512
            let isRegular = (typeFlag == 0x30 /* '0' */ || typeFlag == 0x00)

            if isRegular, !name.isEmpty {
                var rel = name
                if rel.hasPrefix(stripPrefix) { rel = String(rel.dropFirst(stripPrefix.count)) }
                if !rel.isEmpty && !rel.hasSuffix("/") {
                    let dest = destDir.appendingPathComponent(rel)
                    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    fm.createFile(atPath: dest.path, contents: nil)
                    let out = try FileHandle(forWritingTo: dest)
                    var remaining = size
                    while remaining > 0 {
                        let n = min(remaining, 1 << 20)
                        let data = handle.readData(ofLength: n)
                        if data.isEmpty { break }
                        out.write(data)
                        remaining -= data.count
                    }
                    try? out.close()
                    // Skip padding to the next 512 boundary.
                    if padded > size { _ = handle.readData(ofLength: padded - size) }
                } else {
                    if padded > 0 { _ = handle.readData(ofLength: padded) }
                }
            } else {
                if padded > 0 { _ = handle.readData(ofLength: padded) }
            }
        }
    }

    private static func tarString(_ data: Data, _ offset: Int, _ length: Int) -> String {
        let slice = data.subdata(in: offset..<min(offset + length, data.count))
        let bytes = slice.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
#endif
