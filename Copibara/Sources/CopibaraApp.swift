import SwiftUI
import AppKit

/// Shared services that persist independently of SwiftUI view lifecycle.
/// Initialized once at app launch, not when the MenuBarExtra panel opens.
final class CopibaraServices: ObservableObject {
    static let shared = CopibaraServices()

    let store = CopibaraStore()
    var monitor: CopibaraMonitor?
    var hotkeyService: HotkeyService?
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

        // 4. Tilde long-press screenshot
        let tilde = TildeScreenshotService()
        tilde.start()
        tildeService = tilde

        // 5. Track previously-active app for paste-back
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
        MenuBarExtra("Copibara", systemImage: "clipboard") {
            ContentView(store: services.store, onPasteItem: { item in
                pasteItem(item)
            })
        }
        .menuBarExtraStyle(.window)
    }

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
