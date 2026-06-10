import XCTest
@testable import MacMD

final class EditorBackgroundTests: XCTestCase {

    // MARK: - Luma

    func testLumaOfWhiteIsOne() {
        XCTAssertEqual(EditorBackground.luma(r: 1, g: 1, b: 1), 1.0, accuracy: 0.0001)
    }

    func testLumaOfBlackIsZero() {
        XCTAssertEqual(EditorBackground.luma(r: 0, g: 0, b: 0), 0.0, accuracy: 0.0001)
    }

    func testLumaUsesRec601Weights() {
        XCTAssertEqual(EditorBackground.luma(r: 1, g: 0, b: 0), 0.299, accuracy: 0.0001)
        XCTAssertEqual(EditorBackground.luma(r: 0, g: 1, b: 0), 0.587, accuracy: 0.0001)
        XCTAssertEqual(EditorBackground.luma(r: 0, g: 0, b: 1), 0.114, accuracy: 0.0001)
    }

    // MARK: - isLight

    func testWhiteIsLight() {
        XCTAssertEqual(EditorBackground.isLight(hex: "#FFFFFF"), true)
    }

    func testBlackIsDark() {
        XCTAssertEqual(EditorBackground.isLight(hex: "#000000"), false)
    }

    func testDefaultDarkEditorBackgroundIsDark() {
        XCTAssertEqual(EditorBackground.isLight(hex: "#1E1E1E"), false)
    }

    func testPureRedIsDark() {
        // Red's luma is 0.299: below threshold, so it gets light text.
        XCTAssertEqual(EditorBackground.isLight(hex: "#FF0000"), false)
    }

    func testYellowIsLight() {
        XCTAssertEqual(EditorBackground.isLight(hex: "#FFFF00"), true)
    }

    func testPureBlueIsDark() {
        XCTAssertEqual(EditorBackground.isLight(hex: "#0000FF"), false)
    }

    func testMidGraySitsJustAboveThreshold() {
        // #808080 luma = 0.50196...: reads light, so text on it goes dark.
        XCTAssertEqual(EditorBackground.isLight(hex: "#808080"), true)
    }

    func testMalformedHexIsNil() {
        XCTAssertNil(EditorBackground.isLight(hex: ""))
        XCTAssertNil(EditorBackground.isLight(hex: "bogus"))
        XCTAssertNil(EditorBackground.isLight(hex: "#12345"))
    }

    // MARK: - effectiveAppearance

    func testDefaultModePassesTheModeThrough() {
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .default, hex: "#FF0000", appearance: .light), .light)
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .default, hex: nil, appearance: .system), .system)
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .default, hex: nil, appearance: .dark), .dark)
    }

    func testCustomLightColorForcesLightAppearance() {
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .custom, hex: "#FFFDE7", appearance: .dark), .light)
    }

    func testCustomDarkColorForcesDarkAppearance() {
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .custom, hex: "#101820", appearance: .light), .dark)
    }

    func testCustomWithoutUsableColorFallsBackToTheMode() {
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .custom, hex: nil, appearance: .dark), .dark)
        XCTAssertEqual(EditorBackground.effectiveAppearance(mode: .custom, hex: "bogus", appearance: .light), .light)
    }

    // MARK: - customColor

    func testCustomColorIsNilUnderDefaultMode() {
        XCTAssertNil(EditorBackground.customColor(mode: .default, hex: "#FF0000"))
    }

    func testCustomColorIsNilWithoutUsableHex() {
        XCTAssertNil(EditorBackground.customColor(mode: .custom, hex: nil))
        XCTAssertNil(EditorBackground.customColor(mode: .custom, hex: "bogus"))
    }

    func testCustomColorRoundTripsTheHex() {
        XCTAssertEqual(EditorBackground.customColor(mode: .custom, hex: "#FF8800")?.hexString, "#FF8800")
    }

    // MARK: - Persistence contract + Default swatch colors

    func testBackgroundModeRawValues() {
        XCTAssertEqual(BackgroundMode.default.rawValue, "default")
        XCTAssertEqual(BackgroundMode.custom.rawValue, "custom")
    }

    func testDefaultBackgroundMatchesTheModeColors() {
        XCTAssertEqual(EditorBackground.defaultBackground(dark: false).hexString, "#FFFFFF")
        XCTAssertEqual(EditorBackground.defaultBackground(dark: true).hexString, "#1E1E1E")
    }
}
