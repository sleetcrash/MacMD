import AppKit

/// The editor background mode. Default follows the Light/Dark Mode (today's
/// behavior); Custom paints a fixed user-picked color and derives readable text
/// from that color's luminance instead of the Mode.
enum BackgroundMode: String, CaseIterable {
    case `default`, custom
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

    /// The editor's Default background under each mode, matching the resolved
    /// `.textBackgroundColor` (white in Light, near-black in Dark). Drawn by the
    /// Background dropdown's Default swatch and the preview pane.
    static func defaultBackground(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1) : .white
    }
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
