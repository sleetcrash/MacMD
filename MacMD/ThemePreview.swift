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
                Text("- ").font(bodyFont.weight(.bold)).foregroundColor(headingColor(level: 2))
                Text("list item").font(bodyFont).foregroundColor(bodyColor)
            }
            heading("### Subsection", level: 3)
            HStack(spacing: 0) {
                Text("1. ").font(bodyFont.weight(.bold)).foregroundColor(headingColor(level: 3))
                Text("ordered item").font(bodyFont).foregroundColor(bodyColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255) : Color.white)
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
    }

    // Mirrors the editor's font scheme so the preview shows the chosen size:
    // body at the base size, headings bumped by (7 - level) like Theme.headingFont.
    private var bodyFont: Font { .system(size: fontSize, design: .monospaced) }

    private func heading(_ text: String, level: Int) -> some View {
        Text(text)
            .font(.system(size: fontSize + CGFloat(7 - level), weight: .bold, design: .monospaced))
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
