import Foundation
import UIKit
import AVFoundation
import ImageIO

/// Generates a small local preview image for a downloaded file and stores it in
/// Documents/thumbnails/<id>.jpg. Works for both images (downsampled) and videos
/// (a frame near the start). Returns the saved path, or nil if it couldn't.
///
/// Must be called on the temp file *before* it is moved into Photos / deleted.
enum ThumbnailMaker {
    private static let maxPixel: CGFloat = 480

    static var dir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func path(for id: String) -> URL {
        dir.appendingPathComponent(id).appendingPathExtension("jpg")
    }

    @discardableResult
    static func make(from fileURL: URL, isImage: Bool, id: String) -> String? {
        guard let image = isImage ? downsampled(fileURL) : videoFrame(fileURL),
              let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let out = path(for: id)
        do {
            try data.write(to: out, options: .atomic)
            return out.path
        } catch {
            return nil
        }
    }

    static func remove(id: String) {
        try? FileManager.default.removeItem(at: path(for: id))
    }

    static func removeAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private static func downsampled(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func videoFrame(_ url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        // Aim ~1s in, but clamp to the clip's length so short clips still yield a frame.
        let duration = asset.duration.seconds
        let seconds = duration.isFinite && duration > 0 ? min(1, duration / 2) : 0
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}
