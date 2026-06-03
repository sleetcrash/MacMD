import SwiftUI

/// Identifies the Help window, opened from Help > MacMD Help.
enum HelpScene {
    static let id = "help"
}

/// A local, offline help window. Reference content the user can keep open while
/// working. No network links: all guidance is bundled here.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MacMD Help")
                    .font(.system(size: 16, weight: .semibold))

                section("Files",
                        "MacMD opens and saves Markdown (.md) and plain text (.txt). New documents are Markdown by default. Use File > Open and File > Save as usual.")

                section("Markdown",
                        "Headings, bold, italic, inline code, fenced code, links, lists, task lists, blockquotes, strikethrough, and horizontal rules are highlighted as you type. Front matter at the top of a file (--- for YAML or +++ for TOML) is shown as muted metadata.")

                section("Appearance and themes",
                        "Open Format > Appearance to set light, dark, or system appearance, the heading color scheme, and the editor font size. Adjust size quickly with Command-Plus, Command-Minus, and Command-0.")

                section("Custom themes",
                        "In the Appearance window's Theme dropdown choose Custom+ to open the Custom Theme builder. Pick colors for your H1, H2, and H3 headings in both light (sun) and dark (moon) appearance. The Appearance window previews each change live. Name and Save the theme, then choose it in the Appearance window to apply it to your document.")

                section("Word count",
                        "Use View > Show Word Count to show a live word count and reading-time estimate under the editor. It is off by default.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 520)
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .foregroundStyle(Pane.text)
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(Pane.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
