import XCTest
@testable import MacMD

@MainActor
final class ThemeControllerTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "ThemeControllerTests.\(Int.random(in: 1...1_000_000))"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testInitLoadsSavedState() {
        let d = freshDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.eva01", forKey: ThemeSettings.themeIdKey)
        d.set(18.0, forKey: FontSize.key)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.coloring, .standard)
        XCTAssertEqual(c.themeId, "std.eva01")
        XCTAssertEqual(c.fontSize, 18.0)
    }

    func testApplyDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(coloring: .unified, themeId: "uni.teal", fontSize: 20, appearance: .system)
        XCTAssertEqual(c.coloring, .unified)
        XCTAssertEqual(c.themeId, "uni.teal")
        // saved state untouched
        XCTAssertNil(d.string(forKey: ThemeSettings.schemeKey))
        XCTAssertEqual(c.savedColoring, .off)
    }

    func testSavePersistsAndApplies() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.save(coloring: .standard, themeId: "std.rgb", fontSize: 12, appearance: .system)
        XCTAssertEqual(c.coloring, .standard)
        XCTAssertEqual(d.string(forKey: ThemeSettings.schemeKey), Coloring.standard.rawValue)
        XCTAssertEqual(d.string(forKey: ThemeSettings.themeIdKey), "std.rgb")
        XCTAssertEqual(d.object(forKey: FontSize.key) as? Double, 12.0)
    }

    func testRevertDiscardsUnsavedApply() {
        let d = freshDefaults()
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("uni.red", forKey: ThemeSettings.themeIdKey)
        let c = ThemeController(defaults: d)
        c.apply(coloring: .standard, themeId: "std.rgb", fontSize: 24, appearance: .light)
        c.revertToSaved()
        XCTAssertEqual(c.coloring, .unified)
        XCTAssertEqual(c.themeId, "uni.red")
    }

    // MARK: - Appearance (transactional, like coloring/theme/size)

    func testInitLoadsSavedAppearance() {
        let d = freshDefaults()
        d.set(AppAppearance.dark.rawValue, forKey: ThemeSettings.appearanceKey)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.appearance, .dark)
    }

    func testInitDefaultsToSystemAppearance() {
        let c = ThemeController(defaults: freshDefaults())
        XCTAssertEqual(c.appearance, .system)
    }

    func testApplyAppearanceDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(coloring: .off, themeId: "std.rgb", fontSize: 14, appearance: .dark)
        XCTAssertEqual(c.appearance, .dark)
        XCTAssertNil(d.string(forKey: ThemeSettings.appearanceKey))
        XCTAssertEqual(c.savedAppearance, .system)
    }

    func testSaveAppearancePersists() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.save(coloring: .off, themeId: "std.rgb", fontSize: 14, appearance: .light)
        XCTAssertEqual(c.appearance, .light)
        XCTAssertEqual(d.string(forKey: ThemeSettings.appearanceKey), AppAppearance.light.rawValue)
    }

    func testRevertRestoresSavedAppearance() {
        let d = freshDefaults()
        d.set(AppAppearance.dark.rawValue, forKey: ThemeSettings.appearanceKey)
        let c = ThemeController(defaults: d)
        c.apply(coloring: .off, themeId: "std.rgb", fontSize: 14, appearance: .light)
        XCTAssertEqual(c.appearance, .light)
        c.revertToSaved()
        XCTAssertEqual(c.appearance, .dark)
    }

    func testSetFontSizeImmediatePersistsSizeOnly() {
        let d = freshDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        let c = ThemeController(defaults: d)
        c.setFontSizeImmediate(11)
        XCTAssertEqual(c.fontSize, 11.0)
        XCTAssertEqual(d.object(forKey: FontSize.key) as? Double, 11.0)
        // coloring saved-state untouched (still standard)
        XCTAssertEqual(d.string(forKey: ThemeSettings.schemeKey), Coloring.standard.rawValue)
    }

    func testFontSizeClamps() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(coloring: .off, themeId: "std.rgb", fontSize: 999, appearance: .system)
        XCTAssertEqual(c.fontSize, Double(FontSize.maximum))
        c.apply(coloring: .off, themeId: "std.rgb", fontSize: 1, appearance: .system)
        XCTAssertEqual(c.fontSize, Double(FontSize.minimum))
    }
}
