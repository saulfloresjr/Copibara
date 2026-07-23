import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Shared services that persist independently of SwiftUI view lifecycle.
/// Initialized once at app launch, not when the MenuBarExtra panel opens.
final class CopibaraServices: ObservableObject {
    static let shared = CopibaraServices()

    let store = CopibaraStore()
    var monitor: CopibaraMonitor?
    var hotkeyService: HotkeyService?
    var forageHotkeyService: HotkeyService?
    var tildeService: TildeScreenshotService?
    var floatingPanel: FloatingPanel?

    /// The app that was frontmost before we showed the menu bar / picker.
    var previousApp: NSRunningApplication?

    /// Whether services have been started.
    private var isStarted = false

    func startAll(togglePicker: @escaping () -> Void) {
        guard !isStarted else { return }
        isStarted = true

        // 1. Accessibility — prompt immediately if not trusted
        if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // 2. Clipboard monitor
        let m = CopibaraMonitor(store: store)
        m.start()
        monitor = m

        // 3. Global hotkey (⌘⇧V)
        let hotkey = HotkeyService(handler: togglePicker)
        hotkey.register()
        hotkeyService = hotkey

        // 4. Forage mode toggle (⌘⇧F) + auto-arm watcher
        let forageHotkey = HotkeyService(
            keycode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(cmdKey | shiftKey),
            id: 2
        ) {
            MainActor.assumeIsolated { ForageMode.shared.toggle() }
        }
        forageHotkey.register()
        forageHotkeyService = forageHotkey
        MainActor.assumeIsolated { ForageMode.shared.startWatching() }

        // 5. Tilde long-press screenshot
        let tilde = TildeScreenshotService()
        tilde.start()
        tildeService = tilde

        // 6. Track previously-active app for paste-back
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.previousApp = app
            }
        }

        print("[Copibara] All services started. AXIsProcessTrusted: \(AXIsProcessTrusted())")
    }
}

@main
struct CopibaraApp: App {
    private var services: CopibaraServices { CopibaraServices.shared }

