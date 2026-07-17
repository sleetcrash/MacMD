import Foundation

/// Single source of truth for the theming selection, mirroring `FontSize`:
/// plain UserDefaults keys plus a pure resolver. The SwiftUI layer reads these
/// keys through `@AppStorage`; the document views resolve the active palette
/// and hand it to `Theme.setActiveTheme`.
enum ThemeSettings {
    static let schemeKey = "colorScheme"
    static let themeIdKey = "themeId"
    static let appearanceKey = "appAppearance"
    static let customsKey = "customPalettes"
    static let fontFamilyKey = "editorFontFamily"
    static let cursorStyleKey = "cursorStyle"
    static let cursorBlinkKey = "cursorBlink"
    static let cursorColorKey = "cursorColor"
    static let backgroundModeKey = "backgroundMode"
    static let customBackgroundKey = "customBackground"
    static let backgroundPresetKey = "backgroundPreset"
    static let selectedThemeKey = "selectedTheme"
    static let customThemesKey = "customThemes"
    static let schemaVersionKey = "themeSchemaVersion"

    // MARK: - Pure resolver (unit-tested)

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

    /// The palette for the current selection, or nil under the Default scheme.
    /// Unknown ids fall back to the scheme's first preset so the editor never
    /// renders an empty selection.
    static func resolvePalette(coloring: Coloring, themeId: String, customs: [Palette]) -> Palette? {
        guard coloring != .off else { return nil }
        if let preset = ColorTheming.preset(id: themeId), preset.scheme == coloring { return preset }
        if let custom = customs.first(where: { $0.id == themeId && $0.scheme == coloring }) { return custom }
        return ColorTheming.presets(for: coloring).first
    }

    static func encodeCustoms(_ palettes: [Palette]) -> Data {
        (try? JSONEncoder().encode(palettes)) ?? Data()
    }

    static func decodeCustoms(_ data: Data) -> [Palette] {
        (try? JSONDecoder().decode([Palette].self, from: data)) ?? []
    }

    static func savedCustoms(_ defaults: UserDefaults = .standard) -> [Palette] {
        decodeCustoms(defaults.data(forKey: customsKey) ?? Data())
    }
}
