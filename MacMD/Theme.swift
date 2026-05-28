import AppKit

enum Theme {
    static let editorFontSize: CGFloat = 14
    static let editorLineSpacing: CGFloat = 4

    static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    static func headingFont(level: Int) -> NSFont {
        let bump: CGFloat = max(0, CGFloat(7 - level))
        let size = editorFontSize + bump
        return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
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
