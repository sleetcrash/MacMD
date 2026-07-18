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

    // MARK: - Default swatch colors

    func testDefaultBackgroundMatchesTheModeColors() {
        XCTAssertEqual(EditorBackground.defaultBackground(dark: false).hexString, "#FFFFFF")
        XCTAssertEqual(EditorBackground.defaultBackground(dark: true).hexString, "#1E1E1E")
    }

    // MARK: - BackgroundLibrary

    func testBackgroundLibraryAddNormalizesDedupsAndRejectsMalformed() {
        let suite = "EditorBackgroundTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        BackgroundLibrary.add("#15151a", to: d)
        BackgroundLibrary.add("#15151A", to: d)          // same color, other case
        BackgroundLibrary.add("not-a-color", to: d)      // rejected
        BackgroundLibrary.add("#FF8800", to: d)
        XCTAssertEqual(BackgroundLibrary.all(d), ["#15151A", "#FF8800"])

        BackgroundLibrary.remove("#15151a", from: d)
        XCTAssertEqual(BackgroundLibrary.all(d), ["#FF8800"])
    }

    // MARK: - Theme-based background resolution

    func testEffectiveAppearanceStaticFollowsLuminance() {
        let dark = ColorPair(light: "#111111", dark: "#111111")
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: dark, isStatic: true, appearance: .light), .dark)

        let cream = ColorPair(light: "#F8F1E1", dark: "#F8F1E1")
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: cream, isStatic: true, appearance: .dark), .light)
    }

    func testEffectiveAppearanceStaticBadHexFallsThroughToMode() {
        // An unparseable light hex on a static pair falls through to the Mode,
        // not an appearance-dependent labelColor guess.
        let bad = ColorPair(light: "garbage", dark: "garbage")
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: bad, isStatic: true, appearance: .dark), .dark)
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: bad, isStatic: true, appearance: .light), .light)
    }

    func testEffectiveAppearanceDynamicFollowsMode() {
        let pair = BackgroundPreset.all[0].pair
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: pair, isStatic: false, appearance: .light), .light)
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: pair, isStatic: false, appearance: .dark), .dark)
        XCTAssertEqual(EditorBackground.effectiveAppearance(background: pair, isStatic: false, appearance: .system), .system)
    }

    func testActiveColorSemanticNilForDefaultPair() {
        XCTAssertNil(EditorBackground.activeColor(background: EditorBackground.defaultPair, dark: false))
        XCTAssertNil(EditorBackground.activeColor(background: EditorBackground.defaultPair, dark: true))
    }

    func testActiveColorPicksSideByDark() {
        let cream = BackgroundPreset.all[0].pair
        XCTAssertEqual(EditorBackground.activeColor(background: cream, dark: false)?.hexString, cream.light)
        XCTAssertEqual(EditorBackground.activeColor(background: cream, dark: true)?.hexString, cream.dark)
    }
}
