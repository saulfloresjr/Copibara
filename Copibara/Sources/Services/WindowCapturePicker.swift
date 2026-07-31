import AppKit
import ScreenCaptureKit

/// "Say screenshot → pick a window → it's on the clipboard."
///
/// Two-step, stateful so an external driver (Yapivo, via the copibara:// URL scheme)
/// can run it hands-free:
///   1. `capture()` enumerates on-screen windows, grabs a thumbnail of each, and shows
///      a numbered grid overlay.
///   2. `select(n)` re-captures window n at full resolution and puts the PNG on the
///      clipboard — where Copibara's own monitor ingests it like any other capture.
///
/// The overlay is also fully usable by hand: number keys 1–9, click, or Esc. That's
/// what makes it testable without voice, and a decent affordance on its own.
///
/// On-device; needs Screen Recording permission (the first capture prompts).
@MainActor
final class WindowCapturePicker {
    static let shared = WindowCapturePicker()

    struct Candidate {
        let window: SCWindow
        let thumbnail: NSImage
        let appName: String
        let title: String
    }

    /// Cap so numbers stay single-digit and the grid stays readable.
    private static let maxWindows = 9

    private var overlay: NSWindow?
    private var candidates: [Candidate] = []
    private var status: ((String) -> Void)?

    var isPresenting: Bool { overlay != nil }

    // MARK: - Step 1: capture + present

    func capture(status: @escaping (String) -> Void = { _ in }) {
        // A second "capture" while the grid is up is a no-op, not a reset — avoids a
        // double trigger (voice + key) tearing down the overlay mid-selection.
        guard overlay == nil else { return }
        self.status = status
        status("Finding windows…")

        Task { @MainActor in
            do {
                let found = try await Self.enumerate()
                guard !found.isEmpty else {
                    status("No windows to capture")
                    return
                }
                candidates = found
                present(found)
                status("Say a number, or press 1–\(found.count)")
            } catch {
                status("Couldn't capture — grant Screen Recording in System Settings › Privacy")
            }
        }
    }

    // MARK: - Step 2: select → clipboard

    func select(_ n: Int) {
        guard overlay != nil, n >= 1, n <= candidates.count else { return }
        let cand = candidates[n - 1]
        let report = status
        close()

        Task { @MainActor in
            guard let full = try? await Self.captureImage(cand.window, maxLongEdge: nil),
                  let png = NSBitmapImageRep(cgImage: full).representation(using: .png, properties: [:]) else {
                report?("Couldn't capture that window")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            report?("\(cand.appName) → clipboard (\(full.width)×\(full.height))")
        }
    }

    func cancel() { close() }

    private func close() {
        overlay?.orderOut(nil)
        overlay = nil
        candidates = []
    }

    // MARK: - Window enumeration

    private static func enumerate() async throws -> [Candidate] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true)
        let ownPID = NSRunningApplication.current.processIdentifier

        let windows = content.windows
            .filter { w in
                w.isOnScreen &&
                w.windowLayer == 0 &&                       // normal windows, not menu bar / dock
                w.frame.width >= 120 && w.frame.height >= 80 &&
                w.owningApplication?.processID != ownPID && // never our own overlay/panel
                !(w.title ?? "").isEmpty
            }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .prefix(maxWindows)

