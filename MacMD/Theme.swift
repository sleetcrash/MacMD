import AppKit

@MainActor
enum Theme {
    static let editorLineSpacing: CGFloat = 4

    private(set) static var editorFontSize: CGFloat = FontSize.standard
    private(set) static var editorFontFamily: FontFamily = .default
    private(set) static var editorFont: NSFont = FontFamily.default.font(size: FontSize.standard)
    /// Always-monospace font for inline and fenced code, so code stays legible
    /// under a proportional body font. Tracks the editor size, not the family.
    private(set) static var codeFont: NSFont = .monospacedSystemFont(ofSize: FontSize.standard, weight: .regular)
    private static var headingFonts: [NSFont] = makeHeadingFonts(base: FontSize.standard, family: .default)

    /// Clamps to the supported range and rebuilds the cached fonts. Returns
    /// whether the size actually changed, so callers can skip a re-highlight.
    @discardableResult
    static func setEditorFontSize(_ size: CGFloat) -> Bool {
        let clamped = FontSize.clamp(size)
        guard clamped != editorFontSize else { return false }
        editorFontSize = clamped
        rebuildFonts()
        return true
    }

    /// Sets the body font family and rebuilds the cached fonts. Returns whether
    /// it changed (mirrors `setEditorFontSize`). The code font is unaffected.
    @discardableResult
    static func setEditorFontFamily(_ family: FontFamily) -> Bool {
        guard family != editorFontFamily else { return false }
        editorFontFamily = family
        rebuildFonts()
        return true
    }

    static func headingFont(level: Int) -> NSFont {
        let clamped = max(1, min(6, level))
        return headingFonts[clamped - 1]
    }

    private static func rebuildFonts() {
        editorFont = editorFontFamily.font(size: editorFontSize)
        codeFont = .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        headingFonts = makeHeadingFonts(base: editorFontSize, family: editorFontFamily)
    }

    private static func makeHeadingFonts(base: CGFloat, family: FontFamily) -> [NSFont] {
        (1...6).map { level in
            let bump = CGFloat(7 - level)
            return family.boldFont(size: base + bump)
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

    // MARK: - Cursor

    private(set) static var cursorStyle: CursorStyle = .bar
    private(set) static var cursorBlink: Bool = true

    /// Sets the caret style + blink. Returns whether anything changed, so callers
    /// can skip a redraw (mirrors `setEditorFontSize`).
    @discardableResult
    static func setCursor(style: CursorStyle, blink: Bool) -> Bool {
        guard style != cursorStyle || blink != cursorBlink else { return false }
        cursorStyle = style
        cursorBlink = blink
        return true
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
