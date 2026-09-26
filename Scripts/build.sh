#!/bin/bash
#
# Builds Hugo for Humans.app, with a real Hugo binary inside it.
#
# The app must be self-contained: a user who installs the .dmg should never have
# to install Homebrew, Go, or Hugo separately. macOS only ships Hugo as a .pkg,
# so the binary is extracted from that package at build time.
#
# Usage:
#   ./Scripts/build.sh              release build + .dmg
#   ./Scripts/build.sh --no-dmg     release build only
#   ./Scripts/build.sh --debug      debug build
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Hugo for Humans"
BUNDLE_ID="com.hugoforhumans.app"
VERSION="0.1.0"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/$APP_NAME.app"
DIST="$ROOT/dist"
HUGO_VERSION="0.166.0"
HUGO_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_darwin-universal.pkg"

CONFIG="release"
MAKE_DMG=1
for arg in "$@"; do
  case "$arg" in
    --no-dmg) MAKE_DMG=0 ;;
    --debug)  CONFIG="debug" ;;
  esac
done

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/HugoForHumans"
if [[ ! -x "$BINARY" ]]; then
  echo "error: build produced no binary at $BINARY" >&2
  exit 1
fi

# ---------------------------------------------------------------- Hugo binary
HUGO_CACHE="$ROOT/.build/hugo-binary"
HUGO_BIN="$HUGO_CACHE/hugo"

fetch_hugo() {
  if [[ -x "$HUGO_BIN" ]] && "$HUGO_BIN" version >/dev/null 2>&1; then
    echo "==> Reusing cached Hugo at $HUGO_BIN"
    return
  fi
  echo "==> Fetching Hugo extended v$HUGO_VERSION"
  mkdir -p "$HUGO_CACHE"
  local pkg="$HUGO_CACHE/hugo.pkg"
  local expanded="$HUGO_CACHE/pkg"

  curl -fsSL --retry 3 -o "$pkg" "$HUGO_URL"
  rm -rf "$expanded"
  pkgutil --expand "$pkg" "$expanded"
  # The package payload is a gzipped cpio archive containing ./hugo
  ( cd "$expanded" && tar -xzf Payload )
  mv "$expanded/hugo" "$HUGO_BIN"
  rm -rf "$expanded" "$pkg"
  chmod +x "$HUGO_BIN"
}

fetch_hugo
echo "==> $( "$HUGO_BIN" version )"

# ---------------------------------------------------------------- App bundle
echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/bin"

cp "$BINARY" "$APP_DIR/Contents/MacOS/HugoForHumans"
cp "$HUGO_BIN" "$APP_DIR/Contents/Resources/bin/hugo"

# Hugo is Apache-2.0, not MIT. Its licence has to travel with the binary.
[[ -f "$ROOT/Vendor/hugo-LICENSE.txt" ]] || { echo "missing Vendor/hugo-LICENSE.txt" >&2; exit 1; }
cp "$ROOT/Vendor/hugo-LICENSE.txt" "$APP_DIR/Contents/Resources/hugo-LICENSE.txt"
cp "$ROOT/NOTICE" "$APP_DIR/Contents/Resources/NOTICE"
chmod +x "$APP_DIR/Contents/MacOS/HugoForHumans" "$APP_DIR/Contents/Resources/bin/hugo"

# ---------------------------------------------------------------- Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>            <string>HugoForHumans</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSHumanReadableCopyright</key>      <string>Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and Buho Smart Tools (buho.co.in). Licensed under GPL-3.0-or-later. Bundles Hugo, copyright the Hugo Authors, Apache-2.0.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>    <string>Folder</string>
            <key>CFBundleTypeRole</key>    <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array><string>public.folder</string></array>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>Hugo Site</string>
            <key>CFBundleURLSchemes</key> <array><string>hugohumans</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- Icon
echo "==> Generating app icon"
# Loud on failure. This previously printed a note and continued, which is how an
# empty AppIcon.icns shipped unnoticed: the app had no icon in Finder or the Dock.
if ! swift "$ROOT/Scripts/make_icon.swift" "$APP_DIR/Contents/Resources/AppIcon.icns"; then
  echo "   error: icon generation failed" >&2
  exit 1
