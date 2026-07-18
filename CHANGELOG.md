# Changelog

All notable changes to MacMD will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Three tinted built-in themes, Cream, Parchment, and Gray, carrying the 2.2 background pairs as full themes.
- Background-only custom themes: choose the None scheme in the Theme Builder to build a theme from just a background color.
- Static themes: a custom theme can now keep one fixed look. It sets the window's light or dark appearance from its background color, and the Mode control shows "Set by theme" while one is applied.

### Changed
- Themes now own their backgrounds. The one Theme dropdown in Settings → Appearance covers everything: Default, the tinted themes, the Standard and Unified presets, and your custom themes, each carrying its own background.
- The Custom Theme window is now the Theme Builder: pick static or dynamic, a scheme (None, Unified, or Standard), heading colors, and a background from quick swatches, your saved colors, or the color panel. Colors picked with the panel join your Saved list when the theme is saved.
- Your existing setup migrates automatically on first launch and keeps its exact look, including custom themes, background choices, and the saved background list.

### Removed
- The separate Scheme and Background dropdowns in Settings → Appearance. Scheme choice lives in the Theme Builder; backgrounds ride with their themes.

## [2.2.0] - 2026-07-16

### Added
- The toolbar now hides itself and slides in when you move the pointer to the top of the document, like the macOS menu bar in full screen. Right-click the toolbar (or use Settings → Editing) to turn automatic hiding off and keep it always visible.
- Cursor color: pick any fixed caret color in Settings → Appearance (Default keeps the system accent).
- Background presets: the Background dropdown offers Cream (cream | navy), Parchment (parchment | charcoal), and Gray (light | dark gray) pairs that follow your light/dark mode, shown with the same light | dark swatches as the themes.
- A "Show word count" checkbox in Settings → Editing, alongside the existing View menu toggle.

### Changed
- The copy-text button and the pane layout control moved from the titlebar into the toolbar's right edge, ordered customize, copy, layout. The toolbar is shorter and transparent, and its button groups spread across the full window width.
- "Custom+" is now "Customize" in the theme and background dropdowns, with the create plus icon in the same spot custom entries show their edit pencil.
- The preview renders a single newline as a line break, matching the line breaks you see in the editor.

### Removed
- The "New windows" size setting in Settings → Editing. New windows and tabs now follow standard macOS sizing.

### Fixed
- Adding a tab no longer shrinks the whole window to the new-window size.

## [2.1.0] - 2026-07-12

### Added
- Pane layouts: a three-segment control in every document window's titlebar switches between editor only, split, and preview only, alongside a one-click button that copies the whole document. View → Layout mirrors the three choices.
- Two-way scroll sync: in split layout, scrolling the preview now scrolls the editor too, and following the editor is noticeably smoother.
- A format toolbar under the titlebar: Bold, Italic, Strikethrough, Inline Code, Link, and Task Checkbox buttons, the editor font and size, and a shortcut to Settings. Hide it from Settings → Editing or View → Show Toolbar.
- Line numbers in the editor gutter in both styled and plain modes (previously plain mode only), with a View → Show Line Numbers toggle.
- Front matter in the preview: the leading YAML/TOML block now renders as a muted metadata card instead of misparsing as a giant heading, and under a color scheme its keys (name, description, ...) take the theme's H1 color in both the editor and the preview.
- Export to PDF: File → Export to PDF writes a single-page PDF of the rendered document with the theme background edge to edge, through the same offline sandboxed pipeline as the HTML export.
- Templates: File → New from Template starts a prefilled SKILL.md, agent, CLAUDE.md, or AGENTS.md document.
- Custom themes can now be light-only or dark-only: a Light + Dark | Light | Dark selector in the Custom Theme builder; a single-sided theme uses its colors under both appearances.
- Saved custom backgrounds: saving Settings with a custom editor background adds the color to a Saved list in the Background dropdown, removable with one click.
- A `skills/macmd` skill file that teaches AI agents the app's full scope, CLI configuration keys, and menu map.

### Changed
- The word count is now a compact tab in the editor's bottom-left corner instead of a full-width bar.
- New installs default to dark mode; the View menu's font-size reset is now labeled "Reset Font Size" (was "Actual Size").
- The window layout preference migrated from the show-preview toggle to the three-way pane mode (an existing "preview on" carries over as split).

