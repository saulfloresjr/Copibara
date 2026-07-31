import AppKit

/// Handles `copibara://` URLs — the one-way channel Yapivo uses to drive hands-free
/// window capture while it (not Copibara) owns the microphone.
///
///   copibara://capture        → show the numbered window grid
///   copibara://select?n=2     → pick window 2 → clipboard
///   copibara://cancel         → dismiss the grid
///
/// Registered via the Apple Event `GetURL` handler rather than an app-delegate hook,
/// so it needs no NSApplicationDelegate on this MenuBarExtra app. The scheme itself is
/// declared in the built app's Info.plist (see build.sh); until that's installed,
/// `route(_:)` can be called directly for testing.
final class URLSchemeHandler: NSObject {
    static let shared = URLSchemeHandler()

    func register() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        // AppleEvents are delivered on the main thread; hop onto the main actor so we
        // can touch the @MainActor picker without a data-race warning.
        MainActor.assumeIsolated { route(url) }
    }

    /// Route a parsed copibara:// URL. Public so it's callable in dev without the
    /// scheme registered in LaunchServices.
    @MainActor
    func route(_ url: URL) {
        guard url.scheme?.lowercased() == "copibara" else { return }
        let action = (url.host ?? "").lowercased()
        let toast: (String) -> Void = { CopibaraServices.shared.store.toast = $0 }

        switch action {
        case "capture":
            WindowCapturePicker.shared.capture(status: toast)
        case "select":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            if let n = items?.first(where: { $0.name == "n" })?.value.flatMap(Int.init) {
                WindowCapturePicker.shared.select(n)
            }
        case "cancel":
            WindowCapturePicker.shared.cancel()
        default:
            break
        }
    }
}
