import AppKit

/// The editor background mode. Default follows the Light/Dark Mode (today's
/// behavior); Preset paints a curated light/dark pair that also follows the
/// Mode; Custom paints a fixed user-picked color and derives readable text
/// from that color's luminance instead of the Mode.
enum BackgroundMode: String, CaseIterable {
    case `default`, preset, custom
}

/// A curated editor-background pair: one color per Mode side, so a preset
/// keeps following Light/Dark/System like Default does. (Default itself is
/// the white | near-black pair the mode's `.textBackgroundColor` resolves to.)
struct BackgroundPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let pair: ColorPair

    static let all: [BackgroundPreset] = [
        BackgroundPreset(id: "bg.cream", name: "Cream",
                         pair: ColorPair(light: "#F8F1E1", dark: "#14213D")),   // cream | navy
        BackgroundPreset(id: "bg.parchment", name: "Parchment",
                         pair: ColorPair(light: "#EFE3C4", dark: "#2E2E2E")),   // parchment | charcoal
        BackgroundPreset(id: "bg.gray", name: "Gray",
                         pair: ColorPair(light: "#E9E9E9", dark: "#3C3C3C")),   // light | dark gray
    ]

    static func preset(id: String?) -> BackgroundPreset? {
        id.flatMap { wanted in all.first { $0.id == wanted } }
    }
}

/// The custom editor background's brightness math plus the mode/color
/// resolution the document views and the Settings preview share. Separated
/// from the views so the light-vs-dark decision stays unit-testable (the
/// CursorGeometry / LineNumbering pattern).
enum EditorBackground {
    /// Perceived brightness (Rec. 601 luma) of sRGB components in 0...1.
    static func luma(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Whether a `#RRGGBB` color reads as light (so text on it must be dark),
    /// or nil for malformed input.
    static func isLight(hex: String) -> Bool? {
        NSColor(hex: hex).map(isLight)
    }

    /// Whether `color` reads as light. Threshold 0.5: at or above is light.
    static func isLight(_ color: NSColor) -> Bool {
        let c = color.usingColorSpace(.sRGB) ?? color
        return luma(r: c.redComponent, g: c.greenComponent, b: c.blueComponent) >= 0.5
    }

    /// The appearance the document window should force: the custom background's
    /// luminance when one is active (a light background gets the light
    /// appearance, so body text and heading variants resolve dark and stay
    /// readable), else the chosen Mode. A custom mode without a usable color
    /// falls back to the Mode, so a half-configured Custom never changes the look.
    static func effectiveAppearance(mode: BackgroundMode, hex: String?,
                                    appearance: AppAppearance) -> AppAppearance {
        guard mode == .custom, let hex, let light = isLight(hex: hex) else { return appearance }
        return light ? .light : .dark
    }

    /// The color to paint as the editor background, or nil to keep the
    /// appearance-driven `.textBackgroundColor` default.
    static func customColor(mode: BackgroundMode, hex: String?) -> NSColor? {
        guard mode == .custom, let hex else { return nil }
        return NSColor(hex: hex)
    }

    /// A preset's color for the resolved Mode side, or nil for an unknown id
    /// (the editor then behaves as Default).
    static func presetColor(id: String?, dark: Bool) -> NSColor? {
        guard let preset = BackgroundPreset.preset(id: id) else { return nil }
        return dark ? preset.pair.nsDark : preset.pair.nsLight
    }

    /// What the editor paints for the full background selection, or nil for
    /// the appearance-driven default. One switch shared by the document view
    /// and the Settings preview so the two can never disagree.
    static func activeColor(mode: BackgroundMode, hex: String?, presetId: String?,
                            dark: Bool) -> NSColor? {
        switch mode {
        case .default: return nil
        case .custom: return customColor(mode: mode, hex: hex)
        case .preset: return presetColor(id: presetId, dark: dark)
        }
    }

    /// The editor's Default background under each mode, matching the resolved
    /// `.textBackgroundColor` (white in Light, near-black in Dark). Drawn by the
    /// Background dropdown's Default swatch and the preview pane.
    static func defaultBackground(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1) : .white
    }

    /// `defaultBackground` as a pair, for the dropdown's light | dark swatches.
    static let defaultPair = ColorPair(light: "#FFFFFF", dark: "#1E1E1E")
}

/// The saved custom-background swatches (uppercase `#RRGGBB` strings), listed
/// in the Background dropdown like the custom themes in the Theme dropdown.
/// Saving the Settings window with a custom background adds its color here.
enum BackgroundLibrary {
    static let key = "customBackgrounds"

    static func all(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// Append a valid, not-yet-saved color; malformed input and duplicates are
    /// silently ignored.
    static func add(_ hex: String, to defaults: UserDefaults = .standard) {
        let normalized = hex.uppercased()
        guard NSColor(hex: normalized) != nil else { return }
        var list = all(defaults)
        guard !list.contains(normalized) else { return }
        list.append(normalized)
        defaults.set(list, forKey: key)
    }

    static func remove(_ hex: String, from defaults: UserDefaults = .standard) {
        var list = all(defaults)
        list.removeAll { $0.caseInsensitiveCompare(hex) == .orderedSame }
        defaults.set(list, forKey: key)
    }
}
