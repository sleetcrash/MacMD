import AppKit

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

/// The theme background's brightness math plus the appearance/color resolution
/// the document views and the Settings preview share. Separated from the views
/// so the light-vs-dark decision stays unit-testable (the CursorGeometry /
/// LineNumbering pattern).
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

    /// The editor's Default background under each mode, matching the resolved
    /// `.textBackgroundColor` (white in Light, near-black in Dark). Drawn by the
    /// Theme dropdown's Default swatch and the preview pane.
    static func defaultBackground(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1) : .white
    }

    /// `defaultBackground` as a pair, for the dropdown's light | dark swatches.
    static let defaultPair = ColorPair(light: "#FFFFFF", dark: "#1E1E1E")

    /// The appearance a theme's background should force: a static background's
    /// own luminance (so its text stays readable regardless of Mode), or the
    /// Mode passthrough for a dynamic background that already follows it. A
    /// static background whose light hex is unparseable falls through to the
    /// Mode rather than an appearance-dependent labelColor guess.
    static func effectiveAppearance(background: ColorPair, isStatic: Bool,
                                    appearance: AppAppearance) -> AppAppearance {
        guard isStatic, let light = isLight(hex: background.light) else { return appearance }
        return light ? .light : .dark
    }

    /// The color a theme's background should paint, or nil for the default
    /// pair so consumers keep painting the semantic `.textBackgroundColor`.
    static func activeColor(background: ColorPair, dark: Bool) -> NSColor? {
        guard background != defaultPair else { return nil }
        return dark ? background.nsDark : background.nsLight
    }
}

/// The saved custom-background swatches (uppercase `#RRGGBB` strings) the Theme
/// Builder offers as background quick-picks. Saving a theme whose
/// background well was set from the color panel adds that color here.
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
