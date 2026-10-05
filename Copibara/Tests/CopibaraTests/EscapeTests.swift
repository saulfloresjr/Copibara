import XCTest
import SwiftUI
@testable import Copibara

/// Escape must close the tray in one press, and must never be swallowed by the tray
/// when it's aimed at another Copibara window (the ⌘⇧V picker).
/// Drives the real ContentView in an off-screen window with real key events.
final class EscapeTests: XCTestCase {

    private var dir: URL!
    private var tray: NSWindow!

    @MainActor
    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("copibara-escape-\(UUID().uuidString)", isDirectory: true)
        let store = CopibaraStore(directory: dir)
        // The real tray is a MenuBarExtra panel at the pop-up-menu level.
        tray = offscreenWindow(level: .popUpMenu, size: NSSize(width: 720, height: 520))
        tray.contentView = NSHostingView(rootView: ContentView(store: store))
        tray.orderFrontRegardless()
        pump(0.6)   // let onAppear install the key monitors
    }

    @MainActor
    override func tearDown() async throws {
        tray?.orderOut(nil)
        tray = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// With a type filter active (clicking Link/Image, or ⇧Tab), one Escape closes.
    @MainActor
    func testOneEscapeClosesTrayEvenWithAFilterActive() {
        press(keyCode: 48, shift: true, in: tray)   // ⇧Tab → Text filter
        press(keyCode: 53, in: tray)                // Escape
        XCTAssertFalse(tray.isVisible, "tray needed more than one Escape")
    }

    /// Escape aimed at the picker belongs to the picker — the tray (even hidden, with
    /// leftover state) must let it through untouched.
    @MainActor
    func testTrayDoesNotSwallowEscapeMeantForThePicker() {
        press(keyCode: 48, shift: true, in: tray)   // leave state behind in the tray
        tray.orderOut(nil)                          // tray closed, monitors still installed

        let picker = offscreenWindow(level: .floating, size: NSSize(width: 340, height: 400))
        picker.orderFrontRegardless()
        var pickerSawEscape = false
        let pickerMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.window === picker { pickerSawEscape = true; picker.orderOut(nil); return nil }
            return event
        }
        defer { pickerMonitor.map(NSEvent.removeMonitor) }

        press(keyCode: 53, in: picker)
        XCTAssertTrue(pickerSawEscape, "the tray swallowed the picker's Escape")
        XCTAssertFalse(picker.isVisible, "picker needed more than one Escape")
    }

    // MARK: - Helpers

    @MainActor
    private func offscreenWindow(level: NSWindow.Level, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = level
        window.isReleasedWhenClosed = false
        return window
    }

    /// Post a real key-down to `window` and let the app dispatch it, so local event
    /// monitors see it exactly as they would a keystroke.
    @MainActor
    private func press(keyCode: UInt16, shift: Bool = false, in window: NSWindow) {
        let chars = keyCode == 53 ? "\u{1b}" : "\t"
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: keyCode) else { return XCTFail("couldn't make key event") }
        NSApp.postEvent(event, atStart: false)
        while let next = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05),
                                         inMode: .default, dequeue: true) {
            NSApp.sendEvent(next)
        }
        pump(0.3)
    }

    @MainActor
    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
