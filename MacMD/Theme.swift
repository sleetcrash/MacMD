import AppKit

@MainActor
enum Theme {
    static let editorLineSpacing: CGFloat = 4

    private(set) static var editorFontSize: CGFloat = FontSize.standard
    private(set) static var editorFont: NSFont = monospaced(FontSize.standard)
    private static var headingFonts: [NSFont] = makeHeadingFonts(base: FontSize.standard)

    /// Clamps to the supported range and rebuilds the cached fonts. Returns
    /// whether the size actually changed, so callers can skip a re-highlight.
    @discardableResult
    static func setEditorFontSize(_ size: CGFloat) -> Bool {
        let clamped = FontSize.clamp(size)
        guard clamped != editorFontSize else { return false }
        editorFontSize = clamped
        editorFont = monospaced(clamped)
        headingFonts = makeHeadingFonts(base: clamped)
        return true
    }

    static func headingFont(level: Int) -> NSFont {
        let clamped = max(1, min(6, level))
        return headingFonts[clamped - 1]
    }

    private static func monospaced(_ size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func makeHeadingFonts(base: CGFloat) -> [NSFont] {
        (1...6).map { level in
            let bump = CGFloat(7 - level)
            return .monospacedSystemFont(ofSize: base + bump, weight: .bold)
        }
    }

    // MARK: - Active theming (single source of truth for the highlighter)

    private(set) static var activeColoring: Coloring = .off
    private(set) static var activePalette: Palette = ColorTheming.standardPresets[0]

    /// Sets the active coloring + palette. Returns whether anything changed, so
    /// callers can skip a re-highlight (mirrors `setEditorFontSize`).
    /// Precondition: `palette.scheme` must match `coloring`, except under `.off`.
    @discardableResult
    static func setActiveTheme(coloring: Coloring, palette: Palette?) -> Bool {
        assert(palette == nil || coloring == .off || palette?.scheme == coloring,
               "setActiveTheme: palette.scheme must match coloring")
        let newPalette = palette ?? activePalette
        guard coloring != activeColoring || newPalette != activePalette else { return false }
        activeColoring = coloring
        activePalette = newPalette
        return true
    }

    /// The dynamic color for a heading of `level` under the active theme.
    /// Default scheme → `labelColor` (headings are bold + sized only).
    static func headingColor(level: Int) -> NSColor {
        guard activeColoring != .off else { return .labelColor }
        return activePalette.headingColor(level: level)
    }

    static var textColor: NSColor { .labelColor }
    static var mutedColor: NSColor { .secondaryLabelColor }
    static var accentColor: NSColor { .controlAccentColor }
    static var linkColor: NSColor { .linkColor }
    static var codeBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            var resolved: NSColor = .clear
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            }
            return resolved
        }
    }

    static let bodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = editorLineSpacing
        style.defaultTabInterval = 28
        style.tabStops = []
        return style
    }()
}