        // Thumbnails in parallel — a handful of small captures, so this stays well
        // under a second rather than serialising ~9 round-trips to the capture server.
        return try await withThrowingTaskGroup(of: (Int, Candidate?).self) { group in
            for (i, w) in windows.enumerated() {
                group.addTask {
                    guard let cg = try? await captureImage(w, maxLongEdge: 480),
                          NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) != nil
                    else { return (i, nil) }
                    let cand = Candidate(
                        window: w,
                        thumbnail: NSImage(cgImage: cg, size: .zero),
                        appName: w.owningApplication?.applicationName ?? "Window",
                        title: w.title ?? "")
                    return (i, cand)
                }
            }
            var slots = [Candidate?](repeating: nil, count: windows.count)
            for try await (i, cand) in group { slots[i] = cand }
            return slots.compactMap { $0 }
        }
    }

    /// Capture one window. `maxLongEdge == nil` means full native resolution.
    private static func captureImage(_ window: SCWindow, maxLongEdge: CGFloat?) async throws -> CGImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let w = window.frame.width, h = window.frame.height
        let fit = maxLongEdge.map { min(1.0, $0 / max(w, h)) } ?? 1.0

        let config = SCStreamConfiguration()
        config.width = max(1, Int(w * fit * scale))
        config.height = max(1, Int(h * fit * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Overlay

    private func present(_ cands: [Candidate]) {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = WindowPickerView(frame: CGRect(origin: .zero, size: frame.size), candidates: cands)
        view.owner = self
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(view)
        overlay = win
    }
}

// MARK: - Overlay view

private final class WindowPickerView: NSView {
    weak var owner: WindowCapturePicker?
    private let candidates: [WindowCapturePicker.Candidate]
    private var cellRects: [CGRect] = []
    private var hovered: Int?

    init(frame: CGRect, candidates: [WindowCapturePicker.Candidate]) {
        self.candidates = candidates
        super.init(frame: frame)
        let tracking = NSTrackingArea(rect: frame, options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Layout — square-ish grid, single-digit friendly

    private func gridLayout() -> (cols: Int, rows: Int, cell: CGSize, origin: CGPoint, gap: CGFloat) {
        let n = candidates.count
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let gap: CGFloat = 28
        let margin: CGFloat = 80
        let availW = bounds.width - margin * 2 - gap * CGFloat(cols - 1)
        let availH = bounds.height - margin * 2 - gap * CGFloat(rows - 1)
        let cell = CGSize(width: availW / CGFloat(cols), height: availH / CGFloat(rows))
        let gridW = cell.width * CGFloat(cols) + gap * CGFloat(cols - 1)
        let gridH = cell.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        let origin = CGPoint(x: (bounds.width - gridW) / 2, y: (bounds.height - gridH) / 2)
        return (cols, rows, cell, origin, gap)
    }

    private func rebuildCellRects() {
        let l = gridLayout()
        cellRects = candidates.indices.map { i in
            let col = i % l.cols
            let row = i / l.cols
            // Top row first: AppKit y is bottom-up, so invert the row.
            let x = l.origin.x + CGFloat(col) * (l.cell.width + l.gap)
            let yTop = l.origin.y + CGFloat(l.rows - 1 - row) * (l.cell.height + l.gap)
            return CGRect(x: x, y: yTop, width: l.cell.width, height: l.cell.height)
        }
    }

    // MARK: Input

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = cellRects.firstIndex { $0.contains(p) }
        if idx != hovered { hovered = idx; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let idx = cellRects.firstIndex(where: { $0.contains(p) }) {
            owner?.select(idx + 1)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { owner?.cancel(); return }   // Esc
        if let s = event.charactersIgnoringModifiers, let n = Int(s), n >= 1, n <= candidates.count {
            owner?.select(n)
        }
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.72).setFill()
        bounds.fill()
        rebuildCellRects()

        for (i, cell) in cellRects.enumerated() {
            let cand = candidates[i]
            let isHover = hovered == i
            let accent = NSColor(calibratedRed: 0.0, green: 0.53, blue: 1.0, alpha: 1)

            // Card
            let card = cell.insetBy(dx: 0, dy: 0)
            let cardPath = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
            NSColor.white.withAlphaComponent(isHover ? 0.16 : 0.08).setFill()
            cardPath.fill()
            (isHover ? accent : NSColor.white.withAlphaComponent(0.18)).setStroke()
            cardPath.lineWidth = isHover ? 3 : 1
            cardPath.stroke()

            // Thumbnail, aspect-fit, leaving room for the label strip.
            let labelH: CGFloat = 34
            let thumbBox = CGRect(x: card.minX + 10, y: card.minY + labelH,
                                  width: card.width - 20, height: card.height - labelH - 12)
            drawThumbnail(cand.thumbnail, in: thumbBox)

            // Label
            let label = cand.title.isEmpty ? cand.appName : "\(cand.appName) — \(cand.title)"
            drawLabel(label, in: CGRect(x: card.minX + 12, y: card.minY + 8,
                                        width: card.width - 24, height: labelH - 8))

            // Number badge, top-left
            drawBadge("\(i + 1)", at: CGPoint(x: card.minX + 14, y: card.maxY - 14), accent: accent)
        }

        drawHint()
    }

    private func drawThumbnail(_ image: NSImage, in box: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let fit = min(box.width / size.width, box.height / size.height)
        let w = size.width * fit, h = size.height * fit
        let rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    private func drawLabel(_ text: String, in rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: style,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs)
    }

    private func drawBadge(_ text: String, at center: CGPoint, accent: NSColor) {
        let r: CGFloat = 17
        let circle = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
        let ts = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: center.x - ts.width / 2, y: center.y - ts.height / 2), withAttributes: attrs)
    }

    private func drawHint() {
        let hint = "Say a number  ·  1–\(candidates.count) to pick  ·  Esc to cancel"
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .paragraphStyle: style,
        ]
        let size = (hint as NSString).size(withAttributes: attrs)
        (hint as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: 40), withAttributes: attrs)
    }
}
