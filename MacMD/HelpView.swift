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
                        "MacMD opens and saves Markdown (.md, .markdown, .mdown, .mkd) and plain text (.txt). New documents are Markdown by default. Use File > Open and File > Save as usual. File > New from Template starts a prefilled SKILL.md, agent, CLAUDE.md, or AGENTS.md document.")

                section("Markdown",
                        "Headings, bold, italic, inline code, fenced code, links, lists, task lists, blockquotes, strikethrough, and horizontal rules are highlighted as you type. Front matter at the top of a file (--- for YAML or +++ for TOML) is shown as muted metadata; under a color scheme its keys take the theme's H1 color, in the editor and the preview.")

                section("Preview and layout",
                        "The titlebar's layout control switches between editor only, split, and preview only; View > Show Preview (Shift-Command-P) toggles the pane. In split layout the panes scroll together, in both directions. The titlebar's copy button copies the whole document. Mermaid code fences render as diagrams in the preview.")

                section("Toolbar and line numbers",
                        "The toolbar under the titlebar gives one-click formatting, the editor font and size, and a shortcut to Settings; hide it from Settings > Editing or View > Show Toolbar. Line numbers show in the editor gutter; toggle them with View > Show Line Numbers.")

                section("Export",
                        "File > Export to HTML (Shift-Command-E) writes a single self-contained HTML file. File > Export to PDF writes a single-page PDF of the rendered document with the theme background edge to edge. Both are fully offline; remote image references are stripped and local images are embedded.")

                section("Spell check",
                        "Misspelled words are underlined as you type. Manage it from Edit > Spelling and Grammar.")

                section("Appearance and themes",
                        "Open MacMD > Settings (Command-Comma). The Appearance tab sets light, dark, or system appearance, the editor background, the heading color scheme, the editor font and size, and the cursor style. The Editing tab sets the spelling defaults and the size of new windows. Adjust font size quickly with Command-Plus, Command-Minus, and Command-0.")

                section("Custom themes",
                        "In the Settings window's Theme dropdown choose Custom+ to open the Custom Theme builder. Pick heading colors for light and dark mode, or choose Light or Dark at the top to define one side and use it under both appearances. A Standard theme sets H1, H2, and H3 separately; a Unified theme uses one color for all headings. The Settings window previews each change live. Name and Save the theme, then choose it in the Settings window to apply it to your document.")

                section("Custom backgrounds",
                        "In the Settings window's Background dropdown, Custom+ opens the color panel. Saving the settings with a custom background adds that color to a Saved list in the dropdown, so you can switch between backgrounds like themes; the x beside a saved color removes it.")

                section("Word count",
                        "Use View > Show Word Count to show a live word count and reading-time estimate in a small tab at the editor's bottom-left corner. It is off by default. List markers and ordered-list numbers are not counted.")

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
