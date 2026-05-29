# Changelog

All notable changes to MacMD will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
