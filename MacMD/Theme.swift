import AppKit

@MainActor
enum Theme {
    static let editorFontSize: CGFloat = 14
    static let editorLineSpacing: CGFloat = 4

    static let editorFont: NSFont = .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)

    private static let headingFonts: [NSFont] = (1...6).map { level in
        let bump = CGFloat(7 - level)
        return .monospacedSystemFont(ofSize: editorFontSize + bump, weight: .bold)
    }

    static func headingFont(level: Int) -> NSFont {
        let clamped = max(1, min(6, level))
        return headingFonts[clamped - 1]
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
