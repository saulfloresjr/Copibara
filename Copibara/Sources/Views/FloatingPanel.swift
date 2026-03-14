import AppKit
import SwiftUI

/// A borderless, floating NSPanel for the copibara picker.
/// Appears above all windows. Requires app activation for SwiftUI keyboard events.
final class FloatingPanel: NSPanel {

    /// The cursor position when the picker was invoked — used as the anchor
    /// for all resize operations so the panel always emanates from the cursor.
    private var cursorOrigin: NSPoint = .zero

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        self.contentView = contentView
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        // Don't auto-hide — we manage dismissal ourselves via Escape / onSelect
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Round corners
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }

    /// Show the panel near the mouse cursor, using the persisted picker size.
    func showAtCursor() {
        // Read the persisted picker size so we position correctly for M/L
        let sizeRaw = UserDefaults.standard.string(forKey: "pickerSize") ?? "compact"
        let pickerSize: NSSize
        switch sizeRaw {
        case "regular": pickerSize = NSSize(width: 420, height: 520)
        case "large":   pickerSize = NSSize(width: 520, height: 640)
        default:        pickerSize = NSSize(width: 340, height: 400)
        }

        // Resize the panel to match the persisted size BEFORE positioning
        setContentSize(pickerSize)

        // Save the cursor origin — this is the anchor for all future resizes
        cursorOrigin = NSEvent.mouseLocation

        let origin = computeOrigin(for: pickerSize)
        setFrameOrigin(origin)

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        orderOut(nil)
    }

    /// Resize the panel, recomputing position relative to the original cursor origin
    /// so the picker always emanates from where the cursor was.
    func repositionOnScreen(newSize: NSSize) {
        setContentSize(newSize)
        let origin = computeOrigin(for: newSize)
        setFrame(NSRect(origin: origin, size: newSize), display: true, animate: true)
    }

    // MARK: - Private

    /// Compute the panel origin so it hangs just below the cursor origin,
    /// clamped to screen bounds.
    private func computeOrigin(for size: NSSize) -> NSPoint {
        // Panel top-left aligns near the cursor; panel extends downward and to the right.
        var origin = NSPoint(
            x: cursorOrigin.x - 20,
            y: cursorOrigin.y - size.height - 8
        )

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return origin }
        let s = screen.visibleFrame

        // Right edge
        if origin.x + size.width > s.maxX {
            origin.x = s.maxX - size.width - 8
        }
        // Left edge
        if origin.x < s.minX {
            origin.x = s.minX + 8
        }
        // Bottom edge — flip above cursor if needed
        if origin.y < s.minY {
            origin.y = cursorOrigin.y + 12
        }
        // Top edge
        if origin.y + size.height > s.maxY {
            origin.y = s.maxY - size.height - 8
        }

        return origin
    }

    // Allow the panel to become key so it can receive keyboard input
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
