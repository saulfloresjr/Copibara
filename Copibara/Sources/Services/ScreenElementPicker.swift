import AppKit
import Vision
import ScreenCaptureKit
import CoreImage

/// "Grab an element from the screen": freezes the screen in a full-screen overlay,
/// highlights the foreground object under the cursor, and on click lifts just that
/// object onto a transparent background (for art / stickers / animation).
///
/// Pipeline: ScreenCaptureKit screenshot → Vision foreground-instance segmentation →
/// overlay with per-instance hover highlight → `generateMaskedImage` for the clicked
/// instance. On-device; needs Screen Recording permission (first capture prompts).
@MainActor
final class ScreenElementPicker {
    static let shared = ScreenElementPicker()

    private var window: NSWindow?
    private var status: ((String) -> Void)?
    private var completion: ((Data?) -> Void)?

    func start(status: @escaping (String) -> Void, completion: @escaping (Data?) -> Void) {
        guard window == nil else { return }
        self.status = status
        self.completion = completion
        status("Capturing screen…")

        Task { @MainActor in
            do {
                let shot = try await Self.captureMainDisplay()
                let model = try ElementSegmentation(cgImage: shot.image)
                if model.instanceCount == 0 {
                    status("No distinct elements found on screen")
                    finish(nil)
                    return
                }
                status("Click an element to grab it — Esc to cancel")
                presentOverlay(displayFrame: shot.displayFrame, model: model)
            } catch {
                status("Couldn't capture the screen. Grant Screen Recording in System Settings → Privacy.")
                finish(nil)
            }
        }
    }

    fileprivate func picked(_ data: Data?) {
        closeOverlay()
        finish(data)
    }

    fileprivate func cancelled() {
        closeOverlay()
        finish(nil)
    }

    private func finish(_ data: Data?) {
        completion?(data)
        completion = nil
        status = nil
    }

    // MARK: - Overlay

    private func presentOverlay(displayFrame: CGRect, model: ElementSegmentation) {
        let win = NSWindow(contentRect: displayFrame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true
        win.hasShadow = false

        let view = ElementPickerView(frame: CGRect(origin: .zero, size: displayFrame.size), model: model)
        view.owner = self
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(view)
        self.window = win
    }

    private func closeOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Screen capture

    private static func captureMainDisplay() async throws -> (image: CGImage, displayFrame: CGRect) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenElementPicker", code: 1)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, display.frame)
    }
}

// MARK: - Vision segmentation + per-instance lookup

/// Runs foreground-instance segmentation once and exposes: a fast "which instance is at
/// this image point" lookup (downscaled label map) and full-res extraction of one instance.
final class ElementSegmentation {
    let cgImage: CGImage
    private let handler: VNImageRequestHandler
    private let observation: VNInstanceMaskObservation
    private let instances: [Int]                 // instance indices (1-based per Vision)
    private let labelMap: [Int32]                // downscaled: index into `instances`, or -1
    private let labelW: Int
    private let labelH: Int

    var instanceCount: Int { instances.count }

    init(cgImage: CGImage) throws {
        self.cgImage = cgImage
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first else {
            throw NSError(domain: "ElementSegmentation", code: 1)
        }
        self.handler = handler
        self.observation = obs
        self.instances = obs.allInstances.map { $0 }

        // Build a downscaled label map for O(1) hover lookups.
        let maxDim = 1024
        let scale = min(1.0, CGFloat(maxDim) / CGFloat(max(cgImage.width, cgImage.height)))
        let lw = max(1, Int(CGFloat(cgImage.width) * scale))
        let lh = max(1, Int(CGFloat(cgImage.height) * scale))
        self.labelW = lw
        self.labelH = lh
        var map = [Int32](repeating: -1, count: lw * lh)

        let ciContext = CIContext()
        for (idx, inst) in instances.enumerated() {
            guard let maskBuffer = try? obs.generateScaledMaskForImage(forInstances: IndexSet([inst]), from: handler) else { continue }
            let ci = CIImage(cvPixelBuffer: maskBuffer)
            // Render mask to a small grayscale bitmap
            guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { continue }
            guard let bytes = Self.grayscaleBytes(from: cg, width: lw, height: lh) else { continue }
            for i in 0..<(lw * lh) where bytes[i] > 128 {
                map[i] = Int32(idx)  // later instances win (drawn on top)
            }
        }
        self.labelMap = map
    }

    /// Index into `instances` for an image-pixel point (top-left origin), or nil.
    func instanceIndex(atImagePoint p: CGPoint) -> Int? {
        let x = Int(p.x / CGFloat(cgImage.width) * CGFloat(labelW))
        let y = Int(p.y / CGFloat(cgImage.height) * CGFloat(labelH))
        guard x >= 0, x < labelW, y >= 0, y < labelH else { return nil }
        let label = labelMap[y * labelW + x]
        return label >= 0 ? Int(label) : nil
    }

    /// Transparent cutout PNG for the instance at `index`. `cropped` trims tightly to the
    /// element (for the saved result); uncropped is full-frame (used for the hover overlay).
    func cutoutPNG(forIndex index: Int, cropped: Bool = true) -> Data? {
        guard instances.indices.contains(index) else { return nil }
        guard let masked = try? observation.generateMaskedImage(
            ofInstances: IndexSet([instances[index]]), from: handler, croppedToInstancesExtent: cropped) else { return nil }
        let ci = CIImage(cvPixelBuffer: masked)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private static func grayscaleBytes(from cg: CGImage, width: Int, height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}

// MARK: - Overlay view

private final class ElementPickerView: NSView {
    weak var owner: ScreenElementPicker?
    private let model: ElementSegmentation
    private let screenImage: NSImage
    private var hoveredIndex: Int?

    init(frame: CGRect, model: ElementSegmentation) {
        self.model = model
        self.screenImage = NSImage(cgImage: model.cgImage, size: frame.size)
        super.init(frame: frame)
        let tracking = NSTrackingArea(rect: frame, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// Convert a view point (AppKit, bottom-left origin) to image pixel (top-left origin).
    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        let nx = viewPoint.x / bounds.width
        let ny = viewPoint.y / bounds.height
        return CGPoint(x: nx * CGFloat(model.cgImage.width),
                       y: (1 - ny) * CGFloat(model.cgImage.height))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = model.instanceIndex(atImagePoint: imagePoint(from: p))
        if idx != hoveredIndex { hoveredIndex = idx; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let idx = model.instanceIndex(atImagePoint: imagePoint(from: p)) else { return }
        let data = model.cutoutPNG(forIndex: idx)
        owner?.picked(data)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owner?.cancelled() }  // Esc
    }

    private var highlightCache: [Int: NSImage] = [:]

    /// Full-frame, un-dimmed cutout of an instance — makes the hovered element pop in place
    /// without any bounding-box math (it's drawn at `bounds`, aligned with the screen image).
    private func highlightImage(forIndex index: Int) -> NSImage? {
        if let cached = highlightCache[index] { return cached }
        guard let data = model.cutoutPNG(forIndex: index, cropped: false),
              let img = NSImage(data: data) else { return nil }
        highlightCache[index] = img
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        screenImage.draw(in: bounds)
        // Dim everything…
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
        // …then redraw the hovered element at full brightness so it pops.
        if let idx = hoveredIndex, let hi = highlightImage(forIndex: idx) {
            hi.draw(in: bounds)
        }
    }
}
