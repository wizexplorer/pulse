import AppKit
import ImageIO

/// Downsampled image loading. Full-resolution clipboard images are never decoded into memory:
/// ImageIO decodes straight to the requested size, and results are kept in a small bounded cache.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()
    private let queue = DispatchQueue(label: "Pulse.Thumbnails", qos: .userInitiated, attributes: .concurrent)

    func cached(_ url: URL, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: key(url, maxPixelSize))
    }

    /// Boxes the decoded image across the queue hop; NSImage is immutable once created here.
    private struct Loaded: @unchecked Sendable { let image: NSImage? }

    @MainActor
    func load(_ url: URL, maxPixelSize: Int) async -> NSImage? {
        if let image = cached(url, maxPixelSize: maxPixelSize) { return image }
        let loaded: Loaded = await withCheckedContinuation { continuation in
            queue.async { [self] in
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                ]
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: Loaded(image: nil))
                    return
                }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                cache.setObject(image, forKey: key(url, maxPixelSize))
                continuation.resume(returning: Loaded(image: image))
            }
        }
        return loaded.image
    }

    private func key(_ url: URL, _ size: Int) -> NSString {
        "\(url.lastPathComponent)@\(size)" as NSString
    }
}
