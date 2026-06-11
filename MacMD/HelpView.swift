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
                        "MacMD opens and saves Markdown (.md, .markdown, .mdown, .mkd) and plain text (.txt). New documents are Markdown by default. Use File > Open and File > Save as usual.")

                section("Markdown",
                        "Headings, bold, italic, inline code, fenced code, links, lists, task lists, blockquotes, strikethrough, and horizontal rules are highlighted as you type. Front matter at the top of a file (--- for YAML or +++ for TOML) is shown as muted metadata.")

                section("Spell check",
                        "Misspelled words are underlined as you type. Manage it from Edit > Spelling and Grammar.")

                section("Appearance and themes",
                        "Open MacMD > Settings (Command-Comma). The Appearance tab sets light, dark, or system appearance, the editor background, the heading color scheme, the editor font and size, and the cursor style. The Editing tab sets the spelling defaults and the size of new windows. Adjust font size quickly with Command-Plus, Command-Minus, and Command-0.")

                section("Custom themes",
                        "In the Settings window's Theme dropdown choose Custom+ to open the Custom Theme builder. Pick heading colors for light and dark mode. A Standard theme sets H1, H2, and H3 separately; a Unified theme uses one color for all headings. The Settings window previews each change live. Name and Save the theme, then choose it in the Settings window to apply it to your document.")

                section("Word count",
                        "Use View > Show Word Count to show a live word count and reading-time estimate under the editor. It is off by default. List markers and ordered-list numbers are not counted.")

                section("Keyboard shortcuts",
                        "Bold Command-B, Italic Command-I, Strikethrough Shift-Command-X, and Link Command-K (Inline Code is on the Format menu). Toggle a task checkbox with Shift-Command-L. Find with Command-F. Open Settings with Command-Comma. Resize the editor font with Command-Plus, Command-Minus, and Command-0.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 520)
        .background(Pane.window)
        .background(SystemWindowAppearance())
        .foregroundStyle(Pane.text)
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
