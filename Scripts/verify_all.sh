#!/usr/bin/env bash
#
# The full check for this round of work, in the order that catches problems
# earliest:
#
#   1. build, so a compile error stops everything
#   2. unit tests
#   3. the new editor features against a real Hugo build
#   4. the screenshots, and a pixel check that an image really is drawn
#   5. the release app and DMG
#
# Step 4 matters more than it looks. Every part of the inline-image feature was
# correct on disk and in the model while the editor showed nothing, so "the
# files look right" proved nothing at all until the screenshot was measured.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

step() { printf '\n==> %s\n' "$1"; }

step "Build"
swift build 2>&1 | tail -1

step "Tests"
./Scripts/test.sh 2>&1 | tail -3

step "Portability: Apple-only imports guarded"
python3 Scripts/check_portability.py | tail -3

step "Editor features, built and published with Hugo"
./Scripts/verify_features.sh 2>&1 | tail -5

step "Screenshots"
./Scripts/screenshots.sh 2>&1 | grep -E "^wrote" | sed 's|.*/||' || true

step "Inline image actually drawn?"
python3 Scripts/check_inline_render.py dist/screenshots/04-editor-image.png
echo "--- control: an editor with no image must not pass ---"
if python3 Scripts/check_inline_render.py dist/screenshots/03-editor.png; then
  echo "FAILED: the check cannot tell the two screenshots apart"
  exit 1
fi
echo "control correctly fails"

step "Release build"
./Scripts/build.sh 2>&1 | tail -3

printf '\nAll checks passed.\n'
