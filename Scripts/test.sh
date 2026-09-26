#!/bin/bash
#
# Builds and runs the test suite.
#
# Why not `swift test`: executing an XCTest bundle needs a full Xcode install,
# and the Command Line Tools alone cannot run one. So the suite is compiled
# directly — the app's Core/Models/Design sources plus the tests — into a single
# binary that reports its own results. This works anywhere the app builds.
#
#   ./Scripts/test.sh              run everything
#   ./Scripts/test.sh FrontMatter  run one suite (substring match)
#   ./Scripts/test.sh --verbose    also print the Hugo binary in use
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/.build/tests"

mkdir -p "$OUT"

# The app's @main lives in App/HugoForHumansApp.swift; the tests provide their own
# entry point, so that file is excluded. Everything else is shared.
# (mapfile is bash 4+; macOS ships bash 3.2, so read the list the portable way.)
SOURCES=()
while IFS= read -r line; do
  SOURCES+=("$line")
done < <(
  find "$ROOT/Sources/HugoForHumans/Core" \
       "$ROOT/Sources/HugoForHumans/Models" \
       "$ROOT/Sources/HugoForHumans/Design" \
       "$ROOT/Sources/Tests" \
       -name "*.swift" -print | sort
)

echo "==> Compiling ${#SOURCES[@]} source files"
swiftc \
  -parse-as-library \
  -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" \
  -o "$OUT/hfh-tests" \
  "${SOURCES[@]}"

# The test binary is not inside a .app, so HugoBinary cannot find a bundled copy.
# Put the build script's cached Hugo on PATH — the same one that gets bundled
# into the app, so the tests exercise the real shipping engine.
HUGO_DIR="$ROOT/.build/hugo-binary"
if [[ -x "$HUGO_DIR/hugo" ]]; then
  export PATH="$HUGO_DIR:$PATH"
  export HUGO_CACHEDIR="$ROOT/.build/tests/hugo_cache"
  echo "==> Using Hugo: $("$HUGO_DIR/hugo" version)"
else
  echo "==> No cached Hugo at $HUGO_DIR; run ./Scripts/build.sh first for end-to-end tests"
fi

echo "==> Running"
"$OUT/hfh-tests" "$@"
