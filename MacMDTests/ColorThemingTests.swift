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

    // MARK: - ColorPair

    func testColorPairResolvesLightAndDark() {
        let pair = ColorPair(light: "#C13F50", dark: "#E86577")
        XCTAssertEqual(pair.nsLight.hexString, "#C13F50")
        XCTAssertEqual(pair.nsDark.hexString, "#E86577")
        XCTAssertEqual(pair.resolved(for: NSAppearance(named: .aqua)!).hexString, "#C13F50")
        XCTAssertEqual(pair.resolved(for: NSAppearance(named: .darkAqua)!).hexString, "#E86577")
    }

    func testColorPairCodableRoundTrip() throws {
        let pair = ColorPair(light: "#1F7A5C", dark: "#43B488")
        let data = try JSONEncoder().encode(pair)
        let decoded = try JSONDecoder().decode(ColorPair.self, from: data)
        XCTAssertEqual(decoded, pair)
    }

    func testColorPairDynamicResolvesPerAppearance() {
        let pair = ColorPair(light: "#000000", dark: "#FFFFFF")
        let dyn = pair.dynamic
        var lightHex = "", darkHex = ""
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            lightHex = (dyn.usingColorSpace(.sRGB) ?? dyn).hexString
        }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            darkHex = (dyn.usingColorSpace(.sRGB) ?? dyn).hexString
        }
        XCTAssertEqual(lightHex, "#000000")
        XCTAssertEqual(darkHex, "#FFFFFF")
    }
}
