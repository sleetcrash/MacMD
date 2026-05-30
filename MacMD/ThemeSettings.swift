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

    // MARK: - Pure resolver (unit-tested)

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

    // MARK: - UserDefaults accessors (exercised by the live smoke test)

    static var coloring: Coloring {
        Coloring(rawValue: UserDefaults.standard.string(forKey: schemeKey) ?? "") ?? .off
    }

    static var appAppearance: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system
    }

    /// Defaults to the Standard default id; `resolvePalette` corrects any scheme mismatch.
    static var selectedThemeId: String {
        UserDefaults.standard.string(forKey: themeIdKey) ?? ColorTheming.defaultStandardId
    }

    static func savedCustoms() -> [Palette] {
        decodeCustoms(UserDefaults.standard.data(forKey: customsKey) ?? Data())
    }
}
