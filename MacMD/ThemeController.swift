import SwiftUI
import AppKit

/// Holds the EFFECTIVE theming selection the editor renders, the coloring
/// scheme, the selected theme id, the editor font size, and the window
/// appearance. This is kept separate from the persisted "saved" state
/// (UserDefaults) so the Settings window can Apply changes to the live
/// document without persisting them, and revert them on Close. Saved custom
/// palettes persist immediately elsewhere.
@MainActor
final class ThemeController: ObservableObject {
    @Published private(set) var coloring: Coloring
    @Published private(set) var themeId: String
    @Published private(set) var fontSize: Double
    @Published private(set) var appearance: AppAppearance
    @Published private(set) var fontFamilyId: String
    @Published private(set) var cursorStyle: CursorStyle
    @Published private(set) var cursorBlink: Bool
    /// The caret's fixed color as `#RRGGBB`, or nil for the system accent.
    @Published private(set) var cursorColorHex: String?
    @Published private(set) var backgroundMode: BackgroundMode
    @Published private(set) var customBackgroundHex: String?
    /// The selected BackgroundPreset id (meaningful under `.preset` mode).
    @Published private(set) var backgroundPresetId: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.coloring = ThemeController.loadColoring(defaults)
        self.themeId = ThemeController.loadThemeId(defaults)
        self.fontSize = ThemeController.loadFontSize(defaults)
        self.appearance = ThemeController.loadAppearance(defaults)
        self.fontFamilyId = ThemeController.loadFontFamilyId(defaults)
        self.cursorStyle = ThemeController.loadCursorStyle(defaults)
        self.cursorBlink = ThemeController.loadCursorBlink(defaults)
        self.cursorColorHex = ThemeController.loadCursorColor(defaults)
        self.backgroundMode = ThemeController.loadBackgroundMode(defaults)
        self.customBackgroundHex = ThemeController.loadCustomBackground(defaults)
        self.backgroundPresetId = ThemeController.loadBackgroundPreset(defaults)
    }

    // MARK: - Saved (persisted) state

    var savedColoring: Coloring { ThemeController.loadColoring(defaults) }
    var savedThemeId: String { ThemeController.loadThemeId(defaults) }
    var savedFontSize: Double { ThemeController.loadFontSize(defaults) }
    var savedAppearance: AppAppearance { ThemeController.loadAppearance(defaults) }
    var savedFontFamilyId: String { ThemeController.loadFontFamilyId(defaults) }
    var savedCursorStyle: CursorStyle { ThemeController.loadCursorStyle(defaults) }
    var savedCursorBlink: Bool { ThemeController.loadCursorBlink(defaults) }
    var savedCursorColor: String? { ThemeController.loadCursorColor(defaults) }
    var savedBackgroundMode: BackgroundMode { ThemeController.loadBackgroundMode(defaults) }
    var savedCustomBackground: String? { ThemeController.loadCustomBackground(defaults) }
    var savedBackgroundPreset: String? { ThemeController.loadBackgroundPreset(defaults) }

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

    /// Preview an editor background in the live document without persisting it.
    func applyBackground(mode: BackgroundMode, hex: String?, presetId: String?) {
        self.backgroundMode = mode
        self.customBackgroundHex = hex
        self.backgroundPresetId = presetId
    }

    /// Persist and apply the editor background. The hex and preset id are kept
    /// even under other modes, so a previous pick stays remembered.
    func saveBackground(mode: BackgroundMode, hex: String?, presetId: String?) {
        defaults.set(mode.rawValue, forKey: ThemeSettings.backgroundModeKey)
        if let hex {
            defaults.set(hex, forKey: ThemeSettings.customBackgroundKey)
        } else {
            defaults.removeObject(forKey: ThemeSettings.customBackgroundKey)
        }
        if let presetId {
            defaults.set(presetId, forKey: ThemeSettings.backgroundPresetKey)
        } else {
            defaults.removeObject(forKey: ThemeSettings.backgroundPresetKey)
        }
        applyBackground(mode: mode, hex: hex, presetId: presetId)
    }

    /// Discard any unsaved Apply and snap the effective state back to saved.
    func revertToSaved() {
        apply(coloring: savedColoring, themeId: savedThemeId,
              fontSize: savedFontSize, appearance: savedAppearance)
        self.fontFamilyId = savedFontFamilyId
        self.cursorStyle = savedCursorStyle
        self.cursorBlink = savedCursorBlink
        self.cursorColorHex = savedCursorColor
        applyBackground(mode: savedBackgroundMode, hex: savedCustomBackground,
                        presetId: savedBackgroundPreset)
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
    private static func loadBackgroundMode(_ d: UserDefaults) -> BackgroundMode {
        BackgroundMode(rawValue: d.string(forKey: ThemeSettings.backgroundModeKey) ?? "") ?? .default
    }
    private static func loadCustomBackground(_ d: UserDefaults) -> String? {
        d.string(forKey: ThemeSettings.customBackgroundKey)
    }
    private static func loadBackgroundPreset(_ d: UserDefaults) -> String? {
        d.string(forKey: ThemeSettings.backgroundPresetKey)
    }
}
