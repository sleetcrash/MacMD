import XCTest
import AppKit
import SwiftUI
@testable import MacMD

@MainActor
final class ColorThemingTests: XCTestCase {

    override func tearDown() {
        Theme.setActiveTheme(coloring: .off, palette: ColorTheming.standardPresets[0])
        super.tearDown()
    }

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

    // MARK: - Palette background + kind

    func testPaletteDecodesLegacyShapeWithDefaults() throws {
        let json = """
        [{"id":"custom.X","name":"Old","scheme":"unified","slots":[{"light":"#FF0000","dark":"#00FF00"}]}]
        """.data(using: .utf8)!
        let palettes = try JSONDecoder().decode([Palette].self, from: json)
        XCTAssertEqual(palettes[0].background, ColorPair(light: "#FFFFFF", dark: "#1E1E1E"))
        XCTAssertFalse(palettes[0].isStatic)
    }

    func testPaletteEncodesFullShape() throws {
        let p = Palette(id: "custom.1", name: "Mine", scheme: .standard,
                        slots: [ColorPair(light: "#111111", dark: "#222222")])
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"background\""))
        XCTAssertTrue(json.contains("\"isStatic\""))
    }

    func testStaticDecodeRecollapsesToLightValues() throws {
        let json = """
        {"id":"custom.2","name":"Frozen","scheme":"standard","isStatic":true,
         "background":{"light":"#111111","dark":"#222222"},
         "slots":[{"light":"#333333","dark":"#444444"}]}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Palette.self, from: json)
        XCTAssertEqual(p.background, ColorPair(light: "#111111", dark: "#111111"))
        XCTAssertEqual(p.slots[0], ColorPair(light: "#333333", dark: "#333333"))
    }

    func testTintThemesMatchBackgroundPresets() {
        XCTAssertEqual(Palette.tintThemes.count, 3)
        XCTAssertEqual(Palette.tintThemes.map(\.id), ["tint.cream", "tint.parchment", "tint.gray"])
        for (tint, preset) in zip(Palette.tintThemes, BackgroundPreset.all) {
            XCTAssertEqual(tint.scheme, .off)
            XCTAssertTrue(tint.slots.isEmpty)
            XCTAssertFalse(tint.isStatic)
            XCTAssertEqual(tint.background, preset.pair)
        }
    }

    func testDefaultTheme() {
        let d = Palette.defaultTheme
        XCTAssertEqual(d.id, "default")
        XCTAssertEqual(d.scheme, .off)
        XCTAssertTrue(d.slots.isEmpty)
        XCTAssertEqual(d.background, EditorBackground.defaultPair)
        XCTAssertFalse(d.isStatic)
    }

    // MARK: - Theme active state

    func testDefaultColoringHeadingColorIsLabelColor() {
        Theme.setActiveTheme(coloring: .off, palette: ColorTheming.standardPresets[0])
        XCTAssertEqual(Theme.headingColor(level: 1), .labelColor)
        XCTAssertEqual(Theme.headingColor(level: 3), .labelColor)
    }

    func testStandardColoringResolvesSlotColors() {
        Theme.setActiveTheme(coloring: .standard, palette: ColorTheming.preset(id: "std.rgb")!)
        XCTAssertEqual(Theme.headingColor(level: 1).resolvedHexLight, "#C13F50")
        XCTAssertEqual(Theme.headingColor(level: 2).resolvedHexLight, "#2E8049")
        XCTAssertEqual(Theme.headingColor(level: 5).resolvedHexLight, "#2E86AB") // inherits H3
    }

    func testSetActiveThemeReportsChange() {
        Theme.setActiveTheme(coloring: .off, palette: ColorTheming.standardPresets[0])
        XCTAssertTrue(Theme.setActiveTheme(coloring: .unified, palette: ColorTheming.preset(id: "uni.teal")!))
        XCTAssertFalse(Theme.setActiveTheme(coloring: .unified, palette: ColorTheming.preset(id: "uni.teal")!))
    }

    // MARK: - CustomDraft slot normalization

    func testBeginEditingNormalizesSlotCountToScheme() {
        let draft = CustomDraft()

        // A standard palette with too few slots (e.g. a corrupt prefs blob) is
        // padded to 3, so the slotCount-indexed reads in `palette`/`persistPalette`
        // can't run off the end. Reading `palette` would have trapped before.
        draft.beginEditing(Palette(id: "x", name: "X", scheme: .standard,
                                   slots: [ColorPair(light: "#112233", dark: "#445566")]))
        XCTAssertEqual(draft.lights.count, 3)
        XCTAssertEqual(draft.darks.count, 3)
        XCTAssertEqual(draft.palette.slots.count, 3)

        // A unified palette with too many slots truncates to 1.
        draft.beginEditing(Palette(id: "y", name: "Y", scheme: .unified, slots: [
            ColorPair(light: "#111111", dark: "#222222"),
            ColorPair(light: "#333333", dark: "#444444"),
        ]))
        XCTAssertEqual(draft.lights.count, 1)
        XCTAssertEqual(draft.darks.count, 1)
        XCTAssertEqual(draft.palette.slots.count, 1)
    }

    // MARK: - CustomDraft side modes

    func testSingleSidedDraftRepeatsItsColorsAcrossBothAppearances() {
        let draft = CustomDraft()
        draft.begin(scheme: .unified)
        draft.lights = [Color(nsColor: NSColor(hex: "#112233")!)]
        draft.darks = [Color(nsColor: NSColor(hex: "#AABBCC")!)]

        draft.sides = .light
        XCTAssertEqual(draft.resolvedSlots, [ColorPair(light: "#112233", dark: "#112233")])

        draft.sides = .dark
        XCTAssertEqual(draft.resolvedSlots, [ColorPair(light: "#AABBCC", dark: "#AABBCC")])

        draft.sides = .both
        XCTAssertEqual(draft.resolvedSlots, [ColorPair(light: "#112233", dark: "#AABBCC")])
    }

    func testBeginResetsSideModeToBoth() {
        let draft = CustomDraft()
        draft.sides = .dark
        draft.begin(scheme: .standard)
        XCTAssertEqual(draft.sides, .both)
    }

    // MARK: - Hex parsing

    func testHexInitRejectsMalformedInput() {
        XCTAssertNotNil(NSColor(hex: "#C13F50"))
        XCTAssertNotNil(NSColor(hex: "C13F50"))
        XCTAssertNil(NSColor(hex: "-F0000"), "a sign char must not parse to a color")
        XCTAssertNil(NSColor(hex: "GGGGGG"), "non-hex digits must be rejected")
        XCTAssertNil(NSColor(hex: "12345"), "wrong length must be rejected")
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
