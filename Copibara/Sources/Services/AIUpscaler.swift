import AppKit
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins

/// Upscales small screenshots for sharing. Uses a bundled waifu2x Core ML model
/// (anime/art-trained → ideal for icons) for a real-detail 2× pass on small images,
/// then a high-quality Lanczos scale up to the target size. On-device, no network.
///
/// waifu2x model © imxieyi (MIT) — github.com/imxieyi/waifu2x-mac.
enum AIUpscaler {

    /// Upscale until the longest edge reaches this (px), capped by Lanczos so we don't over-blur.
    static let targetLongEdge: CGFloat = 1024
    /// The waifu2x model input tile is 156 (142 content + 7 border) → single-tile up to 142px.
    private static let maxTile = 142

    /// Upscale image data and return a PNG, or nil on failure.
    static func upscaledPNG(from imageData: Data) -> Data? {
        guard let nsImage = NSImage(data: imageData),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // 1) waifu2x 2× real-detail pass for small captures (the pixelation case).
        var working = cg
        if cg.width <= maxTile, cg.height <= maxTile, let enhanced = waifu2x2x(cg) {
            working = enhanced
        }

        // 2) High-quality Lanczos to reach the target size (no-op if already big enough).
        return lanczosToTarget(working)
    }

    // MARK: - waifu2x single-tile 2× (verified preprocessing)

    private static let model: MLModel? = {
        guard let url = Bundle.module.url(forResource: "waifu2x-anime", withExtension: "mlmodel"),
              let compiled = try? MLModel.compileModel(at: url) else { return nil }
        return try? MLModel(contentsOf: compiled)
    }()

    private final class Input: MLFeatureProvider {
        let array: MLMultiArray
        init(_ a: MLMultiArray) { array = a }
        var featureNames: Set<String> { ["input"] }
        func featureValue(for name: String) -> MLFeatureValue? {
            name == "input" ? MLFeatureValue(multiArray: array) : nil
        }
    }

    private static func waifu2x2x(_ cg: CGImage) -> CGImage? {
        guard let model = model else { return nil }
        let W = cg.width, H = cg.height
        guard W <= maxTile, H <= maxTile, W > 0, H > 0 else { return nil }
        let shrink = 7, inSize = 156, outSize = 284
        let clip: Float = 0.00196

        var rgba = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &rgba, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        func px(_ x: Int, _ y: Int, _ c: Int) -> Float {
            let cx = min(max(x, 0), W - 1), cy = min(max(y, 0), H - 1)
            return Float(rgba[(cy * W + cx) * 4 + c]) / 255
        }

        guard let input = try? MLMultiArray(shape: [3, 156, 156], dataType: .float32) else { return nil }
        let ip = input.dataPointer.assumingMemoryBound(to: Float.self)
        for c in 0..<3 { for ey in 0..<inSize { for ex in 0..<inSize {
            ip[c * inSize * inSize + ey * inSize + ex] = px(ex - shrink, ey - shrink, c) + clip
        }}}

        guard let out = try? model.prediction(from: Input(input)).featureValue(for: "conv7")?.multiArrayValue else { return nil }
        let op = out.dataPointer.assumingMemoryBound(to: Double.self)

        let OW = W * 2, OH = H * 2
        var outRGBA = [UInt8](repeating: 255, count: OW * OH * 4)
        for oy in 0..<OH { for ox in 0..<OW { for c in 0..<3 {
            let v = op[c * outSize * outSize + oy * outSize + ox] * 255
            outRGBA[(oy * OW + ox) * 4 + c] = UInt8(min(max(v, 0), 255))
        }}}
        guard let octx = CGContext(data: &outRGBA, width: OW, height: OH, bitsPerComponent: 8,
                                   bytesPerRow: OW * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        return octx.makeImage()
    }

    // MARK: - Lanczos to target

    private static func lanczosToTarget(_ cg: CGImage) -> Data? {
        let source = CIImage(cgImage: cg)
        let longEdge = CGFloat(max(cg.width, cg.height))
        let scale = min(max(targetLongEdge / longEdge, 1.0), 4.0)

        let scaled: CIImage
        if scale > 1.001 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = source
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1.0
            scaled = lanczos.outputImage ?? source
        } else {
            scaled = source
        }
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = scaled
        sharpen.radius = 1.0
        sharpen.intensity = 0.3
        let result = (sharpen.outputImage ?? scaled).cropped(to: scaled.extent)

        let context = CIContext()
        guard let out = context.createCGImage(result, from: scaled.extent) else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}
