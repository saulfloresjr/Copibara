import AppKit
import ImageIO

/// Loads downscaled thumbnails from files with ImageIO, through a shared bounded cache.
///
/// Two problems this solves:
/// 1. **Full-res decode** — the grid/picker show small thumbnails but loading the whole
///    screenshot decodes tens of MB. `CGImageSourceCreateThumbnailAtIndex` decodes only
///    to `maxPixel`.
/// 2. **Unbounded accumulation** — thumbnails were cached in each card's `@State` with no
///    eviction, so scrolling thousands of image clips piled up gigabytes. Now they live
///    in one shared `NSCache` with a cost ceiling, so total thumbnail memory is capped no
///    matter how far you scroll; the OS evicts the least-recently-used under pressure.
///
/// Decoding is done off the main thread (`loadAsync`) so scrolling never blocks the UI —
/// which also fixes the transient half-rendered paint that a synchronous main-thread
/// decode caused.
enum ImageThumbnail {

    /// ~150 MB of thumbnails, then least-recently-used are evicted. A hard ceiling on the
    /// image memory the history can consume.
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.path)@\(maxPixel)" as NSString
    }

    /// Cached thumbnail, decoding on a miss. Synchronous — prefer `loadAsync` from views
    /// so the decode never lands on the main thread.
    static func load(_ url: URL, maxPixel: Int) -> NSImage? {
        let k = key(url, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: k, cost: cg.width * cg.height * 4)
        return image
    }

    /// Off-main load. Cache hits return immediately; misses decode on a utility queue.
    static func loadAsync(_ url: URL, maxPixel: Int) async -> NSImage? {
        if let hit = cache.object(forKey: key(url, maxPixel)) { return hit }
        return await Task.detached(priority: .utility) { load(url, maxPixel: maxPixel) }.value
    }
}
