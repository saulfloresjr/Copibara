import AppKit
import Vision

/// Captures a scrolling screenshot by taking multiple frames of a window as the
/// user scrolls, then intelligently stitching them into one tall image using
/// Apple's Vision framework for overlap alignment.
///
/// **Flow**:
/// 1. `beginCapture()` — records the frontmost window and takes the first frame
/// 2. `captureFrame()` — called on each scroll tick while tilde is held
/// 3. `finishCapture()` — stitches all frames and copies result to clipboard
///
/// Uses `CGWindowListCreateImage` for per-frame capture and
/// `VNTranslationalImageRegistrationRequest` for sub-pixel overlap detection.
final class ScrollingCaptureEngine {

    // MARK: - State

    private var targetWindowID: CGWindowID = 0
    private var targetWindowBounds: CGRect = .zero
    private var frames: [CGImage] = []
    private var isCapturing = false

    /// Minimum time between frame captures to avoid flooding
    private let captureInterval: TimeInterval = 0.12
    private var lastCaptureTime: TimeInterval = 0

    /// Whether a scrolling capture is active
    var active: Bool { isCapturing }

    // MARK: - Public API

    /// Start a scrolling capture session targeting the frontmost window.
    /// Returns `true` if a valid window was found and the first frame captured.
    @discardableResult
    func beginCapture() -> Bool {
        // Find the frontmost application's main window
        guard let windowInfo = findFrontmostWindow() else {
            print("📸 ScrollingCapture: No frontmost window found")
            return false
        }

        targetWindowID = windowInfo.id
        targetWindowBounds = windowInfo.bounds
        frames.removeAll()
        isCapturing = true
        lastCaptureTime = 0

        // Take the first frame immediately
        if let frame = captureWindowImage() {
            frames.append(frame)
            print("📸 ScrollingCapture: Started — first frame captured (\(frame.width)x\(frame.height))")
        }

        return true
    }

    /// Capture the current state of the target window.
    /// Call this on each scroll event while tilde is held.
    func captureFrame() {
        guard isCapturing else { return }

        // Throttle captures
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now

        guard let frame = captureWindowImage() else { return }
        frames.append(frame)
        print("📸 ScrollingCapture: Frame \(frames.count) captured")
    }

    /// Finish the capture session: stitch frames and copy to clipboard.
    /// Returns `true` if a stitched image was produced.
    @discardableResult
    func finishCapture() -> Bool {
        guard isCapturing else { return false }
        isCapturing = false

        guard frames.count >= 2 else {
            // Only 1 frame — just copy it directly (regular screenshot)
            if let single = frames.first {
                copyToClipboard(cgImage: single)
                print("📸 ScrollingCapture: Single frame — copied to clipboard")
            }
            frames.removeAll()
            return frames.count == 1
        }

        print("📸 ScrollingCapture: Stitching \(frames.count) frames...")

        // Stitch on a background thread to avoid blocking
        let framesToStitch = frames
        frames.removeAll()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let stitched = self?.stitchFrames(framesToStitch) {
                DispatchQueue.main.async {
                    self?.copyToClipboard(cgImage: stitched)
                    print("📸 ScrollingCapture: Done — \(stitched.width)x\(stitched.height) copied to clipboard")
                }
            } else {
                print("📸 ScrollingCapture: Stitching failed — copying last frame")
                if let last = framesToStitch.last {
                    DispatchQueue.main.async {
                        self?.copyToClipboard(cgImage: last)
                    }
                }
            }
        }

