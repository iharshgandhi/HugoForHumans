import SwiftUI
import AppKit

// Renders the app's real views offscreen and writes a PNG, so the UI can be
// checked without screen-recording or accessibility permissions. This exercises
// the same view code the app ships, not a mock.


/// Draws AppKit-backed subviews into an existing bitmap, depth first.
///
/// `layer.render(in:)` draws SwiftUI's own layers but not the AppKit controls
/// hosted inside them, so a screenshot of a `List` or an `NSTextView` comes out
/// empty. Asking each one to `cacheDisplay` into the same context composites the
/// whole tree — and unlike a window capture it needs no screen-recording
/// permission, which is why this replaced `CGWindowListCreateImage`.
func drawAppKitSubviews(of view: NSView, into rep: NSBitmapImageRep, offset: CGPoint = .zero) {
    for subview in view.subviews {
        // `frame` is in the superview's coordinates, so a nested control drawn at
        // its own frame lands in the wrong place — which is what put a second,
        // differently-scaled copy of the editor in the bitmap. Converting to the
        // root view's space is the fix.
        let origin = NSPoint(x: offset.x + subview.frame.origin.x,
                             y: offset.y + subview.frame.origin.y)

        if let subRep = subview.bitmapImageRepForCachingDisplay(in: subview.bounds) {
            subview.cacheDisplay(in: subview.bounds, to: subRep)
            if let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
                // The bitmap's origin is bottom-left; the subview's is top-left.
                let height = rep.size.height
                if let image = cgImage(from: subRep) {
                    ctx.saveGState()
                    ctx.translateBy(x: origin.x, y: height - origin.y - subview.bounds.height)
                    ctx.draw(image, in: CGRect(origin: .zero, size: subview.bounds.size))
                    ctx.restoreGState()
                }
            }
        }
        drawAppKitSubviews(of: subview, into: rep, offset: origin)
    }
}

/// A bitmap's own `CGImage`, via a throwaway context.
///
/// `NSBitmapImageRep.cgImage` is not available here, and `CGContext` cannot be
/// constructed from a rep directly, so a context is made to produce one.
private func cgImage(from rep: NSBitmapImageRep) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    rep.draw(in: CGRect(origin: .zero, size: rep.size))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()

}

@MainActor
func render<V: View>(_ view: V, size: CGSize, to path: String, settle: TimeInterval = 1.2, needsOnscreenDraw: Bool = false) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
    window.contentView = hosting
    // Ordered front from the start: a view that has never been on screen has no
    // layout, and an unlaid-out NSTextView collapses to a single line.
    window.orderFront(nil)

    // Let SwiftUI lay out and any async work (Hugo probes) settle.
    let deadline = Date().addingTimeInterval(settle)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write(Data("could not make a bitmap rep\n".utf8))
        exit(1)
    }
    if let layer = hosting.layer,
       let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
        // AppKit's origin is bottom-left; the layer's is top-left.
        ctx.translateBy(x: 0, y: hosting.bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
    } else {
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
    }

    if needsOnscreenDraw {
        let settleAgain = Date().addingTimeInterval(0.8)
        while Date() < settleAgain { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        hosting.displayIfNeeded()
        // The layer pass above already drew everything, including the inspector.
        // Compositing the AppKit subviews on top of that draws them twice, at two
        // different offsets, which reads as a duplicated panel. The bitmap is
        // therefore cleared and only the subview pass is kept.
        //
        // `rep.size = ...` does not clear anything: it reallocates lazily, and
        // the existing pixels survive. An explicit fill does.
        rep.size = NSSize(width: hosting.bounds.width, height: hosting.bounds.height)
        if let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: rep.size))
        }
        drawAppKitSubviews(of: hosting, into: rep)
    }

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    } else {
        FileHandle.standardError.write(Data("could not encode \(path)\n".utf8))
    }
    window.orderOut(nil)
}

