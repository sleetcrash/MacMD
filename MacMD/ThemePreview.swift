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

    private var dark: Bool {
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
            Text("body text").foregroundColor(bodyColor)
            heading("## Section", level: 2)
            HStack(spacing: 0) {
                Text("- ").foregroundColor(headingColor(level: 2)).bold()
                Text("list item").foregroundColor(bodyColor)
            }
            heading("### Subsection", level: 3)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dark ? Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255) : Color.white)
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
    }

    private func heading(_ text: String, level: Int) -> some View {
        Text(text).bold().foregroundColor(headingColor(level: level))
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