        return true
    }

    /// Cancel without stitching
    func cancel() {
        isCapturing = false
        frames.removeAll()
        print("📸 ScrollingCapture: Cancelled")
    }

    // MARK: - Window Capture

    private struct WindowInfo {
        let id: CGWindowID
        let bounds: CGRect
    }

    private func findFrontmostWindow() -> WindowInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the largest on-screen window belonging to the frontmost app
        var best: WindowInfo?
        var bestArea: CGFloat = 0

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 100, h > 100 // ignore tiny auxiliary windows
            else { continue }

            let area = w * h
            if area > bestArea {
                bestArea = area
                best = WindowInfo(id: windowID, bounds: CGRect(x: x, y: y, width: w, height: h))
            }
        }

        return best
    }

    private func captureWindowImage() -> CGImage? {
        // Re-fetch bounds in case the window moved
        let options: CGWindowListOption = [.optionIncludingWindow]
        if let windowList = CGWindowListCopyWindowInfo(options, targetWindowID) as? [[String: Any]],
           let info = windowList.first,
           let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
           let x = boundsDict["X"],
           let y = boundsDict["Y"],
           let w = boundsDict["Width"],
           let h = boundsDict["Height"] {
            targetWindowBounds = CGRect(x: x, y: y, width: w, height: h)
        }

        return CGWindowListCreateImage(
            targetWindowBounds,
            .optionIncludingWindow,
            targetWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    // MARK: - Stitching with Vision Framework

    /// Stitch an array of overlapping frames into one tall image using
    /// Vision's `VNTranslationalImageRegistrationRequest` for alignment.
    private func stitchFrames(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }

        // Calculate the vertical offset between each consecutive pair
        var offsets: [CGFloat] = [0]  // first frame starts at y=0
        var cumulativeY: CGFloat = 0

        for i in 1..<frames.count {
            let prevFrame = frames[i - 1]
            let currFrame = frames[i]

            let yOffset = computeVerticalOffset(from: prevFrame, to: currFrame)

            // If the offset is tiny (< 5px), the user didn't actually scroll — skip this frame
            if abs(yOffset) < 5 {
                offsets.append(cumulativeY) // same position as previous
                continue
            }

            cumulativeY += yOffset
            offsets.append(cumulativeY)
        }

        // Deduplicate: remove frames with duplicate offsets
        var uniqueIndices: [Int] = [0]
        for i in 1..<offsets.count {
            if offsets[i] != offsets[i - 1] {
                uniqueIndices.append(i)
            }
        }

        guard uniqueIndices.count >= 2 else {
            // No actual scrolling detected — return the first frame
            return first
        }

        // Calculate total canvas size
        let width = CGFloat(first.width)
        let totalHeight = offsets[uniqueIndices.last!] + CGFloat(frames[uniqueIndices.last!].height)

        guard totalHeight > 0, totalHeight < 50000 else {
            // Sanity check — don't create absurdly large images
            print("📸 ScrollingCapture: Canvas too large (\(totalHeight)px height), aborting stitch")
            return frames.last
        }

        // Create the stitched canvas
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(totalHeight),
            bitsPerComponent: first.bitsPerComponent,
            bytesPerRow: 0,
            space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: first.bitmapInfo.rawValue
        ) else { return nil }

        // Draw each unique frame at its computed offset
        // CGContext has origin at bottom-left, so we flip Y
        for idx in uniqueIndices {
            let frame = frames[idx]
            let y = totalHeight - offsets[idx] - CGFloat(frame.height)
            context.draw(frame, in: CGRect(x: 0, y: y, width: CGFloat(frame.width), height: CGFloat(frame.height)))
        }

        return context.makeImage()
    }

    /// Use Vision framework to compute the vertical translation between two frames.
    /// Returns the number of pixels frame `to` is shifted down relative to `from`.
    private func computeVerticalOffset(from: CGImage, to: CGImage) -> CGFloat {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: to)

        let handler = VNImageRequestHandler(cgImage: from, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("📸 ScrollingCapture: Vision alignment failed — \(error.localizedDescription)")
            // Fallback: assume a fixed overlap (70% of frame height visible, 30% new)
            return CGFloat(from.height) * 0.3
        }

        guard let result = request.results?.first as? VNImageTranslationAlignmentObservation else {
            // No result — fallback to fixed overlap
            return CGFloat(from.height) * 0.3
        }

        // Vision reports the transform to align `to` onto `from`.
        // A downward scroll means `to` is shifted up, so ty is negative.
        // We want the positive distance scrolled.
        let ty = result.alignmentTransform.ty
        return abs(ty)
    }

    // MARK: - Clipboard

    private func copyToClipboard(cgImage: CGImage) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }
}