    init() {
        // Start all services immediately at app launch via next run-loop tick.
        // This fires before the user interacts with anything.
        DispatchQueue.main.async {
            CopibaraServices.shared.startAll(togglePicker: {
                CopibaraApp.sharedTogglePicker()
            })
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: services.store, onPasteItem: { item in
                pasteItem(item)
            })
        } label: {
            MenuBarLabel(forage: ForageMode.shared)
        }
        .menuBarExtraStyle(.window)
    }

    /// The menu bar icon, which doubles as the Forage-mode indicator.
    ///
    /// Reading `forage.isArmed` inside a view body is what makes the icon swap live —
    /// Observation tracks the access and re-renders the label when it flips.
    private struct MenuBarLabel: View {
        var forage: ForageMode

        var body: some View {
            Image(nsImage: forage.isArmed ? CopibaraApp.menuBarIconArmed : CopibaraApp.menuBarIcon)
        }
    }

    /// Armed variant: the same capybara, tinted green with a filled dot.
    ///
    /// Deliberately *not* a template image — template icons get force-tinted to match
    /// the menu bar, which is exactly what we don't want here. Colour is the whole
    /// point: armed has to be unmistakable at a glance, in both light and dark bars.
    static let menuBarIconArmed: NSImage = {
        let base = CopibaraApp.menuBarIcon
        let size = NSSize(width: 22, height: 20)
        let image = NSImage(size: size)
        let accent = NSColor(calibratedRed: 0.29, green: 0.71, blue: 0.36, alpha: 1.0)  // forage green

        image.lockFocus()
        // Tint the silhouette by masking the accent colour through it.
        let iconRect = NSRect(x: 0, y: 0, width: 20, height: 20)
        base.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        accent.set()
        iconRect.fill(using: .sourceAtop)

        // Status dot, top-right.
        let dot = NSBezierPath(ovalIn: NSRect(x: 16, y: 13, width: 6, height: 6))
        accent.setFill()
        dot.fill()
        image.unlockFocus()

        image.isTemplate = false
        return image
    }()

    /// Menu bar icon — a capybara hugging a clipboard, from the brand asset
    /// `assets/brand/taskbar-icon-1.png` processed into a monochrome template PNG (white
    /// background and clipboard interior made transparent). Set as a template image so
    /// macOS tints it for light/dark menu bars automatically (like Ollama's llama).
    /// Embedded as base64 so it works identically in `swift run` and the .app bundle,
    /// with no SPM resource plumbing or build.sh changes.
    static let menuBarIcon: NSImage = {
        let base64 = "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"
        let img = Data(base64Encoded: base64).flatMap { NSImage(data: $0) }
            ?? NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Copibara")!
        img.size = NSSize(width: 20, height: 20)
        img.isTemplate = true
        return img
    }()

    // MARK: - Picker

    /// Static toggle so it can be called from the init() closure.
    static func sharedTogglePicker() {
        let services = CopibaraServices.shared

        // If panel is already visible, dismiss it
        if let panel = services.floatingPanel, panel.isVisible {
            panel.dismiss()
            return
        }

        // Remember which app is currently frontmost BEFORE we activate ourselves.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            services.previousApp = front
        }

        // Create a new picker view + panel
        let pickerView = CopibaraPickerView(
            store: services.store,
            onSelect: { item in
                sharedPasteItem(item)
            },
            onSelectMultiple: { items in
                sharedPasteItems(items)
            },
            onDismiss: {
                services.floatingPanel?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: pickerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 400)

        let panel = FloatingPanel(contentView: hostingView)
        services.floatingPanel = panel
        panel.showAtCursor()
    }

    private func togglePicker() {
        CopibaraApp.sharedTogglePicker()
    }

    /// Paste the selected item's content into the previously active app.
    static func sharedPasteItem(_ item: CopibaraItem) {
        let services = CopibaraServices.shared

        print("[Copibara] pasteItem called — type: \(item.type), previousApp: \(services.previousApp?.localizedName ?? "nil")")

        // 1. Pause the copibara monitor so it doesn't re-capture
        //    the content we're about to put on the clipboard.
        services.monitor?.stop()

        // 2. Put the content onto the system clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let fileName = item.imageFileName {
            let fileURL = services.store.imagesDir.appendingPathComponent(fileName)
            if let imageData = try? Data(contentsOf: fileURL) {
                pasteboard.setData(imageData, forType: .png)
                print("[Copibara] Image placed on clipboard: \(fileName)")
            }
        } else {
            pasteboard.setString(item.content, forType: .string)
            print("[Copibara] Text placed on clipboard (\(item.content.prefix(50))...)")
        }

        // 3. Dismiss floating picker (if open) AND close menu bar window
        services.floatingPanel?.dismiss()
        services.floatingPanel = nil
        // Close the MenuBarExtra window so it doesn't stay open
        NSApp.keyWindow?.close()

        // 4. Check accessibility before attempting to simulate paste
        let isTrusted = AXIsProcessTrusted()
        print("[Copibara] AXIsProcessTrusted: \(isTrusted)")

        // 5. Reactivate the previous app, then simulate ⌘V after it gains focus.
        let targetApp = services.previousApp

        // Deactivate ourselves and immediately activate the target app
        NSApp.deactivate()

        // Give the system time to process the window close and focus switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            targetApp?.activate()
            print("[Copibara] Activated target app: \(targetApp?.localizedName ?? "nil")")

            // Wait for the target app to fully gain focus before pasting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if isTrusted {
                    simulatePaste()
                    print("[Copibara] ⌘V simulated")
                } else {
                    print("[Copibara] ⚠️ Cannot simulate paste — Accessibility not granted. Content is on clipboard, use ⌘V manually.")
                }

                // Resume copibara monitor after paste completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    services.monitor?.start()
                }
            }
        }
    }

    private func pasteItem(_ item: CopibaraItem) {
        CopibaraApp.sharedPasteItem(item)
    }

    /// Paste several items into the previously active app — e.g. dropping multiple
    /// screenshots into a chat input. Most apps only ingest one image per ⌘V, so this
    /// fires a tight sequence of pastes. Payloads are pre-resolved off the timed loop
    /// and the gap is kept small so it feels close to instant.
    static func sharedPasteItems(_ items: [CopibaraItem]) {
        guard !items.isEmpty else { return }
        let services = CopibaraServices.shared

        services.monitor?.stop()
        services.floatingPanel?.dismiss()
        services.floatingPanel = nil
        NSApp.keyWindow?.close()

        // Pre-resolve each item's clipboard payload so the timed loop never hits disk.
        enum Payload { case image(Data); case text(String) }
        var payloads = [Payload]()
        for item in items {
            if let fileName = item.imageFileName {
                let url = services.store.imagesDir.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: url) { payloads.append(.image(data)) }
            } else if !item.content.isEmpty {
                payloads.append(.text(item.content))
            }
        }
        guard !payloads.isEmpty else { services.monitor?.start(); return }

        let isTrusted = AXIsProcessTrusted()
        let targetApp = services.previousApp
        NSApp.deactivate()

        let leadIn = 0.15      // hand focus back to the target app
        let interval = 0.15    // tight gap between pastes
        let pasteboard = NSPasteboard.general

        DispatchQueue.main.asyncAfter(deadline: .now() + leadIn - 0.05) {
            targetApp?.activate()
        }
        for (i, payload) in payloads.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + leadIn + Double(i) * interval) {
                pasteboard.clearContents()
                switch payload {
                case .image(let data): pasteboard.setData(data, forType: .png)
                case .text(let text):  pasteboard.setString(text, forType: .string)
                }
                if isTrusted { CopibaraApp.simulatePaste() }
            }
        }

        let done = leadIn + Double(payloads.count) * interval + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + done) {
            services.monitor?.start()
            print("[Copibara] multi-paste: \(payloads.count) item(s) done")
        }
    }

    /// Simulate ⌘V using CGEvent to paste clipboard contents.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
