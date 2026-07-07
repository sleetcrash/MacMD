# Contributing to MacMD

Thanks for your interest. MacMD is a small, single-maintainer project, so the process is deliberately light: open an issue for bugs and ideas, open a pull request for fixes.

## Reporting bugs and requesting features

- Use the [issue forms](../../issues/new/choose). For bugs, the MacMD version, your macOS version, and a minimal Markdown snippet that reproduces the problem make fixes much faster.
- Security issues go through private reporting instead; see [SECURITY.md](SECURITY.md).

## Development setup

Requires Xcode 16 or newer. No package manager, no dependencies to install.

Build:

    xcodebuild -project MacMD.xcodeproj -scheme MacMD -configuration Release -destination 'platform=macOS' build

Test:

    xcodebuild test -project MacMD.xcodeproj -scheme MacMD -destination 'platform=macOS'

Or open `MacMD.xcodeproj` in Xcode and press Cmd-R.

## Project layout

    MacMD/            App source (Swift, SwiftUI + AppKit)
    MacMDTests/       Unit and integration tests
    MacMD.xcodeproj/  Xcode project
    Scripts/          Icon, link-preview, and release-packaging scripts (see Scripts/README.md)
    docs/             Screenshot and link-preview images

## House rules

Pull requests run CI (build plus the full test suite) and are expected to follow these:

- **Behavior changes come with tests.** Every highlighting rule and file-handling policy is pinned by a test; keep it that way.
- **Byte fidelity is doctrine.** The editor never rewrites the user's text. The only exceptions are the documented POSIX ones (trailing newline on save, BOM strip on read). Anything that would make MacMD alter saved bytes needs discussion in an issue first.
- **No em dashes** in first-party files; CI rejects them.
- **Conventional commits** (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- **Plain-language comments, and few of them.** Comment only what the code can't say itself.

## Releases

Releases are cut by the maintainer. `Scripts/package.sh X.Y.Z` clean-builds Release and produces the zip, DMG, and sha256 artifacts in `dist/`; details in `Scripts/README.md`.
