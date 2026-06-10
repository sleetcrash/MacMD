# Changelog

All notable changes to MacMD will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-06-10

### Added
- A Background control in the Appearance window to set the editor background. Default follows your Light/Dark Mode as before. Custom opens the system color picker so any color becomes the editor background, and the text adjusts itself to stay readable on it (a dark color gets light text, a light color gets dark text). The pencil on the Custom swatch reopens the picker, and your choice persists across launches.

### Changed
- The Appearance window controls are rearranged: Mode and Background share the first row, Theme and Scheme the second, Font and Size the third, and Cursor and Blink the fourth.

### Fixed
- The Underline cursor style now draws as a full-width underscore beneath the character. It previously drew as a tiny dot.
- Moving the cursor quickly with the Block or Underline style no longer leaves stale copies of the cursor scattered through the text.
- Turning Blink off now actually keeps the cursor steady. It previously kept blinking regardless of the setting.

## [1.3.2] - 2026-06-09

### Fixed
- The delete confirmation in the Custom Theme window now matches the rest of the app: the stray dark band at the top is gone, and its Delete and Cancel buttons share one size and square style with the builder's buttons (Delete is the same red outline, in the same place).
- Closing that delete confirmation with the window's close button no longer reopens straight to it the next time you edit the same theme. It opens the editor as expected.

## [1.3.1] - 2026-06-08

### Fixed
- Opening or editing a document with an unusual long line (a malformed link with no closing parenthesis, repeated many times) could make the app stop responding. Such lines are now handled instantly.
- Continuing a numbered list with the Return key no longer quits the app in a rare edge case (a list item numbered with an extremely large value).
- Clicking in the narrow gap just above or below a task checkbox no longer toggles it. Only a click on the checkbox itself toggles it.

### Changed
- Scrolling a large document in plain mode (with line numbers showing) is smoother.

## [1.3.0] - 2026-06-06

### Added
- A Font control in the Appearance window to choose the editor body font from eight families (System Monospace, Menlo, Monaco, Courier New, System, New York, Helvetica Neue, Georgia). Inline and fenced code always stay monospace, and headings stay bold and sized for any font.
- A Cursor control in the Appearance window to set the insertion-point style (Bar, Block, or Underline), with an optional Blink toggle.
- Show Formatting in the View menu (Command-Slash) to switch the editor between styled markdown and plain, uniform source text. It applies to every open window.
- Line numbers down the left edge in plain mode (when Show Formatting is off). A wrapped line is numbered only on its first row.

### Changed
- The Appearance preview now renders in your chosen body font, so it matches the editor.

## [1.2.9] - 2026-06-04

### Added
- Strikethrough, Inline Code, and Link commands in the Format menu (Strikethrough is Shift-Command-X, Link is Command-K).
- A Spelling and Grammar submenu in the Edit menu, so you can check spelling and toggle check-as-you-type.
- A Settings item (Command-Comma) in the app menu, the standard place for app preferences. It opens the Appearance window.
- A Keyboard shortcuts section in the Help window.

### Changed
- Toggle Task Checkbox moved from the Edit menu to the Format menu, next to Bold and Italic.
- The word count no longer counts ordered-list numbers (1., 2.), matching Word, Pages, and Google Docs.
- The Custom Theme window is narrower so it fits its content, with no empty space on the sides. Its buttons follow the standard macOS layout (Save at the bottom-right, Delete at the bottom-left).
- The Help window's Files section now lists every supported file type (.md, .markdown, .mdown, .mkd).

### Removed
- The Window menu no longer repeats Appearance, Custom Theme, and Help. They are already in the Format and Help menus.
- The Custom Theme and Appearance windows no longer have a Close button. Use the red window button or Escape to close them.

## [1.2.8] - 2026-06-04

### Fixed
- The theme, scheme, and font-size dropdowns scroll normally again. A 1.2.7 change had over-dampened them, making the Custom+ row at the bottom of the theme list very hard to reach.

### Changed
- The Custom Theme builder is tidied up: the title, swatches, name field, and buttons are centered; the name field shows "Name" inside it and spans the swatches; and Delete, Close, and Save are the same size.
- The Appearance and Custom Theme windows now stay above the document window when you click into the document.

## [1.2.7] - 2026-06-03

### Changed
- The Custom Theme builder is simpler: a single "Custom Theme" title and no description text (the same guidance lives in the Help window).
- The theme, scheme, and font-size dropdowns scroll more gently.

## [1.2.6] - 2026-06-03

### Changed
- The Custom Theme builder and the Help window now describe both theme styles: a Standard theme sets H1, H2, and H3 colors separately, and a Unified theme uses one color for all headings.

## [1.2.5] - 2026-06-03

### Added
- Spell check: misspelled words are now underlined as you type. Toggle it from Edit > Spelling and Grammar.
- Front matter at the top of a file (--- for YAML or +++ for TOML) is shown as muted metadata.
- An optional word count and reading-time estimate under the editor. Turn it on from View > Show Word Count. It is off by default.
- A Help menu with a built-in, offline MacMD Help window.
- Markdown files with the .mdown and .mkd extensions now open as Markdown.

