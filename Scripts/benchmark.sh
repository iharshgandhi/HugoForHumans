#!/bin/bash
#
# Measures the real performance of the app and of the engine it wraps.
# Everything here is measured, not estimated.
#
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
HUGO="$ROOT/.build/hugo-binary/hugo"
APP="$ROOT/dist/Hugo for Humans.app/Contents/MacOS/HugoForHumans"

echo "=============================================================="
echo " Hugo for Humans — measured performance"
echo "=============================================================="
echo
echo "Machine: $(uname -m) macOS $(sw_vers -productVersion)"
HVER=$("$HUGO" version | sed -n 's/^hugo \(v[0-9.]*\).*/\1/p')
HKIND=$("$HUGO" version | grep -q extended && echo extended || echo standard)
echo "Engine:  $HVER $HKIND"
echo

# ---------------------------------------------------------------- app binary
if [[ -x "$APP" ]]; then
  BIN_SIZE=$(du -h "$APP" | cut -f1)
  BUNDLE=$(du -sh "$ROOT/dist/Hugo for Humans.app" | cut -f1)
  DMG=$(du -h "$ROOT/dist/Hugo for Humans-0.1.0.dmg" 2>/dev/null | cut -f1)
  echo "--- Application ---"
  echo "  binary          $BIN_SIZE"
  echo "  bundle (w/ Hugo)  $BUNDLE"
  echo "  disk image         ${DMG:-n/a}"
else
  echo "--- Application: not built ---"
fi
echo

# ---------------------------------------------------------------- cold start
if [[ -x "$APP" ]]; then
  echo "--- Cold launch (time to first window) ---"
  for i in 1 2 3; do
    pkill -f HugoForHumans 2>/dev/null; sleep 1
    START=$(python3 -c 'import time; print(time.time())')  # seconds, float
    open "$APP" 2>/dev/null
    PID=""
    for _ in $(seq 1 60); do
      sleep 0.1
      PID=$(pgrep -f HugoForHumans | head -1)
      [[ -n "$PID" ]] && break
    done
    if [[ -n "$PID" ]]; then
      python3 -c "import time; print(f'  run $i  {time.time()-$START:.2f}s to process')"
      sleep 1
      RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
      THREADS=$(ps -M "$PID" 2>/dev/null | wc -l | tr -d ' ')
      echo "        ${RSS}KB resident, ${THREADS} threads"
    else
      echo "  run $i  failed to start"
    fi
  done
  pkill -f HugoForHumans 2>/dev/null
  echo
fi

# ---------------------------------------------------------------- build perf
SITE="$ROOT/dist/sample/the-deep-dive"
if [[ -d "$SITE" ]]; then
  echo "--- Build performance: the demo site ---"
  PAGES=$(cd "$SITE" && "$HUGO" -D 2>&1 | grep 'Pages' | sed -n 's/.*│ *\([0-9][0-9]*\) *$/\1/p' | head -1)
  TIMES=()
  for i in 1 2 3 4 5; do
    (cd "$SITE" && rm -rf public resources && "$HUGO" -D 2>&1) | grep 'Total in' | sed -n 's/.*Total in *\([0-9][0-9]*\) *ms.*/\1/p'
  done > /tmp/hfh_times.txt
  echo "  pages generated  ${PAGES:-?}"
  echo "  build times      $(tr '\n' ' ' < /tmp/hfh_times.txt) ms (cold, 5 runs)"
  echo "  output size      $(du -sh "$SITE/public" 2>/dev/null | cut -f1)"
  echo
fi

# ---------------------------------------------------------------- scale
SCALE=/tmp/hfh-scale
rm -rf "$SCALE"
"$HUGO" new site "$SCALE" >/dev/null 2>&1
if [[ -d "$SCALE" ]]; then
  mkdir -p "$SCALE/content/posts"
  for i in $(seq 1 500); do
    printf -- "---\ntitle: \"Post %d\"\ndate: 2026-01-01\n---\n\nBody for post %d.\n" "$i" "$i" \
      > "$SCALE/content/posts/post-$i.md"
  done
  if [[ -d "$SITE/themes/PaperMod" ]]; then
    mkdir -p "$SCALE/themes"
    cp -R "$SITE/themes/PaperMod" "$SCALE/themes/"
    printf 'baseURL = "https://example.org/"\ntitle = "Scale"\ntheme = "PaperMod"\n' > "$SCALE/hugo.toml"
  fi
  echo "--- Scale: 500 posts ---"
  COUNT=$(ls "$SCALE"/content/posts/*.md 2>/dev/null | wc -l | tr -d ' ')
  for i in 1 2 3; do
    (cd "$SCALE" && rm -rf public resources && "$HUGO" -D 2>&1) | grep 'Total in' | sed -n 's/.*Total in *\([0-9][0-9]*\) *ms.*/\1/p' | tr '\n' ' '
  done
  echo "ms for $COUNT posts -> $(find "$SCALE/public" -name '*.html' 2>/dev/null | wc -l | tr -d ' ') html pages, $(du -sh "$SCALE/public" 2>/dev/null | cut -f1)"
  echo
  rm -rf "$SCALE"
fi

# ---------------------------------------------------------------- codebase
echo "--- Codebase ---"
SRC=$(find "$ROOT/Sources" -name "*.swift" | wc -l | tr -d ' ')
LINES=$(find "$ROOT/Sources" -name "*.swift" -exec cat {} + | wc -l | tr -d ' ')
echo "  swift files      $SRC"
echo "  lines of swift   $LINES"
echo
echo "=============================================================="
