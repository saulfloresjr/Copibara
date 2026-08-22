import Foundation

// MARK: - Content Type

enum ContentType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case image

    var label: String {
        switch self {
        case .text:  return "TEXT"
        case .code:  return "CODE"
        case .link:  return "LINK"
        case .image: return "IMAGE"
        }
    }

    var emoji: String {
        switch self {
        case .text:  return "📝"
        case .code:  return "💻"
        case .link:  return "🔗"
        case .image: return "🖼"
        }
    }
}

// MARK: - Clipboard Item

struct CopibaraItem: Identifiable, Codable, Equatable {
    let id: Int
    let content: String
    let type: ContentType
    let preview: String
    let createdAt: Date
    var boardId: String
    let size: Int

    /// For image items: relative filename of the stored image in the images directory.
    var imageFileName: String?

    /// Where this clip came from, captured automatically in Forage mode.
    /// Nil for everything captured in Fast mode — which is the default.
    var capture: CaptureContext?

    /// Foraged finds are pinned: "Clear Everything" skips them, so a routine
    /// cleanup can't wipe the things you deliberately collected.
    ///
    /// Optional, not `Bool = false`, on purpose: Swift's synthesized decoder ignores
    /// property defaults and *throws* on a missing key. A non-optional here would make
    /// every pre-existing data.json fail to decode — which the store treats as "no
    /// data" and reseeds, silently destroying the user's clipboard history.
    var pinned: Bool?

    /// Convenience for the optional above.
    var isPinned: Bool { pinned == true }

    /// Starred by hand. Favourites are the shortlist you summon and paste from —
    /// the links you reach for daily — so they're exempt from the history cap and
    /// from "Clear Everything", exactly like foraged finds.
    ///
    /// Optional for the same decoder reason as `pinned` above: a non-optional Bool
    /// would make every pre-existing data.json throw on the missing key, which the
    /// store reads as "no data" and reseeds — wiping the user's history.
    var favorite: Bool?

    /// Convenience for the optional above.
    var isFavorite: Bool { favorite == true }

    /// Kept on purpose — foraged/pinned or favourited. These survive the history cap
    /// and "Clear Everything"; everything else is churn.
    var isKept: Bool { isPinned || isFavorite }

    static func == (lhs: CopibaraItem, rhs: CopibaraItem) -> Bool {
        lhs.id == rhs.id
    }

    /// Search match. Foraged items also match on their source and on any text OCR'd
    /// out of the image — which is what makes screenshots findable at all.
    ///
    /// Uses `range(of:options:.caseInsensitive)`, NOT `content.lowercased().contains`:
    /// the old form allocated a fresh lowercased copy of every item's content (some up
    /// to 70k chars) on every keystroke × ~19k items — the search lag at scale. The
    /// range form compares case-insensitively in place, no allocation, and bails at the
    /// first hit. `query` is assumed already lowercased/trimmed by the caller.
    func matches(_ query: String) -> Bool {
        func has(_ haystack: String?) -> Bool {
            guard let haystack, !haystack.isEmpty else { return false }
            return haystack.range(of: query, options: .caseInsensitive) != nil
        }
        if has(content) { return true }
        if has(type.label) { return true }
        guard let capture else { return false }
        return has(capture.handle) || has(capture.host) || has(capture.appName)
            || has(capture.windowTitle) || has(capture.ocrText)
    }
}

// MARK: - Content Type Detection

func detectContentType(_ content: String) -> ContentType {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    // URL detection
    if let url = URL(string: trimmed),
       let scheme = url.scheme,
       ["http", "https", "ftp"].contains(scheme.lowercased()),
       url.host != nil {
        return .link
    }

    // Code detection heuristics
    let codePatterns = [
        "func ", "class ", "struct ", "enum ", "import ",           // Swift
        "function ", "const ", "let ", "var ",                       // JS
        "def ", "return ", "if __name__",                            // Python
        "public ", "private ", "static ", "void ",                   // Java/C#
        "->", "=>", "&&", "||",                                     // Operators
        "{", "}", "();", "[]",                                      // Brackets
    ]

    let codeIndicators = codePatterns.filter { trimmed.contains($0) }
    if codeIndicators.count >= 2 || trimmed.contains("\n") && trimmed.contains("{") {
        return .code
    }

    return .text
}

func generatePreview(_ content: String, type: ContentType) -> String {
    switch type {
    case .link:
        if let url = URL(string: content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return url.host ?? content
        }
        return String(content.prefix(100))
    case .code:
        let lines = content.components(separatedBy: "\n")
        return lines.prefix(6).joined(separator: "\n")
    case .image:
        return "📸 Screenshot"
    default:
        return String(content.prefix(200))
    }
}

func formatSize(_ bytes: Int) -> String {
    if bytes < 1024 {
        return "\(bytes) B"
    } else if bytes < 1024 * 1024 {
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    } else {
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}
