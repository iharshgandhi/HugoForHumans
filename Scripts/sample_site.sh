#!/bin/bash
#
# Builds the demo site used in the presentation, using the app's own code:
# the same SiteCreator the wizard calls, the same SiteEngine, the same Builder.
#
#   ./Scripts/sample_site.sh [output-directory]
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

OUT_DIR="${1:-$ROOT/dist/sample}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

DRIVER_SRC="$ROOT/.build/make_sample_site.generated.swift"
sed "s|DEST_PLACEHOLDER|$OUT_DIR|g" \
    "$ROOT/Scripts/make_sample_site.swift" > "$DRIVER_SRC"

# The app's sources, minus its @main entry point, plus the driver above.
SOURCES=()
while IFS= read -r line; do SOURCES+=("$line"); done < <(
  find "$ROOT/Sources/HugoForHumans" -name "*.swift" ! -name "HugoForHumansApp.swift" -print | sort
)
SOURCES+=("$DRIVER_SRC")

BIN="$ROOT/.build/sample-site-bin"
echo "==> Compiling the sample-site driver"
swiftc -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -o "$BIN" "${SOURCES[@]}"

echo "==> Creating the site through the app"
export PATH="$ROOT/.build/hugo-binary:$PATH"
"$BIN" | sed 's/^/   /'

SITE="$OUT_DIR/the-deep-dive"
echo
echo "==> Built output"
ls -1 "$SITE/public"/*.html 2>/dev/null | sed 's|.*/|   |'
echo "   site: $SITE"
