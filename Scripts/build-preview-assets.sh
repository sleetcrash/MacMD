#!/bin/bash
# Regenerates the bundled preview assets committed under MacMD/Preview/:
#   markdown-it.min.js  markdown-it 14.2.0 UMD minified build, copied verbatim
#                       (exposes the global `markdownit` factory).
#   mermaid.min.js      mermaid 11.16.0 (ESM-only) bundled to ONE self-contained
#                       IIFE via esbuild, exposing `window.mermaid` with
#                       run()/initialize() reachable directly (a --global-name
#                       re-export would expose window.mermaid.default instead).
#
# The outputs are committed artifacts; this script exists only for reproducibility
# and version bumps. It needs network access and a Node toolchain (node, npm, npx).
# Do NOT wire it as an Xcode run-script phase: ENABLE_USER_SCRIPT_SANDBOXING blocks
# network, and the outputs are already vendored. Both bundles are MIT-licensed.
#
# Known-good toolchain (2026-07-01): node 25, npm 11, esbuild 0.28.1.
set -euo pipefail

MARKDOWN_IT_VERSION="14.2.0"
MERMAID_VERSION="11.16.0"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/MacMD/Preview"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
cd "$BUILD"

npm install --no-audit --no-fund \
  "markdown-it@$MARKDOWN_IT_VERSION" "mermaid@$MERMAID_VERSION" esbuild@latest

cp node_modules/markdown-it/dist/markdown-it.min.js "$DEST/markdown-it.min.js"

printf 'import mermaid from "mermaid";\nwindow.mermaid = mermaid;\n' > mermaid-entry.mjs
node_modules/.bin/esbuild mermaid-entry.mjs --bundle --format=iife --minify \
  --outfile="$DEST/mermaid.min.js"

echo "Vendored into $DEST:"
node -e "console.log('  markdown-it', require('markdown-it/package.json').version); console.log('  mermaid', require('mermaid/package.json').version); console.log('  esbuild', require('esbuild/package.json').version)"
ls -la "$DEST/markdown-it.min.js" "$DEST/mermaid.min.js"
