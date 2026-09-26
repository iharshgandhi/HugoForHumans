#!/bin/bash
#
# Screenshots the published demo site for the presentation.
#
#   ./Scripts/site_screenshots.sh
#
# Starts a real `hugo server` on the generated site, captures the pages with
# headless Chrome at their true content height, and stops the server. The
# images land in dist/assets/ and are what the deck embeds.
#
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

SITE="$ROOT/dist/sample/the-deep-dive"
OUT="$ROOT/dist/assets"
PORT=1313
HUGO="$ROOT/.build/hugo-binary/hugo"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH=1440
VH=1400

if [[ ! -d "$SITE" ]]; then
  echo "no demo site at $SITE — run ./Scripts/sample_site.sh first" >&2
  exit 1
fi
if [[ ! -x "$HUGO" ]]; then
  echo "no hugo binary at $HUGO" >&2
  exit 1
fi
if [[ ! -x "$CHROME" ]]; then
  echo "no Chrome at $CHROME — cannot capture the published site" >&2
  exit 1
fi
mkdir -p "$OUT"

# Fail if something is already holding the port, so we never capture the wrong
# site (or another project's dev server) and label it as ours.
if curl -sf -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then
  echo "port $PORT is already in use; stop it first so the capture is honest" >&2
  exit 1
fi

echo "==> Starting hugo server on :$PORT"
( cd "$SITE" && exec "$HUGO" server --port "$PORT" --buildDrafts ) >/tmp/hfh-site.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT

for _ in $(seq 1 40); do
  sleep 0.5
  curl -sf -o /dev/null "http://localhost:$PORT/" && break
done
curl -sf -o /dev/null "http://localhost:$PORT/" || {
  echo "server did not come up:" >&2
  cat /tmp/hfh-site.log >&2
  exit 1
}
echo "==> serving; capturing"

# page slug -> output name. The post is the one that shows Markdown rendering.
capture() {
  local name="$1" path="$2" full="/tmp/_site_$1.png"
  # Render at a laptop-sized viewport, then crop to the content bounds. A very
  # tall viewport would stretch the page out and defeat the trim.
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --window-size="$WIDTH,$VH" --virtual-time-budget=3000 \
    --screenshot="$full" "http://localhost:$PORT$path" >/dev/null 2>&1
  if [[ ! -s "$full" ]]; then
    echo "   failed: $path" >&2
    return 1
  fi
  local h
  h=$(python3 "$ROOT/Scripts/trim_screenshot.py" "$full" "$OUT/$name.png")
  echo "   $name.png  ${WIDTH}x${h}"
}

capture site-home      "/"
capture site-post      "/posts/the-tape-that-does-not-add-up/"
capture site-section   "/posts/"

echo "==> done"
