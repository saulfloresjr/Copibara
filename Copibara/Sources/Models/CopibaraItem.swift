import Foundation

// MARK: - Content Type

enum ContentType: String, Codable, CaseIterable {
    case text
    case code
    case link
    case image
    case file

    var label: String {
        switch self {
        case .text:  return "TEXT"
        case .code:  return "CODE"
        case .link:  return "LINK"
        case .image: return "IMAGE"
        case .file:  return "FILE"
        }
    }

    var emoji: String {
        switch self {
        case .text:  return "📝"
        case .code:  return "💻"
        case .link:  return "🔗"
        case .image: return "🖼"
        case .file:  return "📁"
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

    static func == (lhs: CopibaraItem, rhs: CopibaraItem) -> Bool {
        lhs.id == rhs.id
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
