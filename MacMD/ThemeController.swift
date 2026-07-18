import SwiftUI
import AppKit

/// Holds the EFFECTIVE theming selection the editor renders: the selected theme
/// id, the editor font size, and the window appearance. This is kept separate
/// from the persisted "saved" state (UserDefaults) so the Settings window can
/// Apply changes to the live document without persisting them, and revert them
/// on Close. Saved custom themes persist immediately elsewhere.
@MainActor
final class ThemeController: ObservableObject {
    /// The single theme selection; its value domain is the full id space
    /// (default, tints, standard/unified presets, and custom ids).
    @Published private(set) var themeId: String
    @Published private(set) var fontSize: Double
    @Published private(set) var appearance: AppAppearance
    @Published private(set) var fontFamilyId: String
    @Published private(set) var cursorStyle: CursorStyle
    @Published private(set) var cursorBlink: Bool
    /// The caret's fixed color as `#RRGGBB`, or nil for the system accent.
    @Published private(set) var cursorColorHex: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        ThemeSettings.migrateIfNeeded(defaults)
        self.defaults = defaults
        self.themeId = ThemeController.loadThemeId(defaults)
        self.fontSize = ThemeController.loadFontSize(defaults)
        self.appearance = ThemeController.loadAppearance(defaults)
        self.fontFamilyId = ThemeController.loadFontFamilyId(defaults)
        self.cursorStyle = ThemeController.loadCursorStyle(defaults)
        self.cursorBlink = ThemeController.loadCursorBlink(defaults)
        self.cursorColorHex = ThemeController.loadCursorColor(defaults)
    }

    /// The palette for the current selection, resolved against the saved
    /// customs. Never nil; an unknown id resolves to `Palette.defaultTheme`
    /// while `themeId` keeps its raw value.
    var resolvedTheme: Palette {
        ThemeSettings.resolveTheme(id: themeId, customs: ThemeSettings.savedCustoms(defaults))
    }

    // MARK: - Saved (persisted) state

    var savedThemeId: String { ThemeController.loadThemeId(defaults) }
    var savedFontSize: Double { ThemeController.loadFontSize(defaults) }
    var savedAppearance: AppAppearance { ThemeController.loadAppearance(defaults) }
    var savedFontFamilyId: String { ThemeController.loadFontFamilyId(defaults) }
    var savedCursorStyle: CursorStyle { ThemeController.loadCursorStyle(defaults) }
    var savedCursorBlink: Bool { ThemeController.loadCursorBlink(defaults) }
    var savedCursorColor: String? { ThemeController.loadCursorColor(defaults) }

    // MARK: - Transitions

    /// Show these settings in the live document without persisting them.
    func apply(themeId: String, fontSize: Double, appearance: AppAppearance) {
        self.themeId = themeId
        self.fontSize = Double(FontSize.clamp(CGFloat(fontSize)))
        self.appearance = appearance
    }

    /// Persist these settings (survives relaunch) and apply them.
    func save(themeId: String, fontSize: Double, appearance: AppAppearance) {
        let size = Double(FontSize.clamp(CGFloat(fontSize)))
        defaults.set(themeId, forKey: ThemeSettings.selectedThemeKey)
        defaults.set(size, forKey: FontSize.key)
        defaults.set(appearance.rawValue, forKey: ThemeSettings.appearanceKey)
        apply(themeId: themeId, fontSize: size, appearance: appearance)
    }

    /// Preview a font family in the live editor without persisting it.
    func applyFontFamily(_ id: String) {
        self.fontFamilyId = id
    }

    /// Persist and apply the font family.
    func saveFontFamily(_ id: String) {
        defaults.set(id, forKey: ThemeSettings.fontFamilyKey)
        self.fontFamilyId = id
    }

    /// Preview the cursor in the live editor without persisting it.
    func applyCursor(style: CursorStyle, blink: Bool) {
        self.cursorStyle = style
        self.cursorBlink = blink
    }

    /// Persist and apply the cursor settings.
    func saveCursor(style: CursorStyle, blink: Bool) {
        defaults.set(style.rawValue, forKey: ThemeSettings.cursorStyleKey)
        defaults.set(blink, forKey: ThemeSettings.cursorBlinkKey)
        self.cursorStyle = style
        self.cursorBlink = blink
    }

    /// Preview a caret color in the live editor without persisting it.
    func applyCursorColor(_ hex: String?) {
        self.cursorColorHex = hex
    }

    /// Persist and apply the caret color (nil restores the system accent).
    func saveCursorColor(_ hex: String?) {
        if let hex {
            defaults.set(hex, forKey: ThemeSettings.cursorColorKey)
        } else {
            defaults.removeObject(forKey: ThemeSettings.cursorColorKey)
        }
        self.cursorColorHex = hex
    }

    /// Discard any unsaved Apply and snap the effective state back to saved.
    func revertToSaved() {
        apply(themeId: savedThemeId, fontSize: savedFontSize, appearance: savedAppearance)
        self.fontFamilyId = savedFontFamilyId
        self.cursorStyle = savedCursorStyle
        self.cursorBlink = savedCursorBlink
        self.cursorColorHex = savedCursorColor
    }

    /// Immediately change AND persist only the font size (for the View-menu
    /// Cmd-+/-/0 commands), leaving the saved theme untouched.
    func setFontSizeImmediate(_ size: CGFloat) {
        let clamped = Double(FontSize.clamp(size))
        self.fontSize = clamped
        defaults.set(clamped, forKey: FontSize.key)
    }

    func adjustFontSize(by delta: CGFloat) { setFontSizeImmediate(CGFloat(fontSize) + delta) }
    func resetFontSize() { setFontSizeImmediate(FontSize.standard) }

    // MARK: - Loaders

    private static func loadThemeId(_ d: UserDefaults) -> String {
        d.string(forKey: ThemeSettings.selectedThemeKey) ?? "default"
    }
    private static func loadFontSize(_ d: UserDefaults) -> Double {
        let stored = d.object(forKey: FontSize.key) as? Double
        return Double(FontSize.clamp(CGFloat(stored ?? Double(FontSize.standard))))
    }
    private static func loadAppearance(_ d: UserDefaults) -> AppAppearance {
        // Dark is the out-of-box Mode (Evan's call, 2026-07-12); System and
        // Light remain one Settings click away.
        AppAppearance(rawValue: d.string(forKey: ThemeSettings.appearanceKey) ?? "") ?? .dark
    }
    private static func loadFontFamilyId(_ d: UserDefaults) -> String {
        let stored = d.string(forKey: ThemeSettings.fontFamilyKey) ?? FontFamily.default.id
        return FontFamily.all.contains(where: { $0.id == stored }) ? stored : FontFamily.default.id
    }
    private static func loadCursorStyle(_ d: UserDefaults) -> CursorStyle {
        CursorStyle(rawValue: d.string(forKey: ThemeSettings.cursorStyleKey) ?? "") ?? .bar
    }
    private static func loadCursorBlink(_ d: UserDefaults) -> Bool {
        d.object(forKey: ThemeSettings.cursorBlinkKey) == nil ? true : d.bool(forKey: ThemeSettings.cursorBlinkKey)
    }
    private static func loadCursorColor(_ d: UserDefaults) -> String? {
        d.string(forKey: ThemeSettings.cursorColorKey)
    }
}
