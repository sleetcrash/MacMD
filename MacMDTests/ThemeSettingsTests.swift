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
}
