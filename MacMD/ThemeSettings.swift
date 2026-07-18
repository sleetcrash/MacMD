import Foundation

/// Single source of truth for the theming selection: plain UserDefaults keys
/// plus the total theme resolver. The SwiftUI layer reads `customThemes`
/// through `@AppStorage`; the document views resolve the active theme and hand
/// its palette to `Theme.setActiveTheme`.
enum ThemeSettings {
    static let appearanceKey = "appAppearance"
    static let fontFamilyKey = "editorFontFamily"
    static let cursorStyleKey = "cursorStyle"
    static let cursorBlinkKey = "cursorBlink"
    static let cursorColorKey = "cursorColor"
    static let selectedThemeKey = "selectedTheme"
    static let customThemesKey = "customThemes"
    static let schemaVersionKey = "themeSchemaVersion"

    // MARK: - Total resolver (unit-tested)

    /// The total theme resolver: every id class in one flat lookup, no
    /// `Coloring` gate. Lookup order mirrors the Theme dropdown's sections:
    /// the built-in Default, then tints, then Standard presets, then Unified
    /// presets, then the caller's customs. Never returns nil; an unknown id
    /// falls back to `Palette.defaultTheme` so the editor always has a theme.
    static func resolveTheme(id: String, customs: [Palette]) -> Palette {
        if id == "default" { return Palette.defaultTheme }
        if let tint = Palette.tintThemes.first(where: { $0.id == id }) { return tint }
        if let standard = ColorTheming.standardPresets.first(where: { $0.id == id }) { return standard }
        if let unified = ColorTheming.unifiedPresets.first(where: { $0.id == id }) { return unified }
        if let custom = customs.first(where: { $0.id == id }) { return custom }
        return Palette.defaultTheme
    }

    static func encodeCustoms(_ palettes: [Palette]) -> Data {
        (try? JSONEncoder().encode(palettes)) ?? Data()
    }

    static func decodeCustoms(_ data: Data) -> [Palette] {
        (try? JSONDecoder().decode([Palette].self, from: data)) ?? []
    }

    static func savedCustoms(_ defaults: UserDefaults = .standard) -> [Palette] {
        decodeCustoms(defaults.data(forKey: customThemesKey) ?? Data())
    }

    // MARK: - One-shot legacy migration (Task 4)

    /// The pre-theme-owned-backgrounds per-key prefs, scoped to migration: they
    /// are read once, then deleted, and nothing else in the app references them.
    private enum Legacy {
        static let schemeKey = "colorScheme"
        static let themeIdKey = "themeId"
        static let backgroundModeKey = "backgroundMode"
        static let customBackgroundKey = "customBackground"
        static let backgroundPresetKey = "backgroundPreset"
        static let customsKey = "customPalettes"

        static var allKeys: [String] {
            [schemeKey, themeIdKey, backgroundModeKey, customBackgroundKey, backgroundPresetKey, customsKey]
        }
    }

    /// The pre-theme-owned-backgrounds scheme/id resolution, kept private for
    /// the migrator alone: nil under the Default scheme, else the matching preset
    /// or custom, else the scheme's first preset. The live app resolves through
    /// `resolveTheme` now.
    private static func legacyResolve(coloring: Coloring, themeId: String, customs: [Palette]) -> Palette? {
        guard coloring != .off else { return nil }
        if let preset = ColorTheming.preset(id: themeId), preset.scheme == coloring { return preset }
        if let custom = customs.first(where: { $0.id == themeId && $0.scheme == coloring }) { return custom }
        return ColorTheming.presets(for: coloring).first
    }

    /// Migrates the legacy per-key prefs into the unified `customThemes`/
    /// `selectedTheme` shape, deletes the six legacy keys, and bumps
    /// `themeSchemaVersion` to 2. Runs at most once per defaults domain (the
    /// version guard makes a second call a no-op) and only when at least one
    /// legacy key is present; a fresh install just writes the flag. Legacy state
    /// is read through the old resolution semantics so the migrated theme matches
    /// what the user was actually seeing, including a colorScheme/themeId mismatch
    /// resolving to the scheme's first preset.
    static func migrateIfNeeded(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: schemaVersionKey) < 2 else { return }

        guard Legacy.allKeys.contains(where: { defaults.object(forKey: $0) != nil }) else {
            defaults.set(2, forKey: schemaVersionKey)
            return
        }

        let coloring = Coloring(rawValue: defaults.string(forKey: Legacy.schemeKey) ?? "") ?? .off
        let themeId = defaults.string(forKey: Legacy.themeIdKey) ?? ColorTheming.defaultStandardId
        let legacyCustoms = decodeCustoms(defaults.data(forKey: Legacy.customsKey) ?? Data())
        let resolved = legacyResolve(coloring: coloring, themeId: themeId, customs: legacyCustoms)
        let selectedCustom = resolved.flatMap { r in legacyCustoms.first { $0.id == r.id && $0.scheme == r.scheme } }

        let mode = defaults.string(forKey: Legacy.backgroundModeKey) ?? "default"
        let hex = defaults.string(forKey: Legacy.customBackgroundKey)
        let presetId = defaults.string(forKey: Legacy.backgroundPresetKey)