### Fixed
- A crash when switching themes while document windows were open (window appearance was mutated mid layout pass).
- The cursor style could revert visually (for example to Block) in other open windows after changing it in Settings; every window now refreshes its caret.
- Clicking a color swatch in the Custom Theme builder now always retargets the color panel; previously a click could silently deactivate the well and picks went nowhere.

## [2.0.0] - 2026-07-06

MacMD grows from a pure editor into an editor with a rendered view, while keeping its plain-text guarantees. Everything renders offline with a bundled engine; the app still makes no network connections.

### Added
- Live preview pane: View → Show Preview (Cmd-Shift-P) splits the window with a rendered view that updates as you type and follows your scroll position. It mirrors the editor's theme, fonts, and background in light and dark, renders GitHub Flavored Markdown (tables, task lists, strikethrough), loads images from the document's folder, and opens links in your browser. Documents still open editor-only; the preview is opt-in per window.
- Mermaid diagrams: fenced mermaid code blocks render as diagrams in the preview and in exports. Twelve diagram types ship: flowchart, sequence, class, state, entity-relationship, gantt, pie, mindmap, git graph, journey, timeline, and quadrant.
- Export to HTML: File → Export to HTML (Cmd-Shift-E) writes a single self-contained file that opens anywhere, offline. Styling is inlined and matches your theme, images from the document folder are embedded, mermaid diagrams are baked in as SVG, and remote image references are stripped so the exported file loads nothing from the network when opened.

### Security
- The renderer is locked down: it runs in a sandboxed web view with no network access, script execution from document content is blocked, and every mermaid diagram type was gate-tested to render without relaxing that policy. Hostile-input fixtures (script injection, path traversal, malicious diagram payloads) are part of the test suite, which now stands at 352 tests.

## [1.0.0] - 2026-06-11

The first official release of MacMD, a native Markdown editor for the Mac. Requires macOS 14 (Sonoma) or later. The development builds previously published from this repository were retired when this release was cut; their history remains in the repository's git log.

### Editing
- Live syntax highlighting for headings (H1 through H6), bold, italic, strikethrough, inline code, fenced code blocks (backtick and tilde fences), links, ordered and unordered lists, task lists, blockquotes, front matter (YAML and TOML), and horizontal rules, with correct composition of overlapping styles.
- Interactive task checkboxes: click a checkbox in the text to toggle it, or use Format → Toggle Task Checkbox (Cmd-Shift-L).
- Smart list continuation: pressing Return on a list item starts the next marker, continuing the numbering in ordered lists.
- Find (Cmd-F), Find and Replace, Find Next and Previous, Use Selection for Find, and Print.
- Format commands that wrap or unwrap the selection: Bold, Italic, Strikethrough, Inline Code, and Link.
- Show Formatting (Cmd-/) switches every open window between styled Markdown and plain source text, with line numbers down the left edge in plain mode.
- Spell check underlines misspellings as you type, with an optional grammar check.
- An optional word count and reading-time estimate under the editor (View → Show Word Count).

### Settings
- A tabbed Settings window (Cmd-,). The Appearance tab sets Light, Dark, or System mode; the editor background (the default that follows your mode, or any custom color, with the text adjusting itself to stay readable); the coloring scheme and theme, including custom palettes you build, name, and save with separate light and dark colors; the body font (eight families) and size; and the cursor style (Bar, Block, or Underline) with an optional blink, all with a live preview.
- The Editing tab sets the spelling and grammar defaults, plus the size new windows open at (in points, with a Use Current Window button to capture the size of the window you are using). Reopened files keep their own remembered size.

### Files
- Plain-text UTF-8 Markdown (.md, .markdown, .mdown, .mkd) with byte-for-byte fidelity: a malformed encoding is reported instead of silently corrupted, a leading BOM is stripped on read, and a single trailing newline is appended on save, matching POSIX convention.
- Large-file guards: files over 8 MiB open without highlighting so typing stays responsive, and files over 64 MiB are refused at open.

### Help
- A built-in, offline Help window covering the editor, files, settings, and keyboard shortcuts.

[2.0.0]: https://github.com/sleetcrash/MacMD/releases/tag/v2.0.0
[1.0.0]: https://github.com/sleetcrash/MacMD/releases/tag/v1.0.0
