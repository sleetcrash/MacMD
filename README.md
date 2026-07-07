# MacMD

A lightweight, native, open source Markdown editor for macOS. MacMD feels like TextEdit built for `.md` files: open a Markdown file, edit it as plain text with live syntax highlighting, and save exactly the bytes you typed. The download is about 1.5 MB, and the app makes no network connections of any kind.

MacMD is made for the Markdown files developers touch every day: `README.md`, `CLAUDE.md`, `AGENTS.md`, agent and skill configs, notes, and docs.

**[Download the latest release](../../releases/latest)** for macOS 14 (Sonoma) or later. Free, MIT licensed.

![MacMD editing a CLAUDE.md agent config file with live Markdown syntax highlighting in dark mode](docs/screenshot.png)

## Why MacMD

- **Native and lightweight.** Swift and AppKit, not an Electron wrapper. The installer is about 1.5 MB, and uninstalling is dragging one app to the Trash.
- **Live syntax highlighting.** Headings, bold, italic, code, links, lists, task lists, blockquotes, and front matter are styled as you type. The text stays plain Markdown; nothing is hidden or rewritten.
- **Plain text in, plain text out.** No smart quotes, no dash substitution, no autocorrect, no link detection. Paste always comes in as plain text. What you save is what you typed.
- **Private by design.** No network access, no telemetry, no analytics, no accounts. The app contains no networking code at all.
- **Free and open source.** MIT licensed, with the full Swift source in this repository.

## Built for editing CLAUDE.md, AGENTS.md, and agent configs

Markdown is the config language of AI coding tools, and those files break in editors designed for prose. MacMD is a safe place to edit `CLAUDE.md`, `AGENTS.md`, `agent.md`, skill definitions, and rule files:

- No smart punctuation or autocorrect, so prompts, code fences, and flags survive editing byte-for-byte.
- YAML (`---`) and TOML (`+++`) front matter is recognized at the top of the file and styled as muted metadata.
- Fenced code blocks suppress inline formatting, so example code stays code.
- Task lists highlight, and checkboxes toggle with a click.
- Byte-exact saves mean clean `git diff`s. The only exceptions are POSIX conventions: a single trailing newline is added if missing, and a leading UTF-8 BOM is stripped on read.

## Install

Minimum macOS version: 14 (Sonoma).

### 1. Download

Go to the [latest release](../../releases/latest). You'll see several files; grab just one (version numbers will match whatever the current release is):

| File | What it is | Who should click it |
|---|---|---|
| **`MacMD-<version>.dmg`** | The installer. ~1.5 MB. | **Most people: this is the one you want.** |
| `MacMD-<version>.zip` | Same app, zipped instead of in a DMG. | Alternative if your browser doesn't like DMGs. |
| `*.sha256` | Tiny checksum files. | Optional; for verifying your download wasn't tampered with. |
| `Source code (zip / tar.gz)` | The Swift source. | Only if you want to build it yourself. Ignore otherwise. |

### 2. Copy to Applications

Double-click the DMG. A Finder window opens with `MacMD.app` and an `Applications` shortcut. Drag `MacMD.app` onto `Applications`. You can eject the DMG after.

### 3. First launch (one-time Gatekeeper approval)

MacMD is signed ad-hoc, not Apple-notarized (notarization requires a paid Apple Developer account), so macOS blocks it the first time.

**On macOS 15 Sequoia or newer:**

1. Double-click `MacMD` in Applications.
2. macOS shows "cannot verify this app is free from malware." Click **Done**.
3. Open **System Settings → Privacy & Security**. Scroll to the **Security** section.
4. Next to "MacMD was blocked to protect your Mac", click **Open Anyway**.
5. Confirm once more, authenticate with Touch ID or password.
6. MacMD launches.

**On macOS 14 Sonoma:**

Right-click `MacMD.app` → **Open** → **Open** in the confirmation dialog.

After this one-time approval, MacMD launches normally every time.

### 4. Open .md files

Any of these work:

- Right-click any `.md` file and choose **Open With → MacMD** (or set it as default via File → Get Info → Open with → Change All).
- Drag a `.md` file onto the MacMD icon in the Dock.
- File → Open inside MacMD.
- Cmd-N for a new untitled document.

MacMD opens `.md`, `.markdown`, `.mdown`, and `.mkd` files.

### Uninstall

Drag `MacMD.app` from Applications to Trash. No daemons, no receipts, no login items. The only trace left behind is the standard small preferences file every Mac app keeps; remove `~/Library/Preferences/com.sleetcrash.MacMD.plist` too if you want zero trace.

## Write and save

The File menu works exactly as you'd expect, and all commands use standard Mac keybindings:

    Cmd-N     New document
    Cmd-O     Open an existing .md file
    Cmd-S     Save (prompts for filename + location on first save)
    Cmd-Shift-S   Save As
    Cmd-P     Print
    Cmd-W     Close window (prompts to save if dirty)
    Cmd-Z / Cmd-Shift-Z   Undo / Redo
    Cmd-F     Find (inline find bar)
    Cmd-Opt-F     Find and Replace
    Cmd-B / Cmd-I     Bold / Italic the selection (wraps or unwraps)
    Cmd-Shift-X   Strikethrough the selection
    Cmd-K     Wrap the selection as a link
    Cmd-Shift-L   Toggle the task checkbox on the current line
    Cmd-/     Show Formatting: switch between styled Markdown and plain
              source text with line numbers
    Cmd-+ / Cmd--   Increase / decrease editor font size
    Cmd-0     Reset editor font size to the default
    Cmd-,     Settings (appearance, themes, fonts, cursor, editing defaults)

