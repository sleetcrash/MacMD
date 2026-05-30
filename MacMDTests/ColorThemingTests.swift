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
        XCTAssertNil(NSColor(hex: "#C13F50FF"))
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

    func testSlotIndexStandardMapping() {
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

    // MARK: - Palette + presets

    func testStandardPresetCount() {
        XCTAssertEqual(ColorTheming.standardPresets.count, 6)
        XCTAssertEqual(ColorTheming.standardPresets.map(\.name),
                       ["RGB", "CMY(K)", "EVA-00", "EVA-01", "EVA-02", "EVA-END"])
    }

    func testUnifiedPresetCount() {
        XCTAssertEqual(ColorTheming.unifiedPresets.count, 8)
        XCTAssertEqual(ColorTheming.unifiedPresets.map(\.name),
                       ["Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Periwinkle"])
    }

    func testRGBPresetHex() {
        let rgb = ColorTheming.preset(id: "std.rgb")!
        XCTAssertEqual(rgb.slots.count, 3)
        XCTAssertEqual(rgb.slots[0].light, "#C13F50")
        XCTAssertEqual(rgb.slots[1].light, "#2E8049")
        XCTAssertEqual(rgb.slots[2].dark, "#54A9CC")
    }

    func testUnifiedPaletteHasOneSlot() {
        let red = ColorTheming.preset(id: "uni.red")!
        XCTAssertEqual(red.slots.count, 1)
        XCTAssertEqual(red.slots[0].light, "#A62A43")
    }

    func testPaletteHeadingColorStandardSelectsSlot() {
        let rgb = ColorTheming.preset(id: "std.rgb")!
        XCTAssertEqual(rgb.headingColor(level: 1).resolvedHexLight, "#C13F50")
        XCTAssertEqual(rgb.headingColor(level: 2).resolvedHexLight, "#2E8049")
        XCTAssertEqual(rgb.headingColor(level: 4).resolvedHexLight, "#2E86AB") // inherits H3
    }

    func testPaletteHeadingColorUnifiedSameForAllLevels() {
        let teal = ColorTheming.preset(id: "uni.teal")!
        for level in 1...6 {
            XCTAssertEqual(teal.headingColor(level: level).resolvedHexLight, "#2E86AB")
        }
    }

    func testPaletteCodableRoundTrip() throws {
        let p = Palette(id: "custom.1", name: "Mine", scheme: .standard, slots: [
            ColorPair(light: "#111111", dark: "#222222"),
            ColorPair(light: "#333333", dark: "#444444"),
            ColorPair(light: "#555555", dark: "#666666"),
        ])
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Palette.self, from: data), p)
    }

    func testPresetsForScheme() {
        XCTAssertEqual(ColorTheming.presets(for: .standard).count, 6)
        XCTAssertEqual(ColorTheming.presets(for: .unified).count, 8)
        XCTAssertTrue(ColorTheming.presets(for: .off).isEmpty)
    }

    func testHeadingColorFallsBackWhenSlotMissing() {
        let shortPalette = Palette(id: "short", name: "Short", scheme: .standard,
                                   slots: [ColorPair(light: "#111111", dark: "#222222")])
        // H2 maps to slot 1, which doesn't exist → labelColor fallback.
        XCTAssertEqual(shortPalette.headingColor(level: 2), .labelColor)
    }
}

// Shared across the test target (also used by MarkdownHighlighterTests). Declare
// exactly once, here, with no access modifier.
extension NSColor {
    var resolvedHexLight: String {
        var hex = ""
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            hex = (self.usingColorSpace(.sRGB) ?? self).hexString
        }
        return hex
    }
}