### Changed
- Clearer guidance text in the Custom Theme builder, naming the light and dark heading columns.
- The Custom Theme name field now has a Name label on its left and stretches to the window's right edge.
- The Custom Theme window now comes to the front when it opens.

## [1.2.4] - 2026-06-02

### Changed
- Minor wording cleanup in the Custom Theme builder's guidance text.

## [1.2.3] - 2026-06-02

### Fixed
- The scrollbar in the font-size and theme dropdowns now follows the list as you scroll. (The 1.2.2 attempt at this did not take effect; the indicator stayed pinned at the top.)

## [1.2.2] - 2026-06-02

### Fixed
- The scrollbar in the font-size and theme dropdowns now follows the list as you scroll, instead of staying still.
- The Theme dropdown is tall enough to show the whole list, including your saved custom themes and Custom+, without cutting off the bottom row.
- The Custom+ row's placeholder swatches now line up with the other themes in the dropdown.
- In the Custom Theme builder, the swatch you're editing now shows a selection box around it.
- Closing the Appearance window now also closes the Custom Theme builder and the color picker, instead of leaving them open behind it.
- A custom theme you just created now takes effect on the open document as soon as you choose it in the Appearance window (previously it could need a relaunch to show up).

### Changed
- The Custom Theme builder no longer has its own Apply button. Build and name your palette there and Save it, then choose it in the Appearance window to apply it, the same way you pick any other theme. The Appearance window's preview updates live while you edit.

## [1.2.1] - 2026-06-01

### Fixed
- The Appearance and Custom Theme windows no longer open partly off the edge of the screen. A position you drag them to is still remembered.
- The Theme and Scheme dropdowns respond to the keyboard again: arrow keys move the highlight (and scroll it into view) and Return chooses the highlighted item. Highlighting the row under the pointer is also more responsive.

## [1.2.0] - 2026-05-31

### Added
- **Editor commands.** Find (Cmd-F), Find and Replace (Cmd-Opt-F), Find Next / Previous (Cmd-G / Cmd-Shift-G), and Use Selection for Find (Cmd-E). Print (Cmd-P). Bold (Cmd-B) and Italic (Cmd-I) wrap or unwrap the selection. Smart list continuation: pressing Return on a list item starts the next marker, and renumbers ordered lists.
- **Appearance window** (Format ▸ Appearance, Cmd-,). Pick a coloring **Scheme** (Default / Unified / Standard), a **Theme** (preset palettes, single colors, or your saved customs), an appearance **Mode** (Light / Dark / System), and the editor font **Size**, with a live preview. Heading levels get distinct colors and list markers inherit the color of the heading section above them. The window follows the OS light/dark appearance like the system color picker.
- **Custom themes.** Create, name (up to 10 characters), edit, and delete your own palettes, each with separate light and dark colors per slot, in a dedicated Custom Theme window that live-drives the preview. Changes Apply to the open document and Save persists them app-wide.

### Changed
- Headings and list markers are no longer colored with the system accent color by default. The new out-of-box **Default** scheme renders headings in the adaptive label color (bold and sized only); pick a theme in the Appearance window to color them. Existing users will see plain headings until they choose a theme.
- The font-size control moved from the old stepper into the Appearance window's Size box (the View-menu Cmd-+/-/0 commands still work).

### Fixed
- Custom Theme color swatches now open the color picker when clicked. They previously did nothing because the swatch hid its control in a way that swallowed the click.
- A selected row's highlight in the Theme dropdown no longer bleeds under the scrollbar.
- Fixed a crash when opening the Custom Theme editor.

## [1.1.2] - 2026-05-28

### Changed
- Bundle identifier is now `com.sleetcrash.MacMD` (was `com.eb.MacMD`), aligning the app with the Sleetcrash namespace used across the projects. macOS treats the renamed app as a new identity, so if a previous build is installed you may want to delete it and re-set the default "Open with" association for `.md` files to this version.

## [1.1.1] - 2026-05-28

### Added
- Adjustable editor font size. View menu: Increase Font Size (Cmd-+), Decrease Font Size (Cmd--), Actual Size (Cmd-0). The size is persisted across launches and applies to every open document.
- A Settings window (Cmd-,) with a stepper for the editor font size.
- Edit menu: Toggle Task Checkbox (Cmd-Shift-L) flips the checkbox on the line containing the insertion point, so task lists can be toggled from the keyboard and VoiceOver, not just by clicking. The editor view also carries an accessibility label.

### Fixed
- Security (availability): the `**bold**` and `__bold__` highlight rules used an unbounded lazy match that could backtrack catastrophically. A single crafted line (tens of KB of a repeated `** ` pattern) made the highlighter run for minutes on the main thread when the file was opened, freezing the UI. The inner run is now bounded so emphasis highlighting stays linear; `**bold *italic* bold**` composition is unchanged. Covered by a regression test that highlights a 200 KB adversarial line in milliseconds.
- The task-checkbox toggle now bounds-checks its target character range against the end of the document before editing.