func makeScreenshotDirectory() -> URL {
    let dir = URL(fileURLWithPath: "SCRATCH_PLACEHOLDER", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}


/// The same environment the @main App struct installs. Views read all four, so
/// a partial environment crashes at render time.
@MainActor
func appRoot(engine: SiteEngine) -> some View {
    RootView()
        .environmentObject(engine)
        .environmentObject(PreviewServer())
        .environmentObject(Builder())
        .environmentObject(SiteCreator())
        .frame(minWidth: 1040, minHeight: 680)
}

/// Draws a test image: flat colour, a rule, and legible text. A real photo
/// would be better but this proves the pixels are decoded and laid out.
func makeSampleImage(at url: URL, width: Int, height: Int) {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.18, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // AppKit's origin is bottom-left, so these sit in the lower half of the
    // bitmap — which is the half that is not cropped away.
    NSColor(calibratedRed: 0.93, green: 0.48, blue: 0.13, alpha: 1).setFill()
    NSRect(x: 60, y: 90, width: 220, height: 12).fill()

    let title = "Figure 1 — the original tape"
    title.draw(at: NSPoint(x: 60, y: 150),
               withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: NSColor.white,
               ])
    let sub = "12 March, 04:12"
    sub.draw(at: NSPoint(x: 60, y: 118),
             withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1),
             ])
    image.unlockFocus()
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
}

/// The hosting question, shown with a real request so the form is populated the
/// way it would be mid-wizard.
struct HostingStepPreview: View {
    @State private var request: NewSiteRequest = {
        var r = NewSiteRequest()
        r.title = "The Deep Dive"
        r.hosting = .githubPages
        r.githubUser = "geraldvoss"
        r.githubRepo = "the-deep-dive"
        return r
    }()

    @State private var showHint = false

    var body: some View {
        HostingQuestion(request: $request, showHint: $showHint)
    }
}

@main
struct ScreenshotDriver {
    @MainActor static func main() { run() }
}

