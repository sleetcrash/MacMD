import SwiftUI
import AppKit

/// Holds the EFFECTIVE theming selection the editor renders, the coloring
/// scheme, the selected theme id, the editor font size, and the window
/// appearance. This is kept separate from the persisted "saved" state
/// (UserDefaults) so the Appearance window can Apply changes to the live
/// document without persisting them, and revert them on Close. Saved custom
/// palettes persist immediately elsewhere.
@MainActor
final class ThemeController: ObservableObject {
    @Published private(set) var coloring: Coloring
    @Published private(set) var themeId: String
    @Published private(set) var fontSize: Double
    @Published private(set) var appearance: AppAppearance

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.coloring = ThemeController.loadColoring(defaults)
        self.themeId = ThemeController.loadThemeId(defaults)
        self.fontSize = ThemeController.loadFontSize(defaults)
        self.appearance = ThemeController.loadAppearance(defaults)
    }

    // MARK: - Saved (persisted) state

    var savedColoring: Coloring { ThemeController.loadColoring(defaults) }
    var savedThemeId: String { ThemeController.loadThemeId(defaults) }
    var savedFontSize: Double { ThemeController.loadFontSize(defaults) }
    var savedAppearance: AppAppearance { ThemeController.loadAppearance(defaults) }

    // MARK: - Transitions

    /// Show these settings in the live document without persisting them.
    func apply(coloring: Coloring, themeId: String, fontSize: Double, appearance: AppAppearance) {
        self.coloring = coloring
        self.themeId = themeId
        self.fontSize = Double(FontSize.clamp(CGFloat(fontSize)))
        self.appearance = appearance
    }

    /// Persist these settings (survives relaunch) and apply them.
    func save(coloring: Coloring, themeId: String, fontSize: Double, appearance: AppAppearance) {
        let size = Double(FontSize.clamp(CGFloat(fontSize)))
        defaults.set(coloring.rawValue, forKey: ThemeSettings.schemeKey)
        defaults.set(themeId, forKey: ThemeSettings.themeIdKey)
        defaults.set(size, forKey: FontSize.key)
        defaults.set(appearance.rawValue, forKey: ThemeSettings.appearanceKey)
        apply(coloring: coloring, themeId: themeId, fontSize: size, appearance: appearance)
    }

    /// Discard any unsaved Apply and snap the effective state back to saved.
    func revertToSaved() {
        apply(coloring: savedColoring, themeId: savedThemeId,
              fontSize: savedFontSize, appearance: savedAppearance)
    }

    /// Immediately change AND persist only the font size (for the View-menu
    /// Cmd-+/-/0 commands), leaving the saved coloring/theme untouched.
    func setFontSizeImmediate(_ size: CGFloat) {
        let clamped = Double(FontSize.clamp(size))
        self.fontSize = clamped
        defaults.set(clamped, forKey: FontSize.key)
    }

    func adjustFontSize(by delta: CGFloat) { setFontSizeImmediate(CGFloat(fontSize) + delta) }
    func resetFontSize() { setFontSizeImmediate(FontSize.standard) }

    // MARK: - Loaders

    private static func loadColoring(_ d: UserDefaults) -> Coloring {
        Coloring(rawValue: d.string(forKey: ThemeSettings.schemeKey) ?? "") ?? .off
    }
    private static func loadThemeId(_ d: UserDefaults) -> String {
        d.string(forKey: ThemeSettings.themeIdKey) ?? ColorTheming.defaultStandardId
    }
    private static func loadFontSize(_ d: UserDefaults) -> Double {
        let stored = d.object(forKey: FontSize.key) as? Double
        return Double(FontSize.clamp(CGFloat(stored ?? Double(FontSize.standard))))
    }
    private static func loadAppearance(_ d: UserDefaults) -> AppAppearance {
        AppAppearance(rawValue: d.string(forKey: ThemeSettings.appearanceKey) ?? "") ?? .system
    }
}