fi
if [[ ! -s "$APP_DIR/Contents/Resources/AppIcon.icns" ]]; then
  echo "   error: AppIcon.icns was not produced" >&2
  exit 1
fi
echo "   icon written ($(du -h "$APP_DIR/Contents/Resources/AppIcon.icns" | cut -f1))"

# ---------------------------------------------------------------- Signing
# Ad-hoc signature: enough for the app to launch locally and for the DMG to
# verify. A real release would use a Developer ID.
echo "==> Signing (ad-hoc)"
# Strip inherited extended attributes first. The Hugo binary we bundle carries a
# com.apple.provenance attribute, and hdiutil fails with a misleading "No space
# left on device" when it later mounts and reads a staged bundle that has one.
# Clearing before signing keeps the DMG build working.
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP_DIR" 2>&1 | sed 's/^/   /' || {
  echo "   warning: ad-hoc signing failed" >&2
}
codesign --verify --deep --strict "$APP_DIR" 2>&1 | sed 's/^/   /' || true

# ---------------------------------------------------------------- Launch check
echo "==> Smoke test: verifying the bundle can find its Hugo"
if "$APP_DIR/Contents/Resources/bin/hugo" version >/dev/null 2>&1; then
  echo "   bundled Hugo runs correctly"
else
  echo "   warning: bundled Hugo did not run from the bundle" >&2
fi

echo "==> Built: $APP_DIR"

# ---------------------------------------------------------------- DMG
if [[ "$MAKE_DMG" == "1" ]]; then
  DMG="$DIST/$APP_NAME-$VERSION.dmg"
  echo "==> Creating $DMG"
  rm -f "$DMG"

  # hdiutil mounts its source folder under /Volumes to read it. Staging under a
  # space-free directory keeps that path simple; the .app keeps its real name
  # inside, which is what the user sees when the DMG is mounted.
  STAGE_ROOT="$(mktemp -d)"
  STAGE="$STAGE_ROOT/stage"
  mkdir -p "$STAGE"
  cp -R "$APP_DIR" "$STAGE/$APP_NAME.app"
  # A symlink is what makes drag-to-Applications work from a mounted DMG.
  ln -s /Applications "$STAGE/Applications"

  # Signing re-applies com.apple.provenance to the bundled Hugo, and hdiutil then
  # fails to read the staged copy with a misleading "No space left on device".
  # Clearing it on the staged copy — the shipped .app is untouched — is the fix.
  xattr -cr "$STAGE/$APP_NAME.app" 2>/dev/null || true

  # Build the image in a temp location and move it into dist afterwards.
  # hdiutil mounts the source folder under /Volumes, and writing the image into
  # dist/ — the same tree that holds the source bundle — can fail with a
  # misleading "No space left on device". Building elsewhere and moving is safer.
  DMG_TMP_DIR="$(mktemp -d)"
  DMG_TMP="$DMG_TMP_DIR/$APP_NAME-$VERSION.dmg"

  # hdiutil also fails intermittently on large bundles — the same input succeeds
  # and fails across runs, with plenty of free space. It is a tool-level hiccup,
  # not a real condition, so retry a few times before giving up.
  DMG_OK=0
  for attempt in 1 2 3 4; do
    echo "    attempt $attempt"
    if hdiutil create \
         -volname "$APP_NAME" \
         -srcfolder "$STAGE" \
         -ov -format UDZO \
         "$DMG_TMP" >/dev/null 2>&1; then
      DMG_OK=1
      break
    fi
    # Each failed attempt can leave a partial image and a stale mount behind.
    rm -f "$DMG_TMP"
    sleep 2
  done

  if [[ "$DMG_OK" != "1" ]]; then
    echo "   error: could not create the disk image after 4 attempts" >&2
    rm -rf "$DMG_TMP_DIR"
    exit 1
  fi

  mv "$DMG_TMP" "$DMG"
  rm -rf "$DMG_TMP_DIR"

  rm -rf "$STAGE_ROOT"
  echo "==> Built: $DMG"
  ls -lh "$DMG" | awk '{print "   size: " $5}'
fi

echo
echo "Done. Open the app with:  open \"$APP_DIR\""
