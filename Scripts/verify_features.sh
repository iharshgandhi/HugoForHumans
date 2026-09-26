#!/usr/bin/env bash
# Verifies the new editor features end to end, using the shipping code.
#
# A real site is created through the wizard's own path, a page bundle is filled
# the way the editor fills it, and the result is then built with the bundled
# Hugo. That last step is the check that matters: a shortcode that does not
# resolve, or a page resource Hugo cannot find, is a real defect that no unit
# test can see — the files look perfectly correct on disk.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hfh-features.XXXXXX")"
# Kept on failure so the built site can be inspected; removed on success.
cleanup() {
  if [ -n "${KEEP:-}" ] && [ -d "$WORK/site" ]; then
    echo "kept: $WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

BUILD_DIR="$WORK/build"
mkdir -p "$BUILD_DIR/Shim"

# A quoted delimiter passes every backslash through untouched, so the Swift
# below is byte-for-byte what the compiler sees.
cat > "$BUILD_DIR/Shim/driver.swift" <<'SWIFT'
import Foundation
import AppKit

@main
struct FeatureDriver {
    @MainActor
    static func main() async {
        let work = CommandLine.arguments[1]
        let fm = FileManager.default
        try? fm.createDirectory(at: URL(fileURLWithPath: work), withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: work, isDirectory: true)
        let siteRoot = root.appendingPathComponent("features-test")

        // ---- The site, created the way the wizard creates one ----------
        var request = NewSiteRequest()
        request.title = "Features Test"
        request.folderName = "features-test"
        request.destinationFolder = root
        // A theme is required by the request type, so fall back to any known one.
        guard let anyTheme = ThemeCatalog.theme(named: "PaperMod") ?? ThemeCatalog.all.first else {
            print("FAILED: no themes in the catalog")
            exit(1)
        }
        request.theme = anyTheme
        // A theme is what gives Hugo a layout to render with. Without one it
        // writes no HTML at all, which would make this check meaningless.
        request.installTheme = true
        request.createFirstPost = false
        request.hosting = .decideLater

        let creator = SiteCreator()
        _ = await creator.begin(with: request, kind: .blog)
        if let error = creator.error {
            print("FAILED to create the site: \(error)")
            for step in creator.steps where step.state == .failed {
                print("  failed step: " + step.title + " — " + step.detail)
            }
            exit(1)
        }
        print("SITE_CREATED=true")
        print("SHORTCODE_INSTALLED=" + SiteShortcodes.isInstalled(in: siteRoot).description)

        // ---- A page, the way the editor makes one ----------------------
        let engine = SiteEngine()
        engine.openSite(at: siteRoot)
        guard let created = await engine.createPage(section: "posts", name: "first-contact") else {
            print("FAILED to create a page")
            exit(1)
        }

        // ---- An image, imported exactly as the editor does it -----------
        let source = root.appendingPathComponent("holiday.jpg")
        makeJPEG(at: source, width: 640, height: 400)

        var item = created
        var body = "The first thing you notice is the quiet.\n\n"
        do {
            let placed = try MediaLibrary.add(source, to: item, projectRoot: siteRoot, kind: .inline)
            // The page became a leaf bundle, so the item must follow it.
            item = item.relocated(to: placed.pageURL, contentRoot: siteRoot.appendingPathComponent("content"))
            body += "![A quiet room](" + placed.markdownPath + ")\n\nThe rest of it follows.\n"
            print("IMAGE_REF=" + placed.markdownPath)
            print("IMAGE_RENAMED=" + placed.wasRenamed.description)
        } catch {
            print("FAILED to add the image: \(error)")
            exit(1)
        }

        // ---- A video embed, from nothing but a URL ---------------------
        let video = EmbedParser.parse("https://youtu.be/dQw4w9WgXcQ")
        print("EMBED_KIND=" + video.kind.rawValue)
        print("EMBED_ID=" + video.identifier)
        let shortcode = video.markdown
        if shortcode.isEmpty {
            print("EMBED_MARKDOWN=nil")
        } else {
            body += "\n" + shortcode + "\n"
            print("EMBED_MARKDOWN=" + shortcode)
        }

        // ---- An attachment, which must not appear in the body ----------
        let doc = root.appendingPathComponent("notes.pdf")
        try? Data("%PDF-1.4 sample".utf8).write(to: doc)
        do {
            let attached = try MediaLibrary.add(doc, to: item, projectRoot: siteRoot, kind: .attachment)
            print("ATTACHMENT=" + attached.markdownPath)
            print("ATTACHMENT_IN_BODY=" + body.contains("notes.pdf").description)
        } catch {
            print("FAILED to attach: \(error)")
        }

        // ---- The per-page custom script ---------------------------------
        let bundleDir = item.url.deletingLastPathComponent()
        try? "console.log('from the page');\n".write(
            to: bundleDir.appendingPathComponent(PageScript.fileName),
            atomically: true, encoding: .utf8)
        body = PageScript.applyingMarker(true, to: body)
        print("SCRIPT_MARKER=" + PageScript.hasScriptMarker(in: body).description)

        item.frontMatter.body = body
        engine.save(item)

        // ---- Removing an image leaves no broken reference ---------------
        let onDisk = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
        let reference = MediaLibrary.assets(for: item, projectRoot: siteRoot).inline.first
            .map { MediaLibrary.reference(for: $0, page: item, projectRoot: siteRoot) }
        let cleaned = reference.flatMap { MediaMarkdown.removingImageReference($0, from: onDisk) }
        print("REMOVE_FOUND=" + (cleaned != nil).description)
        print("REMOVE_LEFT_REF=" + ((cleaned?.contains(reference ?? "") ?? true)).description)
        print("REMOVE_KEPT_PROSE=" + ((cleaned?.contains("The rest of it follows.") ?? false)).description)

        // ---- The files Hugo will read -----------------------------------
        print("BUNDLE=" + bundleDir.lastPathComponent)
        print("TREE:")
        for entry in Self.tree(siteRoot) { print("TREE=" + entry) }
        for child in (try? fm.contentsOfDirectory(atPath: bundleDir.path))?.sorted() ?? [] {
            print("FILE=" + child)
        }
        print("SITE=" + siteRoot.path)
    }

    /// The project as Hugo sees it, so a misplaced file is obvious.
    static func tree(_ root: URL) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: root.path) else { return [] }
        var lines: [String] = []
        for case let rel as String in walker {
            if rel.hasPrefix("public") || rel.hasPrefix(".git") { continue }
            let full = root.appendingPathComponent(rel)
            let mark = (try? full.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "/" : ""
            lines.append(rel + mark)
        }
        return lines.sorted()
    }

    /// A genuine JPEG, so Hugo's image pipeline and the editor's decoder both
    /// see a real file rather than a buffer of repeated bytes.
    static func makeJPEG(at url: URL, width: Int, height: Int) {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.12, alpha: 1).setFill()
        NSRect(x: 40, y: 40, width: 220, height: 140).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [:]) else { return }
        try? jpeg.write(to: url)
    }
}
SWIFT

