# Scripts

## make_icon.swift

Regenerates the 10 app-icon PNGs (16, 32, 64, 128, 256, 512, 1024 px) directly into `MacMD/Assets.xcassets/AppIcon.appiconset/`. Uses CoreGraphics + CoreText — no external dependencies.

Run:

    swift Scripts/make_icon.swift MacMD/Assets.xcassets/AppIcon.appiconset

Then rebuild the app in Xcode (or via `xcodebuild`). The asset catalog picks up the new PNGs automatically.

Edit the script to change the icon — colors, font, corner radius, kerning are all local constants near the top.

## package.sh

Clean-builds the Release configuration and packages `MacMD.app` into `dist/` as a signature-preserving `.zip` (via `ditto`) and a drag-to-Applications `.dmg` (APFS, via `hdiutil`), with a `sha256` file next to each.

Run:

    Scripts/package.sh X.Y.Z

Produces: `dist/MacMD-X.Y.Z.zip`, `dist/MacMD-X.Y.Z.zip.sha256`, `dist/MacMD-X.Y.Z.dmg`, `dist/MacMD-X.Y.Z.dmg.sha256`.

Notes for maintainers:
- The script selects the **newest** `MacMD.app` in DerivedData by mtime — not arbitrary `find` order — so a stale previous-version build can't be picked up after a clean build. It prints `Using build: <path>` so you can eyeball the selection.
- The DMG staging dir is cleaned with a `trap` on `EXIT`, so an `hdiutil` failure under `set -e` doesn't leak `/tmp/macmd-dmg.*`.
- Ad-hoc signed. See `project.md` for the notarization path.

## make_social_preview.swift

Generates the 1280x640 GitHub social preview card (`docs/social-preview.png`) by capturing a running MacMD window. The app must be running with a representative file open when you run it.
