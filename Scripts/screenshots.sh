#!/bin/bash
#
# Renders the app's real views to PNGs, so the UI can be reviewed without
# screen-recording or accessibility permissions.
#
#   ./Scripts/screenshots.sh [output-directory]
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUT_DIR="${1:-$ROOT/dist/screenshots}"
mkdir -p "$OUT_DIR"

# The real demo site, so every screenshot shows genuine content rather than
# placeholder files. Built once by sample_site.sh; rebuilt here if missing.
SITE="$ROOT/dist/sample/the-deep-dive"
if [[ ! -d "$SITE/content" ]]; then
  echo "==> Building the sample site first"
  "$ROOT/Scripts/sample_site.sh" "$ROOT/dist/sample" >/dev/null
fi

# The renderer is compiled against the same sources as the app, with the app's
# @main file left out so this can have its own entry point.
SOURCES=()
while IFS= read -r line; do SOURCES+=("$line"); done < <(
  find "$ROOT/Sources/HugoForHumans" -name "*.swift" \
       ! -name "HugoForHumansApp.swift" -print | sort
)
SOURCES+=("$ROOT/Scripts/render_screenshots.swift")

BIN="$ROOT/.build/screenshots-bin"
echo "==> Compiling renderer"

# The two placeholders are substituted here so render_screenshots.swift stays a
# plain source file with no build-specific paths in it.
RENDER_SRC="$ROOT/.build/render_screenshots.generated.swift"
sed -e "s|SCRATCH_PLACEHOLDER|$OUT_DIR|g" \
    -e "s|SITE_PLACEHOLDER|$SITE|g" \
    "$ROOT/Scripts/render_screenshots.swift" > "$RENDER_SRC"

SOURCES=()
while IFS= read -r line; do SOURCES+=("$line"); done < <(
  find "$ROOT/Sources/HugoForHumans" -name "*.swift" ! -name "HugoForHumansApp.swift" -print | sort
)

# RootView lives after the @main entry point in the app file. Only that one
# struct is needed here, so it is extracted by name rather than by position.
APP_SRC="$ROOT/Sources/HugoForHumans/App/HugoForHumansApp.swift"
{ echo "import SwiftUI"; echo "import AppKit"
  awk '/^struct RootView: View \{/{ keep = 1 }
       keep && /^\}/{ print; exit }
       keep { print }' "$APP_SRC"
} > "$ROOT/.build/appviews.generated.swift"

SOURCES+=("$ROOT/.build/appviews.generated.swift" "$RENDER_SRC")

swiftc -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -o "$BIN" "${SOURCES[@]}"

echo "==> Rendering"
export PATH="$ROOT/.build/hugo-binary:$PATH"
"$BIN" | sed 's/^/   /'

# The renderer takes the paths from placeholders so the source stays generic.
ls -1 "$OUT_DIR"/*.png 2>/dev/null | sed 's/^/   /'
echo "Done: $OUT_DIR"
