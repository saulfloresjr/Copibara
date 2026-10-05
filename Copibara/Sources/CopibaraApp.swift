import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Shared services that persist independently of SwiftUI view lifecycle.
/// Initialized once at app launch, not when the MenuBarExtra panel opens.
final class CopibaraServices: ObservableObject {
    static let shared = CopibaraServices()

    let store = CopibaraStore()
    var monitor: CopibaraMonitor?
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

        // 3. Global hotkey (⌘⇧V) — open the clip picker
        HotkeyCenter.shared.register(
            .picker,
            keycode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey),
            handler: togglePicker
        )

        // 3b. Global hotkey (⌃⌘V) — open the picker straight on Favorites.
        //     Deliberately not ⌘⇧B: browsers bind that to the bookmarks bar, and a
        //     Carbon hotkey would swallow it in the very app these links get pasted into.
        HotkeyCenter.shared.register(
            .favorites,
            keycode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | controlKey),
            handler: { CopibaraApp.sharedTogglePicker(board: BoardFilter.favorites) }
        )

        // 4. Forage mode auto-arm watcher.
        //    Its ⌘⇧F toggle is handled by the event tap below, not registered here,
        //    so editors keep their Find-in-Files. See Shortcuts.ownsForageChord().
        MainActor.assumeIsolated { ForageMode.shared.startWatching() }

        // 4b. copibara:// URL scheme — Yapivo's channel for hands-free window capture.
        URLSchemeHandler.shared.register()

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

        // 7. On quit, tell Yapivo the picker is gone if it was up. orderOut/deinit
        //    don't reliably run as the process exits, so post from the terminate hook.
        //    Force-quit (SIGKILL) can't be caught — Yapivo distrusts a stale "open"
        //    after its own timeout in that case.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let panel = self?.floatingPanel, panel.isVisible {
                PickerPresence.post(false)
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

    /// Menu bar icon — the flat Copibara mark (capybara hugging a clipboard), rendered from the
    /// vector rebuild in `assets/brand/vector/` (small variant: eyes and nose enlarged for tiny sizes).
    /// Two exact renders — 20 px for 1x and 40 px for Retina — so neither display gets a resampled
    /// image. It's a template image, so macOS tints it for light/dark menu bars automatically.
    /// Embedded as base64 so it works identically in `swift run` and the .app bundle.
    static let menuBarIcon: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size)
        for base64 in [menuBarIcon1x, menuBarIcon2x] {
            if let data = Data(base64Encoded: base64), let rep = NSBitmapImageRep(data: data) {
                rep.size = size                     // 40 px rep at 20 pt = 2x
                img.addRepresentation(rep)
            }
        }
        if img.representations.isEmpty {
            let fallback = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Copibara")!
            fallback.isTemplate = true
            return fallback
        }
        img.isTemplate = true
        return img
    }()
    private static let menuBarIcon1x = "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAABsElEQVR4nJSUzytEURTHDzNkQUgTiinJkgWl/FhgJbGhbEiSnWym7OTXRtn7A5RiYcPKwoIFsTIypMjPlDJISX7zPd65zXHnPTPzrU/v3HvO+7773j33+ShehWAQlIN9clcPaAan4Fkn0qzCDHABimXcBm5BtoyfJLci40tQBr68DHlVJ5SaguDKDNKt5Bk4oOQV1mZuhjlCssqn2Of4lc8qmAatlLzyxGPNTOhvmAmiKa6Q9QAC4JMH+pUbldkQWAID4F3VvMoc54Zljl+7xhRow6CKQ+AQdIBj0CKcg3bJhVR9hQn8alI3KLfPmMR8c0TVdgpaLybQ35Ab9priezORuKn5dEXtFRao+I2c4xX1MCkCc+RsJC8gYGr1aubFhLUFGuh/7YBaidm8nwO9KfUqzpIrb8S3Ra9Vw6ozgd96DaNqMApmyfmraG2CcVDldq82DOsnQSWgFEyouQ/QRX9bjLXnZjgJVtWY24XbYV3Gu2BZ4ohlOGUCu0WawAg5Z5Q3hXe+UnI34EjVboM7MAM2vAyNFsAiePTI54JuinUFJTLk89knVzfdk9MqcQ/8AQAA//9KeklnAAAABklEQVQDABT/TkDPp7xQAAAAAElFTkSuQmCC"
    private static let menuBarIcon2x = "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAD10lEQVR4nLyYV+hURxTGv8RAYioxpCgpJJAE0/5GQ0JCLIioKCoogj5YsCKC2BBFVFAs2J5UFETs6IOgIgoKYnmwYUHsvSM27L19n3NX1+uZmXv37/rBj2XPzOw9e8/MmTNTBdn1NalFbieUoi9IHfKIXM8y4O0MfaqSpeQ0WU8Ok67Irx7J2PXJby3MMqhKhj4zSPui7++RlmQ7OYRsakdmk3eLbL+Tz8nK0MC3ENZ35ISnbSepTT5MPjUFaiRt5+DekvrcJAfJT57f+ZJc8LThHYRVO9D2J9lLfkFY++F3TvqbrPA1xhy8FmmPOSfVjLTfDDXGQqwFUuqKzSo9466vMbaK75BxKJ9GI+CcFAuxtBnl05ZYh1iIvyW7yScojy6TCnLW1yEW4gUon3PSZ2RuqEPIwebkf5RfDUkjX2MoxNvIX3gz2kjqWQ0+B6vD7QZvSk/gdpSL6QZfiFsbNm1H6aS6H3EdSH2/YTiiF9XcGuxzsI5hUzWiVT2IdIOb4NpJQjuBSqqaSd/uZGDyG72Mvua26suD1Q3beNKbTCAfwc3PkXDFghyZSj4g98nDpO/HZAMZQRYlf6ZJ8ltpfWPYvHMw7wJRfTgrZetJpiO7tCH8mzb6QnwZ+VTXsNVHPl2xjL4Qn0c+dYaLhkKuMA8jbZFPZtbwvcFS9t9O5Cjc1pjXOe8zfXPwU7hUkOVI8Dr0gFSDkRF8Ib4HV6xWM9p0FvFWwBG1gJ1O9KzH1gDfGxxLBhv2M3C57wZKk9KTEncNo20UGZ42WnNQSbUvbK2qhHNIxq72tPWDUTlZDnaEO1pauoTKy3eCU8JvlzZac7Ax/Er/oQ6IH+I3kSFF30MLT2XXjNADpd/gVzPyPUrXj6RpoL0ibbAWiU5xVeGXQvQzuYp8Ujm1D3ZmKOgWXKifywrx1YiDugBSqlhLfkU4KeuBU+BOhxUR56RXzuGWg8dhVzPFOpZ89iddIn1VeKwjRxDX0bTBclAHpf8Qlmq6E6QPmRfodytxUPoBcc1PG6w5+D5cMjXrs0QqxbYjn3QHEzoHn4K7rHpJ1irWIrFK/oIm4YVzql6epNB8+8cYt5VMC/xuK8voy0kqfZYnD/qqyL4YrvQvSM4odZwsQtXMTLj9PC3dBf6Bly+U9Gd1Htll9A9efehuT1dsWqlatWPw6kWSSqQGyCdVLArnULIDLvV4Fbv6KNYyuDlSC5XTHrgLzTZZOme5PCpoDllC1pDJcOHNIy0+pSVFZEDWQXneoKRFUbgByHvmkHT6U1k1MeuAvA4WS1uS5mis6tYRVAsh7xt/pqcAAAD//wbeIgIAAAAGSURBVAMAyaGyVahvlPQAAAAASUVORK5CYII="

    // MARK: - Picker

    /// Static toggle so it can be called from the init() closure.
    ///
    /// `board` / `typeFilter` summon the picker *at* something — the Favorites hotkey
    /// and Yapivo's `copibara://favorites` both come through here. A targeted summon
    /// shows that view for this session only, leaving the tab a plain ⌘⇧V returns to
    /// untouched (see `CopibaraPickerView.initialBoard`).
    static func sharedTogglePicker(board: String? = nil, typeFilter: ContentType? = nil) {
        let services = CopibaraServices.shared
        let isTargeted = board != nil || typeFilter != nil

        // If the panel is already visible, dismiss it. A plain summon stops there —
        // that's the toggle. A targeted one reopens at its target instead: you asked
        // for that list, not for the panel to disappear.
        if let panel = services.floatingPanel, panel.isVisible {
            panel.dismiss()
            services.floatingPanel = nil
            guard isTargeted else { return }
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
            },
            initialBoard: board,
            initialTypeFilter: typeFilter
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
            pasteboard.setString(services.store.fullText(for: item), forType: .string)
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
                payloads.append(.text(services.store.fullText(for: item)))
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