        var migrated: [Palette] = []
        var names = Set<String>()

        func uniqueName(_ base: String) -> String {
            guard names.contains(base) else { return base }
            var n = 2
            while true {
                let suffix = " \(n)"
                let truncated = String(base.prefix(max(0, 10 - suffix.count)))
                let candidate = truncated + suffix
                if !names.contains(candidate) { return candidate }
                n += 1
            }
        }

        @discardableResult
        func add(id: String, name: String, scheme: Coloring, slots: [ColorPair],
                background: ColorPair, isStatic: Bool) -> Palette {
            let finalName = uniqueName(name)
            names.insert(finalName)
            let palette = Palette(id: id, name: finalName, scheme: scheme, slots: slots,
                                  background: background, isStatic: isStatic)
            migrated.append(palette)
            return palette
        }

        // Rec. 601 luminance side of hex H: light collapses pairs to their
        // light value, dark to their dark value, both sides stored identical.
        func collapsed(_ pair: ColorPair, toDark: Bool) -> ColorPair {
            toDark ? ColorPair(light: pair.dark, dark: pair.dark) : ColorPair(light: pair.light, dark: pair.light)
        }

        for c in legacyCustoms where c.id != selectedCustom?.id {
            add(id: c.id, name: c.name, scheme: c.scheme, slots: c.slots,
               background: EditorBackground.defaultPair, isStatic: false)
        }

        let selectedThemeId: String

        if coloring == .off {
            switch mode {
            case "preset":
                if let preset = BackgroundPreset.preset(id: presetId) {
                    selectedThemeId = preset.id.replacingOccurrences(of: "bg.", with: "tint.")
                } else {
                    selectedThemeId = "default"
                }
            case "custom":
                if let hex, EditorBackground.isLight(hex: hex) != nil {
                    let bg = ColorPair(light: hex, dark: hex)
                    let p = add(id: "custom.\(UUID().uuidString)", name: "Custom", scheme: .off,
                               slots: [], background: bg, isStatic: true)
                    selectedThemeId = p.id
                } else {
                    selectedThemeId = "default"
                }
            default:
                selectedThemeId = "default"
            }
        } else if let selectedCustom {
            switch mode {
            case "preset":
                if let preset = BackgroundPreset.preset(id: presetId) {
                    let p = add(id: selectedCustom.id, name: selectedCustom.name, scheme: selectedCustom.scheme,
                               slots: selectedCustom.slots, background: preset.pair, isStatic: false)
                    selectedThemeId = p.id
                } else {
                    let p = add(id: selectedCustom.id, name: selectedCustom.name, scheme: selectedCustom.scheme,
                               slots: selectedCustom.slots, background: EditorBackground.defaultPair, isStatic: false)
                    selectedThemeId = p.id
                }
            case "custom":
                if let hex, let isLight = EditorBackground.isLight(hex: hex) {
                    let slots = selectedCustom.slots.map { collapsed($0, toDark: !isLight) }
                    let bg = ColorPair(light: hex, dark: hex)
                    let p = add(id: selectedCustom.id, name: selectedCustom.name, scheme: selectedCustom.scheme,
                               slots: slots, background: bg, isStatic: true)
                    selectedThemeId = p.id
                } else {
                    let p = add(id: selectedCustom.id, name: selectedCustom.name, scheme: selectedCustom.scheme,
                               slots: selectedCustom.slots, background: EditorBackground.defaultPair, isStatic: false)
                    selectedThemeId = p.id
                }
            default:
                let p = add(id: selectedCustom.id, name: selectedCustom.name, scheme: selectedCustom.scheme,
                           slots: selectedCustom.slots, background: EditorBackground.defaultPair, isStatic: false)
                selectedThemeId = p.id
            }
        } else if let resolved {
            switch mode {
            case "preset":
                if let preset = BackgroundPreset.preset(id: presetId) {
                    let p = add(id: "custom.\(UUID().uuidString)", name: resolved.name, scheme: resolved.scheme,
                               slots: resolved.slots, background: preset.pair, isStatic: false)
                    selectedThemeId = p.id
                } else {
                    selectedThemeId = resolved.id
                }
            case "custom":
                if let hex, let isLight = EditorBackground.isLight(hex: hex) {
                    let slots = resolved.slots.map { collapsed($0, toDark: !isLight) }
                    let bg = ColorPair(light: hex, dark: hex)
                    let p = add(id: "custom.\(UUID().uuidString)", name: resolved.name, scheme: resolved.scheme,
                               slots: slots, background: bg, isStatic: true)
                    selectedThemeId = p.id
                } else {
                    selectedThemeId = resolved.id
                }
            default:
                selectedThemeId = resolved.id
            }
        } else {
            // Unreachable for non-off schemes: legacyResolve always falls back
            // to the scheme's first preset, so `resolved` is never nil here.
            selectedThemeId = "default"
        }

        defaults.set(encodeCustoms(migrated), forKey: customThemesKey)
        defaults.set(selectedThemeId, forKey: selectedThemeKey)
        for key in Legacy.allKeys { defaults.removeObject(forKey: key) }
        defaults.set(2, forKey: schemaVersionKey)
    }
}