### Internal
- Editor fonts are rebuilt only when the size actually changes, keeping the per-keystroke highlight path allocation-free.
- Test suite grown to 54 (was 46): emphasis backtracking guard, editor font-size bounds, and the keyboard toggle command.

## [1.1.0] - 2026-05-28

### Added
- `~~strikethrough~~` rendered with strikethrough style.
- `~~~` fenced code blocks (in addition to triple-backtick). Fences must be closed by the same marker character.
- `1)` ordered-list markers in addition to `1.`.
- Interactive `[ ]` / `[x]` task-list checkboxes. Click a checkbox glyph to toggle its state; the toggle participates in the undo manager. Checked task lines render the body with strikethrough and a muted color.
- Document-size guard: files larger than 64 MiB are refused at open with a standard document-open error; files larger than 8 MiB open without syntax highlighting so typing stays responsive.

### Changed
- A single trailing newline is appended on save when the document doesn't already end with one. Matches POSIX text-file convention and matches BBEdit, Sublime, VS Code.
- A leading UTF-8 BOM is stripped on read.
- Project now builds clean under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` in all four target configurations).
- `Scripts/package.sh` aborts if `MARKETING_VERSION` in the built binary disagrees with the version argument, and runs `codesign --verify --deep --strict` before packaging.

### Fixed
- `addFontTrait` now composes both traits when called with `[.bold, .italic]` instead of silently dropping the second. No current caller hit this, but the behavior was latent and would have surprised future contributors.

### Internal
- `Theme.editorFont` cached as `static let` (was re-resolving the system font on every read).
- `Theme.headingFont(level:)` cached as a six-element array indexed by level.
- `MarkdownTextView.updateNSView` reduced to a direct `String != String` comparison.
- `MarkdownHighlighter` inline-rule table extracted into a file-private `MarkdownRules` namespace, separating runtime state from static configuration.
- `try!` regex compilation replaced with a checked factory that names the failing pattern.

## [1.0.3] - 2026-05-27

### Changed
- Repository transferred from the `cachedcliche` GitHub org to the `sleetcrash` personal account. Latest release: https://github.com/sleetcrash/MacMD/releases/latest. The old URL still 301-redirects.
- `NSHumanReadableCopyright` updated to "© 2026 Sleetcrash. MIT Licensed." (was "© 2026 Cached Cliché. MIT Licensed.").

## [1.0.2] - 2026-04-27

### Removed
- App Sandbox entitlement (`com.apple.security.app-sandbox`). MacMD is now distributed unsandboxed, matching the posture of BBEdit, Sublime Text, and VS Code. Hardened Runtime remains enabled. Trade-off: not Mac App Store eligible (was not a goal). Existing `.md` files are unaffected.

### Fixed
- Documents on external / USB volumes (ExFAT, SMB, etc.) no longer fail to save with "you don't have permission" after the document has been open for an extended time. Root cause was sandbox security-scope invalidation on the file URL once the volume slept or was re-mounted (e.g., via `fskit` on macOS 15+); SwiftUI's `DocumentGroup` did not refresh the scope before atomic save. Removing the sandbox eliminates the failure mode.

## [1.0.1] - 2026-04-21

### Fixed
- Adding or deleting a ` ``` ` fence line now re-highlights the affected region immediately. Previously, content whose fence membership changed kept its old styling until independently edited.
- Inline code block background color adapts correctly when the system appearance changes between Light and Dark Mode (wrapped in a dynamic `NSColor` provider so alpha resolves per-appearance).

### Changed
- Inline highlighting skips redundant string bridging (one `ts.string` fetch per edit instead of eleven), keeping typing smooth on larger documents.
- Bulk document replacements (open / external edit) no longer double-highlight the first paragraph before the full-document pass.
- `NSHumanReadableCopyright` set to "© 2026 Cached Cliché. MIT Licensed."
- Release DMG now uses APFS; packaging script cleans its staging directory even on failure.
- Regex compilation uses `try!` so any pattern bug surfaces with a real error.

### Added
- Two unit tests covering fence-boundary re-highlighting (adding and removing a fence marker). Total: 22 tests.

## [1.0.0] - 2026-04-20

### Added
- Document-based SwiftUI macOS app for editing `.md` files.
- Live syntax highlighting for headings (H1–H6), `**bold**`, `*italic*`, `` `code` ``, fenced code blocks (with open-block styling to end of document), `[links](url)`, ordered and unordered list markers, blockquotes, and horizontal rules.
- Correct composition of overlapping styles (e.g. `**bold *italic* bold**` shows bold and italic together; `> **bold**` preserves bold inside blockquote italic).
- Scoped paragraph-level re-highlighting so typing stays smooth on long documents.
- Dark Mode support via semantic `NSColor` values.
- UTF-8 read/write with explicit error on malformed encoding instead of silent replacement-character corruption.
- App Sandbox enabled; only `user-selected.read-write` file access. Hardened runtime on. No network, camera, mic, location, or contacts access.
- Custom app icon: black squircle with white `.MD` wordmark.
- 20 unit tests covering every syntax rule and the known composition edge cases.
