import XCTest
import AppKit
@testable import MacMD

final class ColorThemingTests: XCTestCase {

    // MARK: - Hex

    func testHexParsesSixDigits() {
        let c = NSColor(hex: "#C13F50")!.usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, CGFloat(0xC1) / 255, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, CGFloat(0x3F) / 255, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, CGFloat(0x50) / 255, accuracy: 0.001)
    }

    func testHexAcceptsNoHashPrefix() {
        XCTAssertEqual(NSColor(hex: "2E86AB")?.hexString, "#2E86AB")
    }

    func testHexRejectsMalformed() {
        XCTAssertNil(NSColor(hex: "#12"))
        XCTAssertNil(NSColor(hex: "ZZZZZZ"))
    }

    func testHexStringRoundTrips() {
        XCTAssertEqual(NSColor(hex: "#A86FE0")?.hexString, "#A86FE0")
    }

    // MARK: - Coloring / slot mapping

    func testDisplayNames() {
        XCTAssertEqual(Coloring.off.displayName, "Default")
        XCTAssertEqual(Coloring.unified.displayName, "Unified")
        XCTAssertEqual(Coloring.standard.displayName, "Standard")
    }

    func testSlotIndexDefaultIsNil() {
        for level in 1...6 {
            XCTAssertNil(ColorTheming.slotIndex(forHeadingLevel: level, scheme: .off))
        }
    }

    func testSlotIndexUnifiedAlwaysZero() {
        for level in 1...6 {
            XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: level, scheme: .unified), 0)
        }
    }

    func testSlotIndexStandardMapsH4ToH6IntoSlot2() {
        XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: 1, scheme: .standard), 0)
        XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: 2, scheme: .standard), 1)
        XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: 3, scheme: .standard), 2)
        XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: 4, scheme: .standard), 2)
        XCTAssertEqual(ColorTheming.slotIndex(forHeadingLevel: 6, scheme: .standard), 2)
    }

    func testAppAppearanceNSAppearance() {
        XCTAssertNil(AppAppearance.system.nsAppearance)
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }
}
