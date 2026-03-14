import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary
    static let appPrimary = Color(red: 0/255, green: 136/255, blue: 255/255)
    static let appPrimaryHover = Color(red: 0/255, green: 109/255, blue: 214/255)

    // Surfaces
    static let appBackground = Color(light: Color(red: 245/255, green: 245/255, blue: 247/255),
                                     dark: Color(red: 28/255, green: 28/255, blue: 30/255))
    static let appSurface = Color(light: .white,
                                  dark: Color(red: 44/255, green: 44/255, blue: 46/255))
    static let appSurfaceHover = Color(light: Color(red: 240/255, green: 240/255, blue: 242/255),
                                       dark: Color(red: 58/255, green: 58/255, blue: 60/255))

    // Text
    static let appTextPrimary = Color(light: Color(red: 29/255, green: 29/255, blue: 31/255),
                                      dark: Color(red: 245/255, green: 245/255, blue: 247/255))
    static let appTextSecondary = Color(light: Color(red: 108/255, green: 108/255, blue: 112/255),
                                        dark: Color(red: 161/255, green: 161/255, blue: 166/255))
    static let appTextTertiary = Color(light: Color(red: 174/255, green: 174/255, blue: 178/255),
                                       dark: Color(red: 99/255, green: 99/255, blue: 102/255))

    // Borders
    static let appBorder = Color(light: Color(red: 229/255, green: 229/255, blue: 234/255),
                                 dark: Color(red: 58/255, green: 58/255, blue: 60/255))

    // Content Type Colors
    static let typeText = Color(red: 0/255, green: 136/255, blue: 255/255)
    static let typeLink = Color(red: 88/255, green: 86/255, blue: 214/255)
    static let typeImage = Color(red: 255/255, green: 149/255, blue: 0/255)
    static let typeCode = Color(red: 48/255, green: 209/255, blue: 88/255)
    static let typeFile = Color(red: 255/255, green: 69/255, blue: 58/255)

    // Convenience initializer for light/dark mode
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

// MARK: - Content Type Color

extension ContentType {
    var color: Color {
        switch self {
        case .text:  return .typeText
        case .code:  return .typeCode
        case .link:  return .typeLink
        case .image: return .typeImage
        case .file:  return .typeFile
        }
    }

    var backgroundColor: Color {
        color.opacity(0.12)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 100
}
