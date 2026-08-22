import Foundation

struct Pinboard: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var icon: String
    var isDefault: Bool

    static let clipboard = Pinboard(
        id: "clipboard",
        name: "Copibara",
        icon: "📋",
        isDefault: true
    )

    static let yapivo = Pinboard(
        id: "yapivo",
        name: "Yapivo",
        icon: "🎙",
        isDefault: true
    )

    /// Where Forage mode files everything it collects.
    static let collected = Pinboard(
        id: "collected",
        name: "Collected",
        icon: "🌿",
        isDefault: true
    )
}

// MARK: - Virtual Boards

/// Board IDs that are *views over* the real boards rather than places items are
/// filed into. Nothing is ever stored with one of these as its `boardId` — they're
/// filters the tab strip presents alongside the real pinboards.
enum BoardFilter {
    /// Every clip, from every board.
    static let all = "all"
    /// Clips the user starred — the shortlist you summon and paste from.
    static let favorites = "favorites"

    static let ids: Set<String> = [all, favorites]

    /// True when `id` is a filter, not a board items can be written to.
    static func isVirtual(_ id: String) -> Bool { ids.contains(id) }
}
