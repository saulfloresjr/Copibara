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
}
