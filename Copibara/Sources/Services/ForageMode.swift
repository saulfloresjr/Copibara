import AppKit
import Foundation

/// Forage mode — the toggle that turns Copibara from "fast scratchpad" into
/// "collect things that caught my eye".
///
/// **Fast mode (default, disarmed):** screenshots behave exactly as they always have.
/// Nothing is inspected, no URL is read, no OCR runs. Zero added cost, zero added
/// privacy surface.
///
/// **Forage mode (armed):** each capture also records where it came from, lands on
/// the Collected board, and is pinned so bulk clears can't take it.
///
/// Arming is deliberate (hotkey / menu) or automatic on an allowlisted site. Auto-arm
/// always disarms itself when you leave, and a manual arm times out — because a mode
/// that silently records page URLs must never be something you can forget you left on.
@MainActor
@Observable
final class ForageMode {

    static let shared = ForageMode()

    // MARK: - Tunables

    /// A manual arm expires after this long with no captures.
    private let idleTimeout: TimeInterval = 20 * 60
    /// How often the auto-arm watcher samples the frontmost page.
    private let watchInterval: TimeInterval = 2.0
    /// Latched context older than this is stale — a capture that slow isn't related.
    private let latchTTL: TimeInterval = 20

    // MARK: - State

    private(set) var isArmed = false
    /// True when the current arm came from the domain allowlist rather than the user.
    private(set) var armedAutomatically = false

    /// Auto-arm on allowlisted sites.
    var autoArmEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoArmEnabled, forKey: Keys.autoArm)
            if !autoArmEnabled && armedAutomatically { disarm() }
        }
    }

    /// Hosts that auto-arm forage mode. Matched as suffixes, so "reddit.com"
    /// also covers "old.reddit.com" and "www.reddit.com".
    var allowlist: [String] {
        didSet { UserDefaults.standard.set(allowlist, forKey: Keys.allowlist) }
    }

    /// Sites offered in the menu. The user can toggle any subset.
    static let knownSites = ["reddit.com", "x.com", "instagram.com", "youtube.com", "news.ycombinator.com", "tiktok.com"]

    /// Context captured the instant a screenshot began, waiting to be paired with
    /// the image once it lands on the clipboard.
    private var latched: (context: CaptureContext, at: Date)?

    private var lastActivity = Date()
    private var watchTimer: Timer?

    private enum Keys {
        static let autoArm = "forage.autoArmEnabled"
        static let allowlist = "forage.allowlist"
    }

    private init() {
        let defaults = UserDefaults.standard
        self.autoArmEnabled = defaults.object(forKey: Keys.autoArm) as? Bool ?? true
        self.allowlist = defaults.object(forKey: Keys.allowlist) as? [String] ?? ["reddit.com"]
    }

    // MARK: - Arming

    func toggle() {
        if isArmed { disarm(announce: true) } else { arm(automatically: false) }
    }

    func arm(automatically: Bool) {
        let wasArmed = isArmed
        isArmed = true
        armedAutomatically = automatically
        lastActivity = Date()
        guard !wasArmed else { return }

        let reason = automatically ? "auto" : "manual"
        print("[Forage] armed (\(reason))")
        ForageHUD.shared.show(
            icon: "🌿",
            title: "Forage mode ON",
            subtitle: automatically ? "auto-armed — captures go to Collected" : "captures go to Collected"
        )
    }

    func disarm(announce: Bool = false) {
        guard isArmed else { return }
        isArmed = false
        armedAutomatically = false
        latched = nil
        print("[Forage] disarmed")
        if announce {
            ForageHUD.shared.show(icon: "💤", title: "Forage mode OFF", subtitle: "back to fast captures")
        }
    }

    // MARK: - Allowlist

    func isAllowlisted(_ host: String) -> Bool {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return allowlist.contains { bare == $0 || bare.hasSuffix("." + $0) }
    }

    func toggleSite(_ site: String) {
        if let index = allowlist.firstIndex(of: site) {
            allowlist.remove(at: index)
        } else {
            allowlist.append(site)
        }
    }

    // MARK: - Context Latching

    /// Snapshot the current source. Called the moment a capture *starts* — by then
    /// the crosshair hasn't taken over yet, so the frontmost app is still the page
    /// you're looking at. Waiting until the image hits the clipboard is too late:
    /// focus has moved to the screenshot UI and the context is gone.
    func latchContext() {
        guard isArmed, !isSensitiveContext() else { return }
        let context = SourceInspector.snapshot()
        latched = (context, Date())
        print("[Forage] latched: \(context.displaySource ?? "unknown")")
    }

    /// Take the latched context, if it's still fresh.
    func consumeLatchedContext() -> CaptureContext? {
        defer { latched = nil }
        guard let latched, Date().timeIntervalSince(latched.at) < latchTTL else { return nil }
        return latched.context
    }

    /// Drop a latch that turned out not to precede a capture — e.g. the user just
    /// tapped `~` for a backtick. Otherwise that stale context would get stapled onto
    /// whatever image happened to reach the clipboard next.
    func clearLatch() { latched = nil }

    // MARK: - Sensitive Contexts

    /// Apps we never inspect or collect from, even while armed.
    ///
    /// Forage records window titles and copied text, which is fine for a subreddit and
    /// very much not fine for a vault entry. An armed mode the user forgot about must
    /// not be able to sweep a password into a board.
    private static let sensitiveBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.1password.browser-support",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass",
        "com.sinew.Secrets",
        "in.sinew.Enpass-Desktop",
        "com.apple.Passwords",
    ]

    /// True when the frontmost app is a credential manager — collection must stand down.
    func isSensitiveContext() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Self.sensitiveBundleIDs.contains(bundleID)
    }

    /// Note that a capture happened, so a manual arm doesn't idle out mid-session.
    func noteActivity() { lastActivity = Date() }

    // MARK: - Watcher

    /// Start the auto-arm / idle-disarm loop.
    func startWatching() {
        guard watchTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: watchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.5
        watchTimer = timer
    }

    func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func tick() {
        // Idle timeout for a manual arm — never leave recording on indefinitely.
        if isArmed && !armedAutomatically,
           Date().timeIntervalSince(lastActivity) > idleTimeout {
            disarm(announce: true)
            return
        }

        guard autoArmEnabled else { return }

        // Don't touch a manual arm — the user's explicit choice outranks the allowlist.
        if isArmed && !armedAutomatically { return }

        let host = SourceInspector.frontmostURL()?.host
        let matches = host.map { isAllowlisted($0) } ?? false

        if matches && !isArmed {
            arm(automatically: true)
        } else if !matches && isArmed && armedAutomatically {
            // Left the site — stand down. This is the privacy guarantee: auto-arm
            // can never follow you to your bank.
            disarm()
        }
    }
}