HUGO="$ROOT/dist/Hugo for Humans.app/Contents/Resources/bin/hugo"
if [ ! -x "$HUGO" ]; then
  HUGO=$(find "$ROOT/dist" -name hugo -type f 2>/dev/null | head -1)
fi
# The driver is a bare binary, not the .app, so it has no bundled Resources to
# find; putting the real Hugo on PATH is how it gets the same one the app uses.
export PATH="$(dirname "$HUGO"):$PATH"

echo "compiling…"
swiftc -O \
  $(find Sources/HugoForHumans/Core Sources/HugoForHumans/Models -name '*.swift') \
  "$BUILD_DIR/Shim/driver.swift" \
  -o "$BUILD_DIR/drive" 2>&1 | grep -E "error:" | head -12 || true

[ -x "$BUILD_DIR/drive" ] || { echo "could not build the driver"; exit 1; }

echo "running…"
"$BUILD_DIR/drive" "$WORK" | tee "$WORK/report.txt"
SITE=$(grep '^SITE=' "$WORK/report.txt" | cut -d= -f2-)

if [ -n "${HUGO:-}" ] && [ -x "$HUGO" ]; then
  echo
  echo "building with the bundled Hugo…"
  # New pages are drafts, and Hugo skips drafts unless told otherwise.
  ( cd "$SITE" && "$HUGO" --buildDrafts --logLevel info ) 2>&1 | tail -10
  echo
  POST=$(find "$SITE/public" -name "index.html" -path "*first-contact*" | head -1)
  if [ -n "$POST" ] && [ -f "$POST" ]; then
    echo "  at: ${POST#$SITE/public}"
    echo "published the post"
    echo "  image:  $(grep -o 'src="[^"]*holiday[^"]*"' "$POST" | head -1)"
    echo "  script: $(grep -o 'custom\.js' "$POST" | head -1)"
    echo "  video:  $(grep -o 'youtube\.com/embed/[^"]*' "$POST" | head -1)"
  else
    KEEP=1
    echo "no page published; what Hugo produced:"
    find "$SITE/public" -type f | sed "s|$SITE/public|  |" | head -20
    echo "content on disk:"
    find "$SITE/content" -type f | sed "s|$SITE|  |" | head -10
    for f in "$SITE"/content/posts/first-contact/index.md; do
      echo "--- $(basename "$f") ---"
      cat "$f"
    done
    exit 1
  fi
else
  echo "no bundled hugo found; skipped the build check"
fi
