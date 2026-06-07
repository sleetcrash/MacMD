import SwiftUI
import AppKit

/// Live preview of the selected scheme + theme, following the Mode. Renders the
/// fixed sample (through ### Subsection) with resolved colors. Body is the
/// adaptive label color; the list marker inherits its section's (## Section)
/// color. Under System it follows the current OS appearance.
struct ThemePreview: View {
    let coloring: Coloring
    let palette: Palette?
    let appearance: AppAppearance
    let fontSize: CGFloat
    let family: FontFamily

    @MainActor private var dark: Bool {
        switch appearance {
        case .light: return false
        case .dark: return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("# Title", level: 1)
            Text("body text").font(bodyFont).foregroundColor(bodyColor)
            heading("## Section", level: 2)
            HStack(spacing: 0) {
                Text("- ").font(boldBodyFont).foregroundColor(headingColor(level: 2))
                Text("list item").font(bodyFont).foregroundColor(bodyColor)
            }
            heading("### Subsection", level: 3)
            HStack(spacing: 0) {
                Text("1. ").font(boldBodyFont).foregroundColor(headingColor(level: 3))
                Text("ordered item").font(bodyFont).foregroundColor(bodyColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255) : Color.white)
        // Border contrasts against the preview's own background, not the window:
        // a black hairline vanishes on the dark preview, so flip to white there.
        .overlay(Rectangle().strokeBorder((dark ? Color.white : Color.black).opacity(0.15), lineWidth: 1))
    }

    // Mirrors the editor's font scheme so the preview shows the chosen family and
    // size: body at the base size in the chosen family, headings bumped by
    // (7 - level) and bolded like Theme.headingFont. Uses the same NSFont -> Font
    // bridge the Appearance font dropdown uses.
    private var bodyFont: Font { Font(family.font(size: fontSize) as CTFont) }
    private var boldBodyFont: Font { Font(family.boldFont(size: fontSize) as CTFont) }

    private func heading(_ text: String, level: Int) -> some View {
        Text(text)
            .font(Font(family.boldFont(size: fontSize + CGFloat(7 - level)) as CTFont))
            .foregroundColor(headingColor(level: level))
    }

    private var bodyColor: Color {
        Color(nsColor: dark ? .white : .black).opacity(0.88)
    }

    private func headingColor(level: Int) -> Color {
        guard coloring != .off, let palette,
              let idx = ColorTheming.slotIndex(forHeadingLevel: level, scheme: coloring),
              idx < palette.slots.count else { return bodyColor }
        let pair = palette.slots[idx]
        return Color(nsColor: dark ? pair.nsDark : pair.nsLight)
    }
}
