import XCTest
import SwiftUI
@testable import Copibara

/// Renders the real tray window and ⌘⇧V picker off-screen to PNGs, so UI changes can
/// be checked without opening anything on the desktop.
/// Opt-in: `COPIBARA_SNAPSHOT_DIR=/some/folder swift test --filter SnapshotTests`.
final class SnapshotTests: XCTestCase {

    @MainActor
    func testRenderTrayAndPicker() throws {
        guard let out = ProcessInfo.processInfo.environment["COPIBARA_SNAPSHOT_DIR"] else {
            throw XCTSkip("set COPIBARA_SNAPSHOT_DIR to render snapshots")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)   // no Dock icon, no focus steal
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("copibara-snapshots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CopibaraStore(directory: dir)   // demo clips, never the real history

        render(ContentView(store: store), size: NSSize(width: 720, height: 520), to: "\(out)/tray.png")

        // The picker reads its S/M/L preset from defaults; render each, then restore.
        let saved = UserDefaults.standard.string(forKey: "pickerSize")
        defer { UserDefaults.standard.set(saved, forKey: "pickerSize") }
        for size in PickerSize.allCases {
            UserDefaults.standard.set(size.rawValue, forKey: "pickerSize")
            render(CopibaraPickerView(store: store, onSelect: { _ in }, onDismiss: {}),
                   size: NSSize(width: size.width, height: size.height),
                   to: "\(out)/picker-\(size.label).png")
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, size: NSSize, to path: String) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -8000, y: -8000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}
