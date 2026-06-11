# Changelog

All notable changes to MacMD will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-11

The first official release of MacMD, a native markdown editor for the Mac. Requires macOS 14 (Sonoma) or later. The development builds previously published from this repository were retired when this release was cut; their history remains in the repository's git log.

### Editing
- Live syntax highlighting for headings (H1 through H6), bold, italic, strikethrough, inline code, fenced code blocks (backtick and tilde fences), links, ordered and unordered lists, task lists, blockquotes, front matter (YAML and TOML), and horizontal rules, with correct composition of overlapping styles.
- Interactive task checkboxes: click a checkbox in the text to toggle it, or use Format > Toggle Task Checkbox (Shift-Command-L).
- Smart list continuation: pressing Return on a list item starts the next marker and renumbers ordered lists.
- Find (Command-F), Find and Replace, Find Next and Previous, Use Selection for Find, and Print.
- Format commands that wrap or unwrap the selection: Bold, Italic, Strikethrough, Inline Code, and Link.
- Show Formatting (Command-Slash) switches every open window between styled markdown and plain source text, with line numbers down the left edge in plain mode.
- Spell check underlines misspellings as you type, with an optional grammar check.
- An optional word count and reading-time estimate under the editor (View > Show Word Count).

### Settings
- A tabbed Settings window (Command-Comma). The Appearance tab sets Light, Dark, or System mode; the editor background (the default that follows your mode, or any custom color, with the text adjusting itself to stay readable); the coloring scheme and theme, including custom palettes you build, name, and save with separate light and dark colors; the body font (eight families) and size; and the cursor style (Bar, Block, or Underline) with an optional blink, all with a live preview.
- The Editing tab sets the spelling and grammar defaults, plus the size new windows open at (in points, with a Use Current Window button to capture the size of the window you are using). Reopened files keep their own remembered size.

### Files
- Plain-text UTF-8 markdown (.md, .markdown, .mdown, .mkd) with byte-for-byte fidelity: a malformed encoding is reported instead of silently corrupted, a leading BOM is stripped on read, and a single trailing newline is appended on save, matching POSIX convention.
- Large-file guards: files over 8 MiB open without highlighting so typing stays responsive, and files over 64 MiB are refused at open.

### Help
- A built-in, offline Help window covering the editor, files, settings, and keyboard shortcuts.
