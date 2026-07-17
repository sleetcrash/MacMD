import XCTest
@testable import MacMD

final class ThemeSettingsTests: XCTestCase {

    func testResolveReturnsNilForDefaultScheme() {
        XCTAssertNil(ThemeSettings.resolvePalette(coloring: .off, themeId: "std.rgb", customs: []))
    }

    func testResolveReturnsPresetById() {
        let p = ThemeSettings.resolvePalette(coloring: .standard, themeId: "std.eva01", customs: [])
        XCTAssertEqual(p?.id, "std.eva01")
    }

    func testResolveReturnsCustomById() {
        let custom = Palette(id: "custom.x", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        let p = ThemeSettings.resolvePalette(coloring: .unified, themeId: "custom.x", customs: [custom])
        XCTAssertEqual(p?.id, "custom.x")
    }

    func testResolveFallsBackToSchemeFirstPresetForUnknownId() {
        let p = ThemeSettings.resolvePalette(coloring: .unified, themeId: "bogus", customs: [])
        XCTAssertEqual(p?.id, ColorTheming.defaultUnifiedId)
    }

    func testCustomsEncodeDecodeRoundTrip() throws {
        let customs = [
            Palette(id: "c1", name: "One", scheme: .standard, slots: [
                ColorPair(light: "#111111", dark: "#222222"),
                ColorPair(light: "#333333", dark: "#444444"),
                ColorPair(light: "#555555", dark: "#666666"),
            ]),
            Palette(id: "c2", name: "Two", scheme: .unified, slots: [
                ColorPair(light: "#777777", dark: "#888888"),
            ]),
        ]
        let data = ThemeSettings.encodeCustoms(customs)
        XCTAssertEqual(ThemeSettings.decodeCustoms(data), customs)
    }

    func testDecodeEmptyOrGarbageReturnsEmpty() {
        XCTAssertEqual(ThemeSettings.decodeCustoms(Data()), [])
        XCTAssertEqual(ThemeSettings.decodeCustoms(Data([0x00, 0x01])), [])
    }

    func testResolveIgnoresCrossSchemePreset() {
        // coloring is .unified but the id points to a Standard preset → fall back to the Unified default.
        let p = ThemeSettings.resolvePalette(coloring: .unified, themeId: "std.rgb", customs: [])
        XCTAssertEqual(p?.id, ColorTheming.defaultUnifiedId)
    }

    func testResolveIgnoresCrossSchemeCustom() {
        // A Unified custom id requested under Standard coloring must NOT load
        // (wrong slot count); fall back to the Standard default preset instead.
        let unifiedCustom = Palette(id: "custom.u", name: "U", scheme: .unified,
                                    slots: [ColorPair(light: "#111111", dark: "#222222")])
        let p = ThemeSettings.resolvePalette(coloring: .standard, themeId: "custom.u", customs: [unifiedCustom])
        XCTAssertEqual(p?.id, ColorTheming.defaultStandardId)
    }

    // MARK: - resolveTheme (Task 2: total resolver, no Coloring/scheme gate)

    func testResolveThemeDefault() {
        XCTAssertEqual(ThemeSettings.resolveTheme(id: "default", customs: []), Palette.defaultTheme)
    }

    func testResolveThemeTint() {
        let p = ThemeSettings.resolveTheme(id: "tint.cream", customs: [])
        XCTAssertEqual(p.id, "tint.cream")
    }

    func testResolveThemeStandardPreset() {
        let p = ThemeSettings.resolveTheme(id: "std.rgb", customs: [])
        XCTAssertEqual(p.id, "std.rgb")
    }

    func testResolveThemeUnifiedPreset() {
        let p = ThemeSettings.resolveTheme(id: "uni.red", customs: [])
        XCTAssertEqual(p.id, "uni.red")
    }

    func testResolveThemeCustom() {
        let custom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        let p = ThemeSettings.resolveTheme(id: "custom.mine", customs: [custom])
        XCTAssertEqual(p.id, "custom.mine")
    }

    func testResolveThemeUnknownFallsBackToDefault() {
        XCTAssertEqual(ThemeSettings.resolveTheme(id: "garbage.nonexistent", customs: []), Palette.defaultTheme)
    }
}
