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

    /// For text clips too large to keep inline: the file in the store's `texts/`
    /// directory holding the full text. When set, `content` holds only the first
    /// `inlineTextLimit` bytes — enough to preview and search — and paste/copy read
    /// the full text from disk via `CopibaraStore.fullText(for:)`.
    ///
    /// Without this, every byte of every clip lived in memory and was rewritten on
    /// every copy: a handful of multi-megabyte JSON clips made data.json 141 MB,
    /// launch decode ~1 s, and each save ~0.5 s on the main thread.
    /// Optional for the same decoder reason as `pinned` above.
    var contentFileName: String?

    /// Clips larger than this (UTF-8 bytes) keep only this much inline.
    static let inlineTextLimit = 64 * 1024

    /// True when `content` is only the head of a larger clip stored on disk.
    var isTextTruncated: Bool { contentFileName != nil }

    static func == (lhs: CopibaraItem, rhs: CopibaraItem) -> Bool {
        lhs.id == rhs.id
    }

    /// This clip with `content` cut to its inline head and the full text recorded as
    /// living in `fileName`. Every other field is carried over unchanged.
    func spilled(to fileName: String) -> CopibaraItem {
        CopibaraItem(
            id: id,
            content: content.utf8Prefix(Self.inlineTextLimit),
            type: type,
            preview: preview,
            createdAt: createdAt,
            boardId: boardId,
            size: size,
            imageFileName: imageFileName,
            capture: capture,
            pinned: pinned,
            favorite: favorite,
            contentFileName: fileName
        )
    }

    /// Search match. Foraged items also match on their source and on any text OCR'd
    /// out of the image — which is what makes screenshots findable at all.
    ///
    /// ASCII queries use an allocation-free byte scan that folds A–Z as it goes.
    /// Foundation's `range(of:options:.caseInsensitive)` does full Unicode case
    /// folding per character, and on a real 10k-clip history it took 1.3 s per pass
    /// against 9 ms for the byte scan, with identical hits. Queries containing
    /// non-ASCII characters still go through Foundation so "École" keeps matching
    /// "école".
    func matches(_ query: SearchQuery) -> Bool {
        func has(_ haystack: String?) -> Bool {
            guard let haystack, !haystack.isEmpty else { return false }
            return query.isASCII
                ? haystack.asciiCaseInsensitiveContains(query.bytes)
                : haystack.range(of: query.text, options: .caseInsensitive) != nil
        }
        if has(content) { return true }
        if has(type.label) { return true }
        guard let capture else { return false }
        return has(capture.handle) || has(capture.host) || has(capture.appName)
            || has(capture.windowTitle) || has(capture.ocrText)
    }
}

/// A search term prepared once per search pass rather than once per clip.
struct SearchQuery {
    let text: String
    let bytes: [UInt8]
    let isASCII: Bool

    init(_ raw: String) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        bytes = Array(text.utf8)
        isASCII = bytes.allSatisfy { $0 < 0x80 }
    }

    var isEmpty: Bool { text.isEmpty }
}

extension String {
    /// The longest prefix of this string that fits in `maxBytes` of UTF-8, cut on a
    /// character boundary so a multi-byte character is never split.
    func utf8Prefix(_ maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var end = utf8.index(utf8.startIndex, offsetBy: maxBytes)
        // `end` is the first byte left out; if it continues a character, back up.
        while end > utf8.startIndex, UTF8.isContinuation(utf8[end]) {
            end = utf8.index(before: end)
        }
        return String(self[..<end])
    }

    /// Case-insensitive substring test for an already-lowercased ASCII `needle`,
    /// scanning UTF-8 bytes in place: no copies, stops at the first hit.
    func asciiCaseInsensitiveContains(_ needle: [UInt8]) -> Bool {
        let n = needle.count
        if n == 0 { return true }
        var copy = self
        return copy.withUTF8 { hay in
            guard hay.count >= n else { return false }
            @inline(__always) func fold(_ b: UInt8) -> UInt8 { (b &- 65) < 26 ? b | 0x20 : b }
            let first = needle[0]
            var i = 0
            let last = hay.count - n
            while i <= last {
                if fold(hay[i]) == first {
                    var j = 1
                    while j < n, fold(hay[i + j]) == needle[j] { j += 1 }
                    if j == n { return true }
                }
                i += 1
            }
            return false
        }
    }
}

// MARK: - Content Type Detection

func detectContentType(_ content: String) -> ContentType {
    // Classify from the head only. This runs on the main thread for every copy, and on
    // a 32 MB clip the full-string trim + 24 substring scans stalled capture; the type
    // is evident from the first few KB.
    let head = content.utf8Prefix(16 * 1024)
    let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
    let isWhole = head.utf8.count == content.utf8.count

    // URL detection — a clip longer than the head can't be a single URL.
    if isWhole,
       let url = URL(string: trimmed),
       let scheme = url.scheme,
       ["http", "https", "ftp"].contains(scheme.lowercased()),
       url.host != nil {
        return .link
    }

    return looksLikeCode(trimmed) ? .code : .text
}

private func looksLikeCode(_ trimmed: String) -> Bool {
    let codePatterns = [
        "func ", "class ", "struct ", "enum ", "import ",           // Swift
        "function ", "const ", "let ", "var ",                       // JS
        "def ", "return ", "if __name__",                            // Python
        "public ", "private ", "static ", "void ",                   // Java/C#
        "->", "=>", "&&", "||",                                     // Operators
        "{", "}", "();", "[]",                                      // Brackets
    ]

    let codeIndicators = codePatterns.filter { trimmed.contains($0) }
    return codeIndicators.count >= 2 || trimmed.contains("\n") && trimmed.contains("{")
}

func generatePreview(_ content: String, type: ContentType) -> String {
    // Previews are at most a few lines; never split or copy a multi-megabyte clip
    // (the code case below used to split the whole text into lines to keep six).
    let content = content.utf8Prefix(16 * 1024)
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
