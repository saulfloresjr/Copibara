import XCTest
import AppKit
@testable import Copibara

/// The menu bar icon and app icon are built from the vector mark in assets/brand/vector/.
final class IconTests: XCTestCase {

    func testMenuBarIconHasExactRendersForBothDisplayScales() {
        let icon = CopibaraApp.menuBarIcon
        let px = icon.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide }.sorted()
        XCTAssertEqual(px, [20, 40], "expected one exact render per display scale")
        XCTAssertEqual(icon.size, NSSize(width: 20, height: 20))
        XCTAssertTrue(icon.isTemplate, "must stay a template so macOS tints it for light/dark menu bars")
    }

    func testArmedIconStillBuildsFromTheBaseIcon() {
        let armed = CopibaraApp.menuBarIconArmed
        XCTAssertFalse(armed.isTemplate)
        XCTAssertEqual(armed.size, NSSize(width: 22, height: 20))
        XCTAssertNotNil(armed.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testAppIconCarriesEveryResolution() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/AppIcon.icns")
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        let px = Set(img.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide })
        XCTAssertEqual(px, [16, 32, 64, 128, 256, 512, 1024])
    }
}
