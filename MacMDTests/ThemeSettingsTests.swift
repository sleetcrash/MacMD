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

    // MARK: - migrateIfNeeded (Task 4: one-shot fast-cut migration)

    private func scratchDefaults() -> UserDefaults {
        let suite = "ThemeSettingsTests-migration-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        migrationTeardowns.append { d.removePersistentDomain(forName: suite) }
        return d
    }

    private var migrationTeardowns: [() -> Void] = []

    override func tearDown() {
        migrationTeardowns.forEach { $0() }
        migrationTeardowns = []
        super.tearDown()
    }

    func testMigrationOffDefaultSelectsDefault() {
        let d = scratchDefaults()
        d.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "default")
    }

    func testMigrationOffPresetMapsToTint() {
        let d = scratchDefaults()
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.cream", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "tint.cream")
    }

    func testMigrationOffCustomHexSynthesizesStaticCustom() {
        let d = scratchDefaults()
        d.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        d.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("#334455", forKey: ThemeSettings.customBackgroundKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        XCTAssertEqual(c.scheme, .off)
        XCTAssertTrue(c.slots.isEmpty)
        XCTAssertEqual(c.background, ColorPair(light: "#334455", dark: "#334455"))
        XCTAssertTrue(c.isStatic)
        XCTAssertEqual(c.name, "Custom")
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), c.id)
    }

    func testMigrationPresetDefaultKeepsPresetId() {
        let d = scratchDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        ThemeSettings.migrateIfNeeded(d)

        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "std.rgb")
        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertTrue(customs.isEmpty)
    }

    func testMigrationPresetWithPresetBackgroundSynthesizesDynamicCustom() {
        let d = scratchDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.gray", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        let rgb = ColorTheming.standardPresets.first { $0.id == "std.rgb" }!
        let gray = BackgroundPreset.all.first { $0.id == "bg.gray" }!
        XCTAssertEqual(c.slots, rgb.slots)
        XCTAssertEqual(c.background, gray.pair)
        XCTAssertEqual(c.name, "RGB")
        XCTAssertFalse(c.isStatic)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), c.id)
    }

    func testMigrationPresetWithCustomHexSynthesizesStaticCollapsed() {
        let d = scratchDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("#111111", forKey: ThemeSettings.customBackgroundKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        let rgb = ColorTheming.standardPresets.first { $0.id == "std.rgb" }!
        XCTAssertEqual(c.slots, rgb.slots.map { ColorPair(light: $0.dark, dark: $0.dark) })
        XCTAssertEqual(c.background, ColorPair(light: "#111111", dark: "#111111"))
        XCTAssertTrue(c.isStatic)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), c.id)
    }

    func testMigrationSelectedCustomGainsDefaultPair() {
        let d = scratchDefaults()
        let custom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        d.set(ThemeSettings.encodeCustoms([custom]), forKey: ThemeSettings.customsKey)
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        XCTAssertEqual(c.id, "custom.mine")
        XCTAssertEqual(c.name, "Mine")
        XCTAssertEqual(c.scheme, .unified)
        XCTAssertEqual(c.slots, custom.slots)
        XCTAssertEqual(c.background, EditorBackground.defaultPair)
        XCTAssertFalse(c.isStatic)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "custom.mine")
    }

    func testMigrationSelectedCustomWithPresetBackground() {
        let d = scratchDefaults()
        let custom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        d.set(ThemeSettings.encodeCustoms([custom]), forKey: ThemeSettings.customsKey)
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.parchment", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        let parchment = BackgroundPreset.all.first { $0.id == "bg.parchment" }!
        XCTAssertEqual(c.id, "custom.mine")
        XCTAssertEqual(c.slots, custom.slots)
        XCTAssertEqual(c.background, parchment.pair)
        XCTAssertFalse(c.isStatic)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "custom.mine")
    }

    func testMigrationSelectedCustomWithCustomHexBecomesStatic() {
        let d = scratchDefaults()
        let custom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                             slots: [ColorPair(light: "#111111", dark: "#222222")])
        d.set(ThemeSettings.encodeCustoms([custom]), forKey: ThemeSettings.customsKey)
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("#EEEEEE", forKey: ThemeSettings.customBackgroundKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        XCTAssertEqual(c.id, "custom.mine")
        XCTAssertEqual(c.slots, [ColorPair(light: "#111111", dark: "#111111")])
        XCTAssertEqual(c.background, ColorPair(light: "#EEEEEE", dark: "#EEEEEE"))
        XCTAssertTrue(c.isStatic)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "custom.mine")
    }

    func testMigrationNonSelectedCustomsBecomeDynamicDefaultPair() {
        let d = scratchDefaults()
        let c1 = Palette(id: "custom.one", name: "One", scheme: .unified,
                         slots: [ColorPair(light: "#111111", dark: "#222222")])
        let c2 = Palette(id: "custom.two", name: "Two", scheme: .standard, slots: [
            ColorPair(light: "#333333", dark: "#444444"),
            ColorPair(light: "#555555", dark: "#666666"),
            ColorPair(light: "#777777", dark: "#888888"),
        ])
        d.set(ThemeSettings.encodeCustoms([c1, c2]), forKey: ThemeSettings.customsKey)
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 2)
        for (original, migrated) in [(c1, customs.first { $0.id == "custom.one" }),
                                     (c2, customs.first { $0.id == "custom.two" })] {
            guard let migrated else { return XCTFail("missing migrated custom") }
            XCTAssertEqual(migrated.name, original.name)
            XCTAssertEqual(migrated.scheme, original.scheme)
            XCTAssertEqual(migrated.slots, original.slots)
            XCTAssertEqual(migrated.background, EditorBackground.defaultPair)
            XCTAssertFalse(migrated.isStatic)
        }
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "std.rgb")
    }

    func testMigrationSchemeMismatchKeysOffResolvedPalette() {
        let d = scratchDefaults()
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.gray", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        let uniRed = ColorTheming.unifiedPresets.first { $0.id == ColorTheming.defaultUnifiedId }!
        XCTAssertEqual(c.slots, uniRed.slots)
        XCTAssertEqual(c.name, uniRed.name)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), c.id)
    }

    func testMigrationDegenerateHexDegradesToDefaultSibling() {
        let dNil = scratchDefaults()
        dNil.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        dNil.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        ThemeSettings.migrateIfNeeded(dNil)
        XCTAssertEqual(dNil.string(forKey: ThemeSettings.selectedThemeKey), "default")
        XCTAssertTrue(ThemeSettings.decodeCustoms(dNil.data(forKey: ThemeSettings.customThemesKey) ?? Data()).isEmpty)

        let dGarbage = scratchDefaults()
        dGarbage.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        dGarbage.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        dGarbage.set("garbage", forKey: ThemeSettings.customBackgroundKey)
        ThemeSettings.migrateIfNeeded(dGarbage)
        XCTAssertEqual(dGarbage.string(forKey: ThemeSettings.selectedThemeKey), "default")
        XCTAssertTrue(ThemeSettings.decodeCustoms(dGarbage.data(forKey: ThemeSettings.customThemesKey) ?? Data()).isEmpty)

        // A selected custom (not just the off-scheme default) must also
        // degrade to its bg-default sibling, keeping the user's theme instead
        // of silently falling to "default".
        let selectedCustom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                                     slots: [ColorPair(light: "#111111", dark: "#222222")])
        let dSelectedNil = scratchDefaults()
        dSelectedNil.set(ThemeSettings.encodeCustoms([selectedCustom]), forKey: ThemeSettings.customsKey)
        dSelectedNil.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        dSelectedNil.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        dSelectedNil.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        ThemeSettings.migrateIfNeeded(dSelectedNil)
        assertSurvivesAsDynamicDefault(dSelectedNil, original: selectedCustom)

        let dSelectedGarbage = scratchDefaults()
        dSelectedGarbage.set(ThemeSettings.encodeCustoms([selectedCustom]), forKey: ThemeSettings.customsKey)
        dSelectedGarbage.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        dSelectedGarbage.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        dSelectedGarbage.set(BackgroundMode.custom.rawValue, forKey: ThemeSettings.backgroundModeKey)
        dSelectedGarbage.set("garbage", forKey: ThemeSettings.customBackgroundKey)
        ThemeSettings.migrateIfNeeded(dSelectedGarbage)
        assertSurvivesAsDynamicDefault(dSelectedGarbage, original: selectedCustom)
    }

    func testMigrationUnknownPresetIdDegradesToDefaultSibling() {
        let d = scratchDefaults()
        d.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.nonexistent", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "default")

        // Same degenerate-preset rule, but for a selected custom: it must
        // survive as its dynamic bg-default self, not get discarded.
        let selectedCustom = Palette(id: "custom.mine", name: "Mine", scheme: .unified,
                                     slots: [ColorPair(light: "#111111", dark: "#222222")])
        let dSelected = scratchDefaults()
        dSelected.set(ThemeSettings.encodeCustoms([selectedCustom]), forKey: ThemeSettings.customsKey)
        dSelected.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        dSelected.set("custom.mine", forKey: ThemeSettings.themeIdKey)
        dSelected.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        dSelected.set("bg.nonsense", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(dSelected)
        assertSurvivesAsDynamicDefault(dSelected, original: selectedCustom)
    }

    /// Shared assertion for the selected-custom degenerate-input blocks above:
    /// the custom must survive as dynamic with the default background pair,
    /// id/name/scheme/slots preserved, selected, with no stray synthesis.
    private func assertSurvivesAsDynamicDefault(_ d: UserDefaults, original: Palette) {
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), original.id)
        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 1)
        let c = customs[0]
        XCTAssertEqual(c.id, original.id)
        XCTAssertEqual(c.name, original.name)
        XCTAssertEqual(c.scheme, original.scheme)
        XCTAssertEqual(c.slots, original.slots)
        XCTAssertEqual(c.background, EditorBackground.defaultPair)
        XCTAssertFalse(c.isStatic)
    }

    func testFreshInstallWritesFlagOnly() {
        let d = scratchDefaults()
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.integer(forKey: ThemeSettings.schemaVersionKey), 2)
        XCTAssertNil(d.string(forKey: ThemeSettings.selectedThemeKey))
        XCTAssertNil(d.data(forKey: ThemeSettings.customThemesKey))
    }

    func testMigrationDeletesLegacyKeysAndWritesFlag() {
        let d = scratchDefaults()
        d.set(Coloring.standard.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("std.rgb", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("#123456", forKey: ThemeSettings.customBackgroundKey)
        d.set("bg.gray", forKey: ThemeSettings.backgroundPresetKey)
        d.set(ThemeSettings.encodeCustoms([]), forKey: ThemeSettings.customsKey)
        ThemeSettings.migrateIfNeeded(d)

        XCTAssertNil(d.object(forKey: ThemeSettings.schemeKey))
        XCTAssertNil(d.object(forKey: ThemeSettings.themeIdKey))
        XCTAssertNil(d.object(forKey: ThemeSettings.backgroundModeKey))
        XCTAssertNil(d.object(forKey: ThemeSettings.customBackgroundKey))
        XCTAssertNil(d.object(forKey: ThemeSettings.backgroundPresetKey))
        XCTAssertNil(d.object(forKey: ThemeSettings.customsKey))
        XCTAssertEqual(d.integer(forKey: ThemeSettings.schemaVersionKey), 2)
    }

    func testMigrationIsIdempotent() {
        let d = scratchDefaults()
        d.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "default")

        d.set("mutated", forKey: ThemeSettings.selectedThemeKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), "mutated")
    }

    func testMigrationPreservesCustomBackgroundsLibrary() {
        let d = scratchDefaults()
        d.set(["#111111", "#222222"], forKey: BackgroundLibrary.key)
        d.set(Coloring.off.rawValue, forKey: ThemeSettings.schemeKey)
        ThemeSettings.migrateIfNeeded(d)
        XCTAssertEqual(BackgroundLibrary.all(d), ["#111111", "#222222"])
    }

    func testMigrationNameCollisionTruncatesWithSuffix() {
        let d = scratchDefaults()
        let existing = Palette(id: "custom.existing", name: "Periwinkle", scheme: .unified,
                               slots: [ColorPair(light: "#111111", dark: "#222222")])
        d.set(ThemeSettings.encodeCustoms([existing]), forKey: ThemeSettings.customsKey)
        d.set(Coloring.unified.rawValue, forKey: ThemeSettings.schemeKey)
        d.set("uni.periwinkle", forKey: ThemeSettings.themeIdKey)
        d.set(BackgroundMode.preset.rawValue, forKey: ThemeSettings.backgroundModeKey)
        d.set("bg.cream", forKey: ThemeSettings.backgroundPresetKey)
        ThemeSettings.migrateIfNeeded(d)

        let customs = ThemeSettings.decodeCustoms(d.data(forKey: ThemeSettings.customThemesKey) ?? Data())
        XCTAssertEqual(customs.count, 2)
        XCTAssertEqual(customs.first { $0.id == "custom.existing" }?.name, "Periwinkle")
        let synthesized = customs.first { $0.id != "custom.existing" }
        XCTAssertEqual(synthesized?.name, "Periwink 2")
        XCTAssertEqual(d.string(forKey: ThemeSettings.selectedThemeKey), synthesized?.id)
    }
}
