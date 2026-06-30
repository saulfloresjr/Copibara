import AppKit
import Vision
import CoreImage

/// Removes the background from an image, returning just the foreground subject(s) on a
/// transparent background — for art, animations, stickers, etc.
///
/// Uses Vision's `VNGenerateForegroundInstanceMaskRequest` (macOS 14+) — the same
/// on-device "lift subject from background" model as Preview/Photos. No bundled model,
/// no network.
enum SubjectExtractor {

    /// Cut the subject out of `imageData` and return a transparent-background PNG,
    /// or nil if no subject is found / the request fails.
    /// - Parameter cropped: trim the result tightly to the subject's bounds.
    static func cutout(from imageData: Data, cropped: Bool = true) -> Data? {
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            return nil
        }

        do {
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: cropped
            )
            let ci = CIImage(cvPixelBuffer: masked)
            let context = CIContext()
            guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
            return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }
}
