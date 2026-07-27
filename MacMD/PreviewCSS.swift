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

        let resolved = theme.resolvedTheme
        let palette: Palette? = resolved.scheme == .off ? nil : resolved
        let base = CGFloat(theme.fontSize)
        let family = FontFamily.resolve(id: theme.fontFamilyId)
        let stack = fontStack(for: family.resolver, isMonospace: family.isMonospace)
        // Resolved per side: a static theme's collapsed pair is the same in both
        // blocks, while a dynamic pair contributes its light color to `aqua` and
        // its dark color to `darkAqua`, exactly like the editor following the Mode.
        let lightBg = EditorBackground.activeColor(background: resolved.background, dark: false)
        let darkBg = EditorBackground.activeColor(background: resolved.background, dark: true)

        return block(class: "aqua", appearance: light, dark: false, palette: palette, base: base, fontStack: stack, customBg: lightBg)
             + block(class: "darkAqua", appearance: dark, dark: true, palette: palette, base: base, fontStack: stack, customBg: darkBg)
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
        // Front matter: muted block; keys follow the theme's H1 color (the editor
        // does the same), staying muted under the Default scheme.
        let fmKey = palette?.headingColor(level: 1) ?? .secondaryLabelColor
        css += "html.\(cls) .front-matter { color: \(hex(.secondaryLabelColor, under: appearance)); border-color: \(hex(.separatorColor, under: appearance)); background: \(codeBackgroundRGBA(under: appearance)); }\n"
        css += "html.\(cls) .front-matter .fm-key { color: \(hex(fmKey, under: appearance)); }\n"
        css += mermaidVariables(class: cls, appearance: appearance, palette: palette, background: customBg ?? EditorBackground.defaultBackground(dark: dark))
        return css
    }

    /// Diagram palette primitives, published as custom properties so the preview
    /// shell can map them onto mermaid's own variable names (the shell owns
    /// mermaid's vocabulary; this owns the colors). Mermaid bakes colors into the
    /// SVG, so a diagram cannot inherit them through CSS the way text does.
    private static func mermaidVariables(class cls: String, appearance: NSAppearance,
                                         palette: Palette?, background: NSColor) -> String {
        let bg = solid(background, under: appearance)
        // Exactly the body-text color the rest of this stylesheet emits, so a
        // diagram label and the prose beside it are the same color.
        let text = solid(.labelColor, under: appearance)
        // Node and actor fills: the code block's layered look, flattened, since a
        // diagram fill cannot be translucent without the arrows showing through.
        let surface = blend(text, into: bg, fraction: 0.10)
        let line = blend(text, into: bg, fraction: 0.45)

        var css = "html.\(cls) { --mmd-bg: \(bg.hexString); --mmd-text: \(text.hexString);"
        css += " --mmd-surface: \(surface.hexString); --mmd-line: \(line.hexString);"
        for (i, color) in seriesColors(palette: palette, under: appearance, text: text, bg: bg).enumerated() {
            css += " --mmd-series-\(i + 1): \(color.hexString);"
        }
        return css + " }\n"
    }

    /// Twelve series colors for multi-color diagrams (pie slices and kin). A themed
    /// palette cycles its heading colors, each pass blended further toward the
    /// background so a repeat never reads as the same slice; the Default scheme
    /// falls back to a neutral ramp of the body color, matching the node fills.
    private static func seriesColors(palette: Palette?, under appearance: NSAppearance,
                                     text: NSColor, bg: NSColor) -> [NSColor] {
        var base: [NSColor] = []
        if let palette {
            for level in 1...3 {
                let color = solid(palette.headingColor(level: level), under: appearance)
                if !base.contains(where: { $0.hexString == color.hexString }) { base.append(color) }
            }
        }
        if base.isEmpty {
            base = [0.85, 0.6, 0.35].map { blend(text, into: bg, fraction: $0) }
        }
        return (0..<12).map { i in
            let color = base[i % base.count]
            let cycle = CGFloat(i / base.count)
            return cycle == 0 ? color : blend(color, into: bg, fraction: 1 - cycle * 0.22)
        }
    }

    /// A dynamic color flattened to one opaque sRGB color under a specific
    /// appearance; mermaid bakes solid values and cannot take an rgba().
    private static func solid(_ color: NSColor, under appearance: NSAppearance) -> NSColor {
        var result = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            result = (color.usingColorSpace(.sRGB) ?? color).withAlphaComponent(1)
        }
        return result
    }

    /// `fraction` of `color` over `base`, both already sRGB and opaque.
    private static func blend(_ color: NSColor, into base: NSColor, fraction: CGFloat) -> NSColor {
        let f = min(max(fraction, 0), 1)
        guard let c = color.usingColorSpace(.sRGB), let b = base.usingColorSpace(.sRGB) else { return color }
        return NSColor(srgbRed: b.redComponent + (c.redComponent - b.redComponent) * f,
                       green: b.greenComponent + (c.greenComponent - b.greenComponent) * f,
                       blue: b.blueComponent + (c.blueComponent - b.blueComponent) * f,
                       alpha: 1)
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