Pressing Return on a list item continues the list: the next marker is inserted for you, with ordered-list numbering continued automatically. Spell check underlines misspellings as you type, with an optional grammar check. An optional word count and reading-time estimate sits under the editor (View → Show Word Count).

The editor autosaves in the background. If the app quits unexpectedly, reopening recovers your work. Recent files appear under File → Open Recent, and a built-in offline Help window (Help → MacMD Help) covers the editor, files, settings, and shortcuts.

## What gets highlighted

As you type, MacMD styles these Markdown constructs live:

    # Heading 1 through ###### Heading 6   → bold, theme color, sized per level
    **bold** and __bold__                  → bold
    *italic* and _italic_                  → italic
    ***bold italic***                      → bold + italic compose correctly
    ~~strikethrough~~                      → single-line strike
    `inline code`                          → subtle background tint
    ```        ~~~                         → fenced code blocks get the same tint,
    fenced     fenced                         and style to end of document if you
    ```        ~~~                            haven't closed them yet (backtick and
                                              tilde fences both work; a fence can
                                              only be closed by the same marker)
    [link label](https://example.com)      → label underlined in link color, URL muted
    - unordered, * and + also valid        → marker inherits its section's heading color
    1. ordered list, 1) also valid         → marker inherits its section's heading color
    - [ ] todo                             → bracket inherits section color; click to toggle
    - [x] done                             → bracket inherits section color + body strike-through
    > blockquote                           → muted + italic, composes with bold inside
    ---  (or +++)  front matter            → muted metadata block, recognized at the
                                              top of the document (YAML and TOML)
    ---                                    → horizontal rule, muted

Highlighting updates only the paragraph you're editing, so typing stays smooth on long files. Inside fenced code blocks, inline rules are intentionally suppressed, so code stays code.

Semantic colors are used throughout, so Dark Mode adapts automatically when you toggle system appearance.

## What gets saved

Plain UTF-8 text. Byte-for-byte what you typed: no smart quotes, no dash substitution, no link detection, no autocorrect. Paste from another app always comes in as plain text.

Two narrow exceptions to byte fidelity, both long-standing text-editor conventions:

- A single trailing newline is appended on save when the document doesn't already end with one (POSIX text-file convention; matters for shell pipelines, `wc -l`, and `git diff`).
- A leading UTF-8 BOM (`EF BB BF`) is stripped on read, since BOMs are how some Windows editors and web tools sign their UTF-8 output and most editors silently strip it on import.

If you try to open a file that isn't valid UTF-8, MacMD refuses and surfaces a clear error rather than silently corrupting it with replacement characters.

Files larger than 64 MiB are rejected outright with a standard document-open error. Files between 8 MiB and 64 MiB open with syntax highlighting disabled so typing stays responsive; they're still fully editable, just unstyled.

## Themes and settings

Open Settings (Cmd-,) for a tabbed settings window with a live preview.

The **Appearance** tab:

- **Mode**: Light, Dark, or System (follows macOS).
- **Background**: the default that follows your mode, or any custom color, with the text adjusting itself to stay readable.
- **Scheme**: Default (headings bold and sized but uncolored), Unified (one color for every heading level), or Standard (three colors: H1, H2, H3, with H4 through H6 inheriting H3).
- **Theme**: preset palettes, or a custom palette you build, name, and save, with separate colors for light and dark.
- **Font**: eight body font families, monospaced and proportional, plus the size (also on the View menu: Cmd-+, Cmd--, Cmd-0).
- **Cursor**: Bar, Block, or Underline, with an optional blink.

The **Editing** tab sets the spelling and grammar defaults, plus the size new windows open at, with a Use Current Window button to capture the size of the window you're using. Reopened files keep their own remembered size.

List markers inherit the color of the heading section they sit under. Body text always uses the adaptive label color.

## Security and privacy

MacMD makes no network connections: no update checks, no crash reporting, no analytics, no telemetry. The source contains no networking code, and the app requests no access to the camera, microphone, location, photos, contacts, or calendars. It registers no URL schemes, daemons, or background services. The hardened runtime is enabled and the binary is code-signed.

The app only ever opens and saves files you explicitly choose through the standard Open and Save panels; it doesn't browse your filesystem on its own.

MacMD is **not sandboxed**. The App Sandbox was removed because it caused intermittent save failures on external and USB volumes (the security-scoped URL granted at file-open time stopped being valid after the drive slept or was re-mounted, a known limitation of SwiftUI's `DocumentGroup`). This matches the posture of editors like BBEdit, Sublime Text, and VS Code.

You can verify at any time:

    codesign -dv --entitlements - /path/to/MacMD.app

Security reports: see [SECURITY.md](SECURITY.md).

## Scope

The current release is deliberately an editor, not an IDE: there is no rendered preview pane, no export, no multi-cursor editing, no outline pane, and no file browser. A rendered preview with HTML export is in development on `main` and will ship as version 2.0.

## Build from source

Requires Xcode 16 or newer.

    xcodebuild -project MacMD.xcodeproj -scheme MacMD -configuration Release -destination 'platform=macOS' build

The built app lands in Xcode's DerivedData under `Build/Products/Release/MacMD.app`, or you can open the project in Xcode and press Cmd-R to run it directly.

Run tests:

    xcodebuild test -project MacMD.xcodeproj -scheme MacMD -destination 'platform=macOS'

The test suite covers every highlighting rule and the tricky edge cases: bold and italic composition, unclosed and reopened code fences, list-marker versus italic disambiguation, BOM stripping, the trailing-newline policy, the document size guards, and the task-list toggle. See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and release packaging.

## License

MIT. See [LICENSE](LICENSE). Built by [sleetcrash](https://github.com/sleetcrash).
