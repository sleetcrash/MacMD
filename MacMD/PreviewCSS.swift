import AppKit

/// Emits the preview's theme CSS, mirroring the editor's active palette, body
/// font, sizes, and code styling. Both a light (`html.aqua`) and a dark
/// (`html.darkAqua`) rule set are emitted; the preview activates one by setting a
/// class on the document element from `EditorBackground.effectiveAppearance`, so a
/// custom background flips the theme by luminance and the choice never depends on
/// the system `prefers-color-scheme`. Heading colors resolve from the PASSED
/// theme's palette (never `Theme.headingColor`, which reads the global active
/// palette and would ignore the argument).
@MainActor
enum PreviewCSS {
    static func css(theme: ThemeController) -> String {
        guard let light = NSAppearance(named: .aqua),
              let dark = NSAppearance(named: .darkAqua) else { return "" }

        let palette = ThemeSettings.resolvePalette(
            coloring: theme.coloring, themeId: theme.themeId, customs: ThemeSettings.savedCustoms())
        let base = CGFloat(theme.fontSize)
        let family = FontFamily.resolve(id: theme.fontFamilyId)
        let stack = fontStack(for: family.resolver, isMonospace: family.isMonospace)
        let customBg = EditorBackground.customColor(mode: theme.backgroundMode, hex: theme.customBackgroundHex)

        return block(class: "aqua", appearance: light, dark: false, palette: palette, base: base, fontStack: stack, customBg: customBg)
             + block(class: "darkAqua", appearance: dark, dark: true, palette: palette, base: base, fontStack: stack, customBg: customBg)
    }

    private static func block(class cls: String, appearance: NSAppearance, dark: Bool,
                              palette: Palette?, base: CGFloat, fontStack: String, customBg: NSColor?) -> String {
        let bg = (customBg ?? EditorBackground.defaultBackground(dark: dark)).hexString
        var css = """
        html.\(cls) body { color: \(hex(.labelColor, under: appearance)); background: \(bg); font-family: \(fontStack); font-size: \(fmt(base))px; }
        html.\(cls) a { color: \(hex(.linkColor, under: appearance)); }
        html.\(cls) code, html.\(cls) pre { font-family: ui-monospace, Menlo, monospace; font-size: \(fmt(base))px; background: \(codeBackgroundRGBA(under: appearance)); }
        html.\(cls) blockquote { color: \(hex(.secondaryLabelColor, under: appearance)); border-left-color: \(hex(.separatorColor, under: appearance)); }
        html.\(cls) th, html.\(cls) td, html.\(cls) hr { border-color: \(hex(.separatorColor, under: appearance)); }

        """
        for level in 1...6 {
            let color = palette?.headingColor(level: level) ?? .labelColor
            let size = base + CGFloat(7 - level)   // base+(7-level), mirroring Theme.makeHeadingFonts
            css += "html.\(cls) h\(level) { color: \(hex(color, under: appearance)); font-size: \(fmt(size))px; font-weight: bold; }\n"
        }
        return css
    }

    /// Resolve a (possibly dynamic) color to a `#RRGGBB` string under a specific
    /// appearance, so light and dark blocks get the right variant.
    private static func hex(_ color: NSColor, under appearance: NSAppearance) -> String {
        var result = "#000000"
        appearance.performAsCurrentDrawingAppearance { result = color.hexString }
        return result
    }

    /// The editor's translucent inline-code background (`secondaryLabel` at 10%)
    /// as an `rgba(...)`. A solid hex would not match the editor's layered look.
    private static func codeBackgroundRGBA(under appearance: NSAppearance) -> String {
        var rgba = "rgba(128, 128, 128, 0.1)"
        appearance.performAsCurrentDrawingAppearance {
            if let c = NSColor.secondaryLabelColor.withAlphaComponent(0.10).usingColorSpace(.sRGB) {
                let r = Int((c.redComponent * 255).rounded())
                let g = Int((c.greenComponent * 255).rounded())
                let b = Int((c.blueComponent * 255).rounded())
                let a = (Double(c.alphaComponent) * 100).rounded() / 100
                rgba = "rgba(\(r), \(g), \(b), \(fmtAlpha(a)))"
            }
        }
        return rgba
    }

    private static func fontStack(for resolver: FontFamily.Resolver, isMonospace: Bool) -> String {
        switch resolver {
        case .systemMono: return "ui-monospace, Menlo, monospace"
        case .system: return "-apple-system, system-ui, sans-serif"
        case .serif: return "ui-serif, \"New York\", Georgia, serif"
        case .named(let name):
            return isMonospace ? "\"\(name)\", ui-monospace, monospace" : "\"\(name)\", -apple-system, sans-serif"
        }
    }

    private static func fmt(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", Double(v))
    }

    private static func fmtAlpha(_ a: Double) -> String {
        String(format: "%g", a)
    }
}
