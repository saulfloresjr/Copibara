import AppKit
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins

/// How far to enlarge.
enum UpscaleMode {
    /// Exactly 2× — one model pass.
    case times2
    /// Exactly 4× — two model passes.
    case times4
    /// Keep running model passes until the long edge reaches `target`, then do a
    /// small final resample. This is the one for "make my tray icon shareable":
    /// it front-loads real detail and leaves interpolation almost nothing to do.
    case fit(CGFloat)

    var label: String {
        switch self {
        case .times2:     return "2×"
        case .times4:     return "4×"
        case .fit(let t): return "\(Int(t))px"
        }
    }
}

/// On-device super-resolution for small captures — tray icons, UI elements, logos.
///
/// Uses a bundled waifu2x Core ML model trained on illustration/flat art, which
/// makes it strong on icons and lettering (hard edges, flat colour) and weaker on
/// photographs. That's the intended trade: large photo captures already have enough
/// pixels to work with.
///
/// Specifically the *scale2x* variant, with no denoising. waifu2x also ships
/// noise0–noise3 models that denoise while they upscale, and we shipped noise1 at
/// first — but screenshots are lossless PNGs with no noise to remove, so that
/// denoising had nothing to do except smooth away real edges. Side by side on a
/// menu bar icon, scale2x keeps eyes and lettering distinct where noise1 mushes
/// them together. If a source ever *is* compressed (a re-shared JPEG), the noise
/// variants would suit it better.
///
/// waifu2x model © 2018 Yi Xie (MIT) — github.com/imxieyi/waifu2x-mac.
/// See THIRD_PARTY_LICENSES.md.
enum AIUpscaler {

    /// Default long edge for `.fit` — comfortable for social posts.
    static let defaultTarget: CGFloat = 1024

    // Model geometry: a 156px input tile carries a 7px context border around 142px
    // of real content, and produces 284px of output (142 × 2).
    private static let content = 142
    private static let inputSize = 156
    private static let outputSize = 284
    private static let shrink = 7
    /// waifu2x's input normalisation offset.
    private static let clipEta: Float = 0.00196

    /// Don't run model passes on images already this large — tile count and memory
    /// climb fast, and big captures aren't the problem being solved here.
    private static let maxAIEdge = 1600
    /// Hard stop on chained passes so `.fit` can't loop away.
    private static let maxPasses = 5

    // MARK: - Entry point

    /// Upscale image data and return a PNG, or nil on failure.
    /// `progress` is called on the calling queue with a short status string.
    static func upscaledPNG(
        from imageData: Data,
        mode: UpscaleMode = .fit(defaultTarget),
        progress: ((String) -> Void)? = nil
    ) -> Data? {
        guard let nsImage = NSImage(data: imageData),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              var bitmap = Bitmap(cg) else { return nil }

        var passes: Int
        var finalTarget: CGFloat?

        switch mode {
        case .times2:
            passes = 1
        case .times4:
            passes = 2
        case .fit(let target):
            finalTarget = target
            var edge = CGFloat(max(bitmap.w, bitmap.h))
            var n = 0
            // Double while we're still short of the target. Overshooting and
            // resampling down beats undershooting and stretching up: the model adds
            // detail, Lanczos can only spread what's already there.
            while n < maxPasses, edge < target, Int(edge) <= maxAIEdge {
                edge *= 2
                n += 1
            }
            passes = n
        }

        for pass in 0..<passes {
            guard max(bitmap.w, bitmap.h) <= maxAIEdge else {
                progress?("Already large — resampling only")
                break
            }
            progress?(passes > 1 ? "Enhancing… \(pass + 1)/\(passes)" : "Enhancing…")
            guard let doubled = double(bitmap) else { break }
            bitmap = doubled
        }

        guard let out = bitmap.cgImage() else { return nil }

        if let target = finalTarget {
            return resample(out, toLongEdge: target)
        }
        return png(out)
    }

    // MARK: - One tiled 2× pass

    private static let model: MLModel? = {
        guard let url = Bundle.module.url(forResource: "waifu2x-anime-scale2x", withExtension: "mlmodel"),
              let compiled = try? MLModel.compileModel(at: url) else {
            print("[AIUpscaler] model not found in bundle")
            return nil
        }
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

    /// Double a bitmap by running every 142×142 content tile through the model.
    ///
    /// Tiles need no overlap blending: the 7px border baked into the 156px input is
    /// exactly the context the network wants, so adjacent outputs abut seamlessly.
    private static func double(_ src: Bitmap) -> Bitmap? {
        guard let model else { return nil }
        guard let input = try? MLMultiArray(shape: [3, 156, 156], dataType: .float32) else { return nil }
        let ip = input.dataPointer.assumingMemoryBound(to: Float.self)

        let outW = src.w * 2, outH = src.h * 2
        var dst = Bitmap(w: outW, h: outH, hasAlpha: src.hasAlpha)

        let tilesX = (src.w + content - 1) / content
        let tilesY = (src.h + content - 1) / content

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let ox = tx * content, oy = ty * content

                // Fill the 156×156 input, edge-clamping outside the image.
                for c in 0..<3 {
                    let plane = c * inputSize * inputSize
                    for y in 0..<inputSize {
                        let sy = min(max(oy + y - shrink, 0), src.h - 1)
                        let row = plane + y * inputSize
                        for x in 0..<inputSize {
                            let sx = min(max(ox + x - shrink, 0), src.w - 1)
                            ip[row + x] = src.rgb[(sy * src.w + sx) * 3 + c] + clipEta
                        }
                    }
                }

                guard let result = try? model.prediction(from: Input(input)),
                      let out = result.featureValue(for: "conv7")?.multiArrayValue else { return nil }

                // Copy this tile's output into place, clipped to the real output size.
                let dx = ox * 2, dy = oy * 2
                let copyW = min(outputSize, outW - dx)
                let copyH = min(outputSize, outH - dy)
                guard copyW > 0, copyH > 0 else { continue }

                out.readingFloats { value in
                    for c in 0..<3 {
                        let plane = c * outputSize * outputSize
                        for y in 0..<copyH {
                            let srcRow = plane + y * outputSize
                            let dstRow = (dy + y) * outW
                            for x in 0..<copyW {
                                dst.rgb[(dstRow + dx + x) * 3 + c] =
                                    min(max(value(srcRow + x), 0), 1)
                            }
                        }
                    }
                }
            }
        }

