import AppKit
import ImageIO

/// Loads a downscaled thumbnail straight from a file with ImageIO.
///
/// The grid and picker show ~80pt and ~48pt thumbnails, but were loading the full
/// screenshot via `NSImage(contentsOf:)` — which decodes the entire image into memory.
/// A single 3456×2234 capture is ~30 MB decoded; with thousands of image clips that's
/// hundreds of MB for pictures the size of a postage stamp.
///
/// `CGImageSourceCreateThumbnailAtIndex` decodes only enough to hit `maxPixel`, so a
/// thumbnail costs kilobytes instead of tens of megabytes.
enum ImageThumbnail {

    /// A small NSImage no larger than `maxPixel` on its long edge, or nil on failure.
    static func load(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
