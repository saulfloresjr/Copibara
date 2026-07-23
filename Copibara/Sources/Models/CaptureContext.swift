import Foundation

// MARK: - Source Kind

/// Where a foraged clip came from. Drives the little glyph on the card.
enum SourceKind: String, Codable {
    case reddit
    case x
    case instagram
    case youtube
    case tiktok
    case hackerNews
    case web
    case app

    var glyph: String {
        switch self {
        case .reddit:     return "👽"
        case .x:          return "𝕏"
        case .instagram:  return "📷"
        case .youtube:    return "▶️"
        case .tiktok:     return "🎵"
        case .hackerNews: return "🟧"
        case .web:        return "🌐"
        case .app:        return "🖥"
        }
    }
}

// MARK: - Capture Context

/// Everything we could learn about *where* a clip came from, gathered automatically
/// at capture time. Only populated when Forage mode is armed — in Fast mode this
/// stays nil and nothing is inspected.
struct CaptureContext: Codable, Equatable {
    /// Frontmost app at the moment the capture started, e.g. "Google Chrome".
    var appName: String?
    /// Focused window title, e.g. "Thyme taking over my yard : r/homestead".
    var windowTitle: String?
    /// Page URL, read from the browser via the Accessibility API.
    var urlString: String?
    /// Normalized source entity — "r/homestead", "@someone".
    var handle: String?
    var kind: SourceKind?
    /// Full text recognized in the captured image (Vision OCR). Feeds search.
    var ocrText: String?
    /// Largest engagement number spotted in the capture, e.g. "5.7K". Heuristic.
    var socialProof: String?
    /// Reserved for the intent note (typed or dictated) — phase two.
    var note: String?

    var url: URL? { urlString.flatMap { URL(string: $0) } }

    /// Bare host without a leading "www.".
    var host: String? {
        guard let h = url?.host else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Best human label for where this came from, most specific first.
    var displaySource: String? {
        handle ?? host ?? appName
    }

    /// True if we learned anything worth showing.
    var hasSource: Bool { displaySource != nil }
}

// MARK: - Source Parsing

/// Turns a URL (precise) or recognized text (fallback) into a normalized handle.
enum SourceParser {

    /// Path segments that are site chrome, never a username.
    private static let reserved: Set<String> = [
        "home", "explore", "search", "settings", "about", "login", "signup",
        "notifications", "messages", "i", "p", "reel", "reels", "watch",
        "shorts", "feed", "hashtag", "topic", "status", "media", "tv",
    ]

    /// Parse an authoritative source out of a page URL.
    static func parse(url: URL) -> (handle: String?, kind: SourceKind) {
        let host = (url.host ?? "").lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // reddit.com/r/<sub>/…  or  reddit.com/user/<name>
        if bare.hasSuffix("reddit.com") {
            if let i = parts.firstIndex(where: { $0.lowercased() == "r" }),
               i + 1 < parts.count {
                return ("r/\(parts[i + 1])", .reddit)
            }
            if let i = parts.firstIndex(where: { ["user", "u"].contains($0.lowercased()) }),
               i + 1 < parts.count {
                return ("u/\(parts[i + 1])", .reddit)
            }
            return (nil, .reddit)
        }

        // x.com/<handle>  /  twitter.com/<handle>
        if bare.hasSuffix("x.com") || bare.hasSuffix("twitter.com") {
            if let first = parts.first, !reserved.contains(first.lowercased()) {
                return ("@\(first)", .x)
            }
            return (nil, .x)
        }

        // instagram.com/<handle>  (posts under /p/ carry no handle in the URL)
        if bare.hasSuffix("instagram.com") {
            if let first = parts.first, !reserved.contains(first.lowercased()) {
                return ("@\(first)", .instagram)
            }
            return (nil, .instagram)
        }

        // youtube.com/@channel
        if bare.hasSuffix("youtube.com") || bare.hasSuffix("youtu.be") {
            if let first = parts.first, first.hasPrefix("@") {
                return (first, .youtube)
            }
            return (nil, .youtube)
        }

        // tiktok.com/@handle
        if bare.hasSuffix("tiktok.com") {
            if let first = parts.first, first.hasPrefix("@") {
                return (first, .tiktok)
            }
            return (nil, .tiktok)
        }

        if bare.hasSuffix("ycombinator.com") {
            return (nil, .hackerNews)
        }

        return (nil, .web)
    }

    /// Fallback: pull a handle straight out of recognized on-screen text.
    /// Works when there's no URL at all — a native app, or a screenshot of a screenshot.
    static func handle(inText text: String) -> (handle: String?, kind: SourceKind?) {
        // r/subreddit — subreddit names are 2–21 chars of [A-Za-z0-9_]
        if let m = firstMatch(#"(?:^|[\s(\[|•·])(r/[A-Za-z0-9_]{2,21})\b"#, in: text) {
            return (m, .reddit)
        }
        // u/username
        if let m = firstMatch(#"(?:^|[\s(\[|•·])(u/[A-Za-z0-9_\-]{3,20})\b"#, in: text) {
            return (m, .reddit)
        }
        // @handle — require 3+ chars so we don't catch stray "@" noise
        if let m = firstMatch(#"(?:^|[\s(\[|•·])(@[A-Za-z0-9_.]{3,30})\b"#, in: text) {
            return (m, nil)
        }
        return (nil, nil)
    }

    /// Heuristic: the biggest engagement-looking number in the capture ("5.7K", "1.2M").
    /// Reddit/X screenshots almost always carry the vote count in-frame, which is a
    /// far better "did this resonate?" signal than our own judgement.
    static func socialProof(inText text: String) -> String? {
        let pattern = #"\b(\d{1,3}(?:\.\d)?)([KM])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var best: (value: Double, label: String)?
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let numRange = Range(match.range(at: 1), in: text),
                  let suffixRange = Range(match.range(at: 2), in: text),
                  let num = Double(text[numRange]) else { return }
            let suffix = String(text[suffixRange])
            let value = num * (suffix == "M" ? 1_000_000 : 1_000)
            if best == nil || value > best!.value {
                best = (value, "\(text[numRange])\(suffix)")
            }
        }
        return best?.label
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
