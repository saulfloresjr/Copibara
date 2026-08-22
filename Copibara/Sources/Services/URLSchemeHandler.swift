import AppKit

/// Handles `copibara://` URLs — the one-way channel Yapivo uses to drive hands-free
/// window capture while it (not Copibara) owns the microphone.
///
///   copibara://capture            → show the numbered window grid
///   copibara://select?n=2         → pick window 2 → clipboard
///   copibara://cancel             → dismiss the grid
///   copibara://picker             → summon the clip picker
///   copibara://favorites          → summon it on the Favorites shortlist
///   copibara://favorites?type=link → …narrowed to links, ready to arrow + Enter
///   copibara://links              → shorthand for the line above
///   copibara://favorite           → star the clip you just copied
///
/// The favourites routes are why this exists in its current shape: saying a URL out
/// loud is slower and more error-prone than picking it off a list, so Yapivo opens
/// the list and the keyboard finishes the job.
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

    /// The `?type=` filter, if the URL carries a recognised one.
    private func contentType(in url: URL) -> ContentType? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let raw = items?.first(where: { $0.name == "type" })?.value else { return nil }
        return ContentType(rawValue: raw.lowercased())
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

        case "picker":
            CopibaraApp.sharedTogglePicker()

        case "favorites", "favourites":
            CopibaraApp.sharedTogglePicker(
                board: BoardFilter.favorites,
                typeFilter: contentType(in: url)
            )

        // Voice shorthand: "Copibara links" is easier to say than a query string.
        case "links":
            CopibaraApp.sharedTogglePicker(board: BoardFilter.favorites, typeFilter: .link)

        // "Favorite that" — stars the clip you just copied, no window needed.
        case "favorite", "favourite":
            CopibaraServices.shared.store.favoriteLatest()

        default:
            break
        }
    }
}
