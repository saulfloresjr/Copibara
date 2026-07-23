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