@MainActor
func run() {
    let out = makeScreenshotDirectory()

    // 1. The onboarding screen — first thing a new user sees.
    render(appRoot(engine: SiteEngine()),
           size: CGSize(width: 1280, height: 800),
           to: out.appendingPathComponent("01-welcome.png").path)

    // 2. A real site, opened through the real engine, rendered in the workspace.
    let siteRoot = URL(fileURLWithPath: "SITE_PLACEHOLDER", isDirectory: true)
    let engine = SiteEngine()
    engine.openSite(at: siteRoot)

    render(appRoot(engine: engine),
           size: CGSize(width: 1440, height: 900),
           to: out.appendingPathComponent("02-workspace.png").path, settle: 2.0,
           needsOnscreenDraw: true)


    // 3. A real post, so the deck shows genuine long-form content in the editor.
    // (3b follows and adds an image to a different page.)
    // Deliberately a page with no image: this shot is the control the inline
    // renderer is measured against, so it must not contain the thing being
    // measured.
    if let post = engine.items.first(where: { $0.frontMatter["title"]?.stringValue.contains("Tape") == true })
        ?? engine.items.first(where: {
            $0.kind == .page && !$0.frontMatter.body.contains("![")
        }) {
        engine.selectedItemID = post.id
        print("03 renders: " + post.relativePath + "  hasImage=" + post.frontMatter.body.contains("![").description)
        let showInspector = Binding.constant(true)
        render(EditorPane(item: post, showInspector: showInspector)
                    .environmentObject(engine)
                    .environmentObject(PreviewServer())
                    .environmentObject(Builder())
                    .environmentObject(SiteCreator()),
               size: CGSize(width: 1180, height: 800),
               to: out.appendingPathComponent("03-editor.png").path, settle: 2.5,
               needsOnscreenDraw: true)
    }

    // 3b. A page with a real image in it, so the inline rendering is visible
    // rather than assumed. The file is added through the shipping code path, so
    // what the editor shows is what a user would get.
    // A *named* page, chosen by title rather than by "whatever has no image
    // yet". Filtering on absence of an image is what made this non-idempotent:
    // every run disqualified the page it had just written to, so it moved on to
    // the next one and left an image behind on each. A fixed target means the
    // same page is reused every time.
    let editorImageTitle = "Against the Alien Thing"
    if let target = engine.items.first(where: {
        $0.frontMatter["title"]?.stringValue.contains(editorImageTitle) == true
    }) ?? engine.items.first {
        let imageSource = siteRoot.deletingLastPathComponent()
            .appendingPathComponent("editor-inline.png")
        if !FileManager.default.fileExists(atPath: imageSource.path) {
            makeSampleImage(at: imageSource, width: 900, height: 500)
        }

        // Reusing the image already on the page, so repeated runs do not pile up
        // `editor-inline-2.png`, `-3.png` and leave the demo site littered.
        //
        // The screenshot is taken either way: gating the render on this check
        // made it silently stop happening on the second run, which looks exactly
        // like a broken feature.
        let alreadyPresent = MediaLibrary.assets(for: target, projectRoot: siteRoot)
            .inline.contains { $0.url.lastPathComponent.hasPrefix("editor-inline") }
        var pageToRender = target

        if !alreadyPresent {
            do {
                let placed = try MediaLibrary.add(imageSource, to: target, projectRoot: siteRoot, kind: .inline)
                var page = target.relocated(to: placed.pageURL,
                                            contentRoot: siteRoot.appendingPathComponent("content"))
                let alt = "A wide blue field with a single line of text"
                var body = page.frontMatter.body
                if !body.contains(placed.markdownPath) {
                    body = "The notes below are the whole of it.\n\n![\(alt)](\(placed.markdownPath))\n\nNothing else was ever filed."
                }
                page.frontMatter.body = body
                engine.save(page)
                engine.scanContent()
                pageToRender = page
                print("image added: " + placed.markdownPath)
            } catch {
                print("could not add the image: " + error.localizedDescription)
            }
        } else {
            print("reusing the image already on the page")
        }

        if let updated = engine.item(withID: pageToRender.relativePath) {
            print("04 renders: " + updated.relativePath + "  hasImage=" + updated.frontMatter.body.contains("![").description)
            engine.selectedItemID = updated.id
            render(EditorPane(item: updated, showInspector: Binding.constant(true))
                        .environmentObject(engine)
                        .environmentObject(PreviewServer())
                        .environmentObject(Builder())
                        .environmentObject(SiteCreator()),
                   size: CGSize(width: 1180, height: 800),
                   to: out.appendingPathComponent("04-editor-image.png").path, settle: 2.5,
                   needsOnscreenDraw: true)
        } else {
            print("could not reload the page to render")
        }
    }

    // 4. Site settings, showing the real generated hugo.toml.
    render(SiteSettingsView()
                .environmentObject(engine)
                .environmentObject(PreviewServer())
                .environmentObject(Builder())
                .environmentObject(SiteCreator()),
           size: CGSize(width: 900, height: 800),
           to: out.appendingPathComponent("05-settings.png").path, settle: 1.5, needsOnscreenDraw: true)

    // 5. The publish screen with a finished build.
    render(PublishView()
                .environmentObject(engine)
                .environmentObject(PreviewServer())
                .environmentObject(Builder())
                .environmentObject(SiteCreator()),
           size: CGSize(width: 1000, height: 800),
           to: out.appendingPathComponent("06-publish.png").path, settle: 1.5, needsOnscreenDraw: true)

    // 3. The editor itself, rendered directly. NavigationSplitView's sidebar is a
    // List that does not paint in an offscreen snapshot, so the writing surface
    // is captured on its own — this is the same EditorPane the workspace shows.
    if let page = engine.items.first(where: { $0.kind == .page }) ?? engine.items.first {
        engine.selectedItemID = page.id
        // EditorPane toggles its front-matter inspector through a binding; the
        // renderer only needs a valid binding, not interactive state.
        let showInspector = Binding.constant(true)
        _ = page
    }

    // 4. Themes, the other screen a new user is sent to.
    render(ThemesView()
                .environmentObject(engine)
                .environmentObject(PreviewServer())
                .environmentObject(Builder())
                .environmentObject(SiteCreator()),
           size: CGSize(width: 1200, height: 820),
           to: out.appendingPathComponent("04-themes.png").path, settle: 2.0, needsOnscreenDraw: true)

    // 6. The hosting question asked during setup, which decides the baseURL.
    render(HostingStepPreview()
                .environmentObject(engine)
                .environmentObject(PreviewServer())
                .environmentObject(Builder())
                .environmentObject(SiteCreator()),
           size: CGSize(width: 900, height: 780),
           to: out.appendingPathComponent("07-hosting.png").path, settle: 1.5, needsOnscreenDraw: true)

    // 7. The deploy screen, generated entirely from the target registry.
    render(DeployView()
                .environmentObject(engine)
                .environmentObject(PreviewServer())
                .environmentObject(Builder())
                .environmentObject(SiteCreator()),
           size: CGSize(width: 1000, height: 820),
           to: out.appendingPathComponent("08-deploy.png").path, settle: 1.5, needsOnscreenDraw: true)

    // 5. Site settings.
    print("site: \(siteRoot.path)")
    print("items: \(engine.items.count)")
    print("theme: \(engine.config.theme)")
}
