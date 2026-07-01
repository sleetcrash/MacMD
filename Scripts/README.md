# Scripts

## make_icon.swift

Regenerates the 10 app-icon PNGs (16, 32, 64, 128, 256, 512, 1024 px) directly into `MacMD/Assets.xcassets/AppIcon.appiconset/`. Uses CoreGraphics + CoreText, no external dependencies.

Run:

    swift Scripts/make_icon.swift MacMD/Assets.xcassets/AppIcon.appiconset

Then rebuild the app in Xcode (or via `xcodebuild`). The asset catalog picks up the new PNGs automatically.

Edit the script to change the icon: colors, font, corner radius, and kerning are all local constants near the top.

## package.sh

Clean-builds the Release configuration and packages `MacMD.app` into `dist/` as a signature-preserving `.zip` (via `ditto`) and a drag-to-Applications `.dmg` (APFS, via `hdiutil`), with a `sha256` file next to each.

Run:

    Scripts/package.sh X.Y.Z

Produces: `dist/MacMD-X.Y.Z.zip`, `dist/MacMD-X.Y.Z.zip.sha256`, `dist/MacMD-X.Y.Z.dmg`, `dist/MacMD-X.Y.Z.dmg.sha256`.

Notes for maintainers:
- The script selects the **newest** `MacMD.app` in DerivedData by mtime, not arbitrary `find` order, so a stale previous-version build can't be picked up after a clean build. It prints `Using build: <path>` so you can eyeball the selection.
- The DMG staging dir is cleaned with a `trap` on `EXIT`, so an `hdiutil` failure under `set -e` doesn't leak `/tmp/macmd-dmg.*`.
- Ad-hoc signed, not Apple-notarized. The README's Install section documents the one-time Gatekeeper approval that end users perform.

## make_social_preview.swift

Generates the 1280x640 GitHub social preview card (`docs/social-preview.png`) by capturing a running MacMD window. The app must be running with a representative file open when you run it.

## build-preview-assets.sh

Regenerates the bundled markdown render assets committed under `MacMD/Preview/`:

- `markdown-it.min.js`: markdown-it 14.2.0 UMD minified build (exposes the global `markdownit` factory), copied verbatim from `node_modules/markdown-it/dist/`.
- `mermaid.min.js`: mermaid 11.16.0 (ESM-only) bundled to one self-contained IIFE via esbuild. The entry is `import mermaid from "mermaid"; window.mermaid = mermaid;`, so `window.mermaid.run` / `window.mermaid.initialize` are reachable directly (a `--global-name` re-export would expose `window.mermaid.default` instead).

Both are MIT-licensed. Run from the repo root:

    Scripts/build-preview-assets.sh

Notes for maintainers:
- The outputs are committed artifacts. This script exists only for reproducibility and version bumps; it needs network access and a Node toolchain (node, npm, npx), and it builds in a `mktemp` dir it cleans up on exit.
- The exact esbuild command is `esbuild mermaid-entry.mjs --bundle --format=iife --minify`. Known-good toolchain (2026-07-01): node 25, npm 11, esbuild 0.28.1; outputs were ~124 KB (markdown-it) and ~3.4 MB (mermaid).
- Do NOT wire this as an Xcode run-script phase: `ENABLE_USER_SCRIPT_SANDBOXING = YES` blocks network, and the outputs are already vendored.
- The two vendored `.min.js` files legitimately contain U+2014 bytes, so they are excluded from the em-dash guards (see `.github/workflows/ci.yml` and the local pre-commit hook).
