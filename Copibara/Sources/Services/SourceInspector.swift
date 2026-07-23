import AppKit
import ApplicationServices

/// Reads "where am I right now" from the frontmost app using the Accessibility API.
///
/// We already hold Accessibility permission for the tilde event tap, so this costs
/// no new prompt and no AppleScript/Automation consent. Every call is bounded by a
/// short messaging timeout and a shallow search — a slow or hostile app can never
/// stall the capture path.
enum SourceInspector {

    /// Browsers we'll dig into for a page URL.
    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",   // Arc
        "com.vivaldi.Vivaldi",
        "org.mozilla.firefox",
        "ai.perplexity.comet",
    ]

    /// Snapshot the current source. Cheap when the frontmost app isn't a browser.
    static func snapshot() -> CaptureContext {
        var ctx = CaptureContext()

        guard let app = NSWorkspace.shared.frontmostApplication else { return ctx }
        ctx.appName = app.localizedName
        ctx.kind = .app

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Never let a wedged app block the screenshot path.
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        guard let window = copyElement(axApp, kAXFocusedWindowAttribute) else { return ctx }
        ctx.windowTitle = copyString(window, kAXTitleAttribute)

        // Page URL — browsers only.
        if let bundleID = app.bundleIdentifier, browserBundleIDs.contains(bundleID),
           let url = findURL(in: window) {
            ctx.urlString = url.absoluteString
            let parsed = SourceParser.parse(url: url)
            ctx.handle = parsed.handle
            ctx.kind = parsed.kind
        }

        // Window titles are a decent last resort — Reddit puts the subreddit in the
        // tab title ("… : r/homestead"), so this often lands even without a URL.
        if ctx.handle == nil, let title = ctx.windowTitle {
            let fromTitle = SourceParser.handle(inText: title)
            if let handle = fromTitle.handle {
                ctx.handle = handle
                if let kind = fromTitle.kind { ctx.kind = kind }
            }
        }

        return ctx
    }

    /// Just the frontmost app's page URL, used by the auto-arm domain watcher.
    static func frontmostURL() -> URL? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              browserBundleIDs.contains(bundleID) else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let window = copyElement(axApp, kAXFocusedWindowAttribute) else { return nil }
        return findURL(in: window)
    }

    // MARK: - AX Traversal

    /// Depth- and breadth-limited hunt for an element carrying AXURL.
    ///
    /// Safari and Chrome both expose AXURL on the web area, but at different depths
    /// and behind different container chains, so a bounded search is more portable
    /// than hard-coding either hierarchy. Limits keep the worst case to a few ms.
    private static func findURL(in element: AXUIElement, depth: Int = 0) -> URL? {
        if depth > 6 { return nil }

        // Direct hit.
        if let url = copyURL(element, "AXURL") { return url }

        // Only descend through plausible containers — a browser window's full tree
        // is enormous (every DOM node), and we must not walk it.
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children.prefix(24) {
            let role = copyString(child, kAXRoleAttribute) ?? ""
            // AXWebArea is the payload; the rest are the containers that wrap it.
            if role == "AXWebArea" {
                if let url = copyURL(child, "AXURL") { return url }
                continue
            }
            guard ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXTabGroup",
                   "AXUnknown", "AXLayoutArea", "AXBox"].contains(role) else { continue }
            if let url = findURL(in: child, depth: depth + 1) { return url }
        }
        return nil
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let string = ref as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func copyURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        if let url = value as? URL { return url }
        if let string = value as? String { return URL(string: string) }
        return nil
    }
}