        // The model is RGB-only, so alpha scales separately. Bilinear is plenty for a
        // 2× step and keeps cutout edges (Remove Background output) clean.
        if src.hasAlpha {
            for y in 0..<outH {
                let fy = (Float(y) + 0.5) / 2 - 0.5
                let y0 = max(Int(fy.rounded(.down)), 0), y1 = min(y0 + 1, src.h - 1)
                let wy = fy - Float(y0)
                for x in 0..<outW {
                    let fx = (Float(x) + 0.5) / 2 - 0.5
                    let x0 = max(Int(fx.rounded(.down)), 0), x1 = min(x0 + 1, src.w - 1)
                    let wx = fx - Float(x0)
                    let a00 = src.alpha[y0 * src.w + x0], a10 = src.alpha[y0 * src.w + x1]
                    let a01 = src.alpha[y1 * src.w + x0], a11 = src.alpha[y1 * src.w + x1]
                    let top = a00 + (a10 - a00) * wx
                    let bot = a01 + (a11 - a01) * wx
                    dst.alpha[y * outW + x] = top + (bot - top) * wy
                }
            }
        }

        return dst
    }

    // MARK: - Final resample

    private static func resample(_ cg: CGImage, toLongEdge target: CGFloat) -> Data? {
        let longEdge = CGFloat(max(cg.width, cg.height))
        let scale = target / longEdge
        // Already there (within 1%) — leave the pixels alone.
        guard abs(scale - 1) > 0.01 else { return png(cg) }

        let source = CIImage(cgImage: cg)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = source
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1.0
        guard let scaled = lanczos.outputImage else { return png(cg) }

        // Only sharpen when stretching UP. Downsampling from a model pass is already
        // crisp, and unsharp there just adds crunch.
        let finished: CIImage
        if scale > 1 {
            let sharpen = CIFilter.unsharpMask()
            sharpen.inputImage = scaled
            sharpen.radius = 1.0
            sharpen.intensity = 0.3
            finished = (sharpen.outputImage ?? scaled).cropped(to: scaled.extent)
        } else {
            finished = scaled
        }

        let context = CIContext()
        guard let out = context.createCGImage(finished, from: scaled.extent) else { return png(cg) }
        return png(out)
    }

    private static func png(_ cg: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

// MARK: - Float bitmap

/// Working image kept in float RGB + alpha, so chained passes don't re-quantise to
/// 8-bit between every step.
private struct Bitmap {
    var rgb: [Float]      // w*h*3, 0…1, straight (un-premultiplied)
    var alpha: [Float]    // w*h, 0…1
    let w: Int
    let h: Int
    let hasAlpha: Bool

    init(w: Int, h: Int, hasAlpha: Bool) {
        self.w = w; self.h = h; self.hasAlpha = hasAlpha
        rgb = [Float](repeating: 0, count: w * h * 3)
        alpha = [Float](repeating: 1, count: hasAlpha ? w * h : 0)
    }

    init?(_ cg: CGImage) {
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &raw, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var transparent = false
        for i in stride(from: 3, to: raw.count, by: 4) where raw[i] != 255 {
            transparent = true
            break
        }

        w = width; h = height; hasAlpha = transparent
        rgb = [Float](repeating: 0, count: width * height * 3)
        alpha = [Float](repeating: 1, count: transparent ? width * height : 0)

        for i in 0..<(width * height) {
            let a = Float(raw[i * 4 + 3]) / 255
            // Un-premultiply so the model sees true colour, rather than colour faded
            // toward black wherever the image is semi-transparent.
            let inv: Float = a > 0.0001 ? 1 / a : 0
            for c in 0..<3 {
                rgb[i * 3 + c] = min(Float(raw[i * 4 + c]) / 255 * inv, 1)
            }
            if transparent { alpha[i] = a }
        }
    }

    func cgImage() -> CGImage? {
        var raw = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let a = hasAlpha ? min(max(alpha[i], 0), 1) : 1
            for c in 0..<3 {
                let v = min(max(rgb[i * 3 + c], 0), 1) * a   // re-premultiply
                raw[i * 4 + c] = UInt8(v * 255 + 0.5)
            }
            raw[i * 4 + 3] = UInt8(a * 255 + 0.5)
        }
        guard let ctx = CGContext(
            data: &raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (hasAlpha ? CGImageAlphaInfo.premultipliedLast
                                  : CGImageAlphaInfo.noneSkipLast).rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}

// MARK: - MLMultiArray reader

private extension MLMultiArray {
    /// Read values whether the model emits float32 or double.
    func readingFloats<R>(_ body: ((Int) -> Float) -> R) -> R {
        switch dataType {
        case .float32:
            let p = dataPointer.assumingMemoryBound(to: Float.self)
            return body { p[$0] }
        default:
            let p = dataPointer.assumingMemoryBound(to: Double.self)
            return body { Float(p[$0]) }
        }
    }
}
