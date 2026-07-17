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

    // MARK: - Theme selection (transactional)

    func testInitLoadsSavedState() {
        let d = freshDefaults()
        d.set("std.eva01", forKey: ThemeSettings.selectedThemeKey)
        d.set(18.0, forKey: FontSize.key)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.themeId, "std.eva01")
        XCTAssertEqual(c.fontSize, 18.0)
    }

    func testInitDefaultsToDefaultTheme() {
        XCTAssertEqual(ThemeController(defaults: freshDefaults()).themeId, "default")
    }

    func testApplyThemePreviewsWithoutPersisting() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(themeId: "uni.teal", fontSize: 20, appearance: .system)
        XCTAssertEqual(c.themeId, "uni.teal")
        // saved state untouched
        XCTAssertNil(d.string(forKey: ThemeSettings.selectedThemeKey))
        XCTAssertEqual(c.savedThemeId, "default")
    }

    func testSaveThemePersistsSelectedTheme() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.save(themeId: "std.rgb", fontSize: 12, appearance: .system)
        XCTAssertEqual(c.themeId, "std.rgb")
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "std.rgb")
        XCTAssertEqual(d.object(forKey: FontSize.key) as? Double, 12.0)
    }

    func testRevertToSavedRestoresTheme() {
        let d = freshDefaults()
        d.set("uni.red", forKey: ThemeSettings.selectedThemeKey)
        let c = ThemeController(defaults: d)
        c.apply(themeId: "std.rgb", fontSize: 24, appearance: .light)
        c.revertToSaved()
        XCTAssertEqual(c.themeId, "uni.red")
    }

    func testInitRunsMigration() {
        // Seed the legacy per-key prefs; init must migrate them into the unified
        // customThemes/selectedTheme shape (delete legacy, bump schema to 2).
        let d = freshDefaults()
        d.set("standard", forKey: "colorScheme")
        d.set("std.rgb", forKey: "themeId")
        d.set("preset", forKey: "backgroundMode")
        d.set("bg.gray", forKey: "backgroundPreset")
        let c = ThemeController(defaults: d)
        XCTAssertNil(d.object(forKey: "colorScheme"), "legacy keys are deleted")
        XCTAssertEqual(d.integer(forKey: ThemeSettings.schemaVersionKey), 2)
        XCTAssertEqual(c.themeId, d.string(forKey: ThemeSettings.selectedThemeKey))
        let customs = ThemeSettings.savedCustoms(d)
        XCTAssertEqual(customs.count, 1)
        XCTAssertEqual(customs[0].background, BackgroundPreset.preset(id: "bg.gray")?.pair)
    }

    func testResolveUnknownSelectedThemeFallsBackToDefault() {
        let d = freshDefaults()
        d.set("custom.deleted", forKey: ThemeSettings.selectedThemeKey)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.themeId, "custom.deleted", "the raw unknown selection is retained")
        XCTAssertEqual(c.resolvedTheme, Palette.defaultTheme, "resolution falls back to Default")
    }

    func testSavedCustomsReadsCustomThemesKey() {
        let d = freshDefaults()
        let custom = Palette(id: "custom.x", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        d.set(ThemeSettings.encodeCustoms([custom]), forKey: ThemeSettings.customThemesKey)
        XCTAssertEqual(ThemeSettings.savedCustoms(d), [custom])
    }

    // MARK: - Appearance (transactional, like theme/size)

    func testInitLoadsSavedAppearance() {
        let d = freshDefaults()
        d.set(AppAppearance.dark.rawValue, forKey: ThemeSettings.appearanceKey)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.appearance, .dark)
    }

    func testInitDefaultsToDarkAppearance() {
        let c = ThemeController(defaults: freshDefaults())
        XCTAssertEqual(c.appearance, .dark)
    }

    func testApplyAppearanceDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(themeId: "std.rgb", fontSize: 14, appearance: .light)
        XCTAssertEqual(c.appearance, .light)
        XCTAssertNil(d.string(forKey: ThemeSettings.appearanceKey))
        XCTAssertEqual(c.savedAppearance, .dark)
    }

    func testSaveAppearancePersists() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.save(themeId: "std.rgb", fontSize: 14, appearance: .light)
        XCTAssertEqual(c.appearance, .light)
        XCTAssertEqual(d.string(forKey: ThemeSettings.appearanceKey), AppAppearance.light.rawValue)
    }

    func testRevertRestoresSavedAppearance() {
        let d = freshDefaults()
        d.set(AppAppearance.dark.rawValue, forKey: ThemeSettings.appearanceKey)
        let c = ThemeController(defaults: d)
        c.apply(themeId: "std.rgb", fontSize: 14, appearance: .light)
        XCTAssertEqual(c.appearance, .light)
        c.revertToSaved()
        XCTAssertEqual(c.appearance, .dark)
    }

    func testSetFontSizeImmediatePersistsSizeOnly() {
        let d = freshDefaults()
        d.set("std.rgb", forKey: ThemeSettings.selectedThemeKey)
        let c = ThemeController(defaults: d)
        c.setFontSizeImmediate(11)
        XCTAssertEqual(c.fontSize, 11.0)
        XCTAssertEqual(d.object(forKey: FontSize.key) as? Double, 11.0)
        // theme saved-state untouched
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "std.rgb")
    }

    func testFontSizeClamps() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.apply(themeId: "std.rgb", fontSize: 999, appearance: .system)
        XCTAssertEqual(c.fontSize, Double(FontSize.maximum))
        c.apply(themeId: "std.rgb", fontSize: 1, appearance: .system)
        XCTAssertEqual(c.fontSize, Double(FontSize.minimum))
    }

    // MARK: - CustomDraft slot-count invariant
    //
    // The Custom Theme editor indexes per-slot arrays by `0..<slotCount`, so the
    // light/dark arrays must always have exactly `slotCount` elements, otherwise
    // the editor crashes with an out-of-bounds read (regression: the default draft
    // had scheme=standard, slotCount 3, but single-element arrays).

    func testCustomDraftDefaultIsSlotConsistent() {
        let draft = CustomDraft()
        XCTAssertEqual(draft.lights.count, draft.slotCount)
        XCTAssertEqual(draft.darks.count, draft.slotCount)
    }

    func testCustomDraftBeginKeepsSlotCountsConsistent() {
        let draft = CustomDraft()
        draft.begin(scheme: .standard)
        XCTAssertEqual(draft.lights.count, 3)
        XCTAssertEqual(draft.darks.count, 3)
        draft.begin(scheme: .unified)
        XCTAssertEqual(draft.lights.count, 1)
        XCTAssertEqual(draft.darks.count, 1)
    }

    func testCustomDraftBeginEditingMatchesPaletteSlots() {
        let draft = CustomDraft()
        let standard = Palette(id: "c1", name: "S", scheme: .standard, slots: [
            ColorPair(light: "#111111", dark: "#222222"),
            ColorPair(light: "#333333", dark: "#444444"),
            ColorPair(light: "#555555", dark: "#666666"),
        ])
        draft.begin(scheme: .unified)          // start mismatched (1 slot)
        draft.beginEditing(standard)           // load a 3-slot standard palette
        XCTAssertEqual(draft.slotCount, 3)
        XCTAssertEqual(draft.lights.count, 3)
        XCTAssertEqual(draft.darks.count, 3)
    }

    // MARK: - CustomDraft swatch selection (Bug #3)

    func testCustomDraftDefaultHasNoSelectedWell() {
        XCTAssertNil(CustomDraft().selectedWell)
    }

    func testCustomDraftSelectedWellEquatableMatchesSameSideAndSlot() {
        XCTAssertEqual(CustomDraft.SelectedWell(side: .light, slot: 1),
                       CustomDraft.SelectedWell(side: .light, slot: 1))
        XCTAssertNotEqual(CustomDraft.SelectedWell(side: .light, slot: 1),
                          CustomDraft.SelectedWell(side: .dark, slot: 1))
        XCTAssertNotEqual(CustomDraft.SelectedWell(side: .light, slot: 0),
                          CustomDraft.SelectedWell(side: .light, slot: 1))
    }

    func testCustomDraftEndClearsSelectedWell() {
        let draft = CustomDraft()
        draft.selectedWell = CustomDraft.SelectedWell(side: .dark, slot: 2)
        draft.end()
        XCTAssertNil(draft.selectedWell)
    }

    func testCustomDraftBeginClearsSelectedWell() {
        let draft = CustomDraft()
        draft.selectedWell = CustomDraft.SelectedWell(side: .light, slot: 0)
        draft.begin(scheme: .standard)
        XCTAssertNil(draft.selectedWell)
    }

    // MARK: - Font family (transactional, additive)

    func testInitDefaultsToSystemMonospaceFamily() {
        let c = ThemeController(defaults: freshDefaults())
        XCTAssertEqual(c.fontFamilyId, FontFamily.default.id)
    }

    func testInitLoadsSavedFontFamily() {
        let d = freshDefaults()
        d.set("georgia", forKey: ThemeSettings.fontFamilyKey)
        XCTAssertEqual(ThemeController(defaults: d).fontFamilyId, "georgia")
    }

    func testInitUnknownFontFamilyFallsBack() {
        let d = freshDefaults()
        d.set("not-a-real-font", forKey: ThemeSettings.fontFamilyKey)
        XCTAssertEqual(ThemeController(defaults: d).fontFamilyId, FontFamily.default.id)
    }

    func testApplyFontFamilyDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.applyFontFamily("menlo")
        XCTAssertEqual(c.fontFamilyId, "menlo")
        XCTAssertNil(d.string(forKey: ThemeSettings.fontFamilyKey))
        XCTAssertEqual(c.savedFontFamilyId, FontFamily.default.id)
    }

    func testSaveFontFamilyPersists() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.saveFontFamily("monaco")
        XCTAssertEqual(c.fontFamilyId, "monaco")
        XCTAssertEqual(d.string(forKey: ThemeSettings.fontFamilyKey), "monaco")
    }

    func testRevertRestoresSavedFontFamily() {
        let d = freshDefaults()
        d.set("georgia", forKey: ThemeSettings.fontFamilyKey)
        let c = ThemeController(defaults: d)
        c.applyFontFamily("menlo")
        c.revertToSaved()
        XCTAssertEqual(c.fontFamilyId, "georgia")
    }

    // MARK: - Cursor (transactional, additive)

    func testInitDefaultsToBarCursorBlinkOn() {
        let c = ThemeController(defaults: freshDefaults())
        XCTAssertEqual(c.cursorStyle, .bar)
        XCTAssertTrue(c.cursorBlink)
    }

    func testInitLoadsSavedCursor() {
        let d = freshDefaults()
        d.set(CursorStyle.block.rawValue, forKey: ThemeSettings.cursorStyleKey)
        d.set(false, forKey: ThemeSettings.cursorBlinkKey)
        let c = ThemeController(defaults: d)
        XCTAssertEqual(c.cursorStyle, .block)
        XCTAssertFalse(c.cursorBlink)
    }

    func testInitUnknownCursorStyleFallsBackToBar() {
        let d = freshDefaults()
        d.set("squiggle", forKey: ThemeSettings.cursorStyleKey)
        XCTAssertEqual(ThemeController(defaults: d).cursorStyle, .bar)
    }

    func testApplyCursorDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.applyCursor(style: .underline, blink: false)
        XCTAssertEqual(c.cursorStyle, .underline)
        XCTAssertFalse(c.cursorBlink)
        XCTAssertNil(d.object(forKey: ThemeSettings.cursorStyleKey))
    }

    func testSaveCursorPersists() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.saveCursor(style: .block, blink: false)
        XCTAssertEqual(d.string(forKey: ThemeSettings.cursorStyleKey), CursorStyle.block.rawValue)
        XCTAssertEqual(d.object(forKey: ThemeSettings.cursorBlinkKey) as? Bool, false)
    }

    func testRevertRestoresSavedCursor() {
        let d = freshDefaults()
        d.set(CursorStyle.block.rawValue, forKey: ThemeSettings.cursorStyleKey)
        d.set(false, forKey: ThemeSettings.cursorBlinkKey)
        let c = ThemeController(defaults: d)
        c.applyCursor(style: .bar, blink: true)
        c.revertToSaved()
        XCTAssertEqual(c.cursorStyle, .block)
        XCTAssertFalse(c.cursorBlink)
    }

    // MARK: - Cursor color (transactional, additive)

    func testInitDefaultsToNilCursorColor() {
        XCTAssertNil(ThemeController(defaults: freshDefaults()).cursorColorHex)
    }

    func testApplyCursorColorDoesNotPersist() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.applyCursorColor("#FF8800")
        XCTAssertEqual(c.cursorColorHex, "#FF8800")
        XCTAssertNil(d.string(forKey: ThemeSettings.cursorColorKey))
    }

    func testSaveCursorColorPersistsAndNilRemoves() {
        let d = freshDefaults()
        let c = ThemeController(defaults: d)
        c.saveCursorColor("#FF8800")
        XCTAssertEqual(d.string(forKey: ThemeSettings.cursorColorKey), "#FF8800")
        c.saveCursorColor(nil)
        XCTAssertNil(d.string(forKey: ThemeSettings.cursorColorKey))
        XCTAssertNil(c.cursorColorHex)
    }

    func testRevertRestoresSavedCursorColor() {
        let d = freshDefaults()
        d.set("#00CC66", forKey: ThemeSettings.cursorColorKey)
        let c = ThemeController(defaults: d)
        c.applyCursorColor("#FF0000")
        c.revertToSaved()
        XCTAssertEqual(c.cursorColorHex, "#00CC66")
    }
}
