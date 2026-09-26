// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
import AppKit
import ImageIO

/// Finds `![alt](path)` in Markdown and loads the image, so the writing surface
/// can show the picture rather than its filename.
///
/// This is deliberately a *view* concern: the document is still plain Markdown
/// and still saves as Markdown. The image is a rendering of the text, never a
/// replacement for it, which is what keeps the file portable to any other tool.
enum InlineImageLoader {

    struct Reference {
        /// The full `![alt](path)` range, in UTF-16 units for NSTextView.
        var range: NSRange
        var path: String
        var alt: String
    }

    /// A small cache, because scrolling a long post re-asks for the same files
    /// on every layout pass and decoding a JPEG is not free.
    nonisolated(unsafe) private static var cache: [String: NSImage?] = [:]
    private static let cacheLimit = 120

    /// All image references in a Markdown document, in order.
    static func references(in markdown: String) -> [Reference] {
        var found: [Reference] = []
        let ns = markdown as NSString
        var index = 0

        while index < ns.length {
            let bang = ns.range(of: "![", options: [],
                                range: NSRange(location: index, length: ns.length - index))
            guard bang.location != NSNotFound else { break }

            let altStart = bang.location + 2
            let altEnd = ns.range(of: "]", options: [],
                                  range: NSRange(location: altStart, length: ns.length - altStart))
            guard altEnd.location != NSNotFound else { break }

            // Only an immediately-following "(" makes this an image rather than
            // a link with an exclamation mark in front of it.
            guard altEnd.location + 1 < ns.length, ns.character(at: altEnd.location + 1) == 40 else {
                index = altEnd.location + 1
                continue
            }
            let pathStart = altEnd.location + 2
            let pathEnd = ns.range(of: ")", options: [],
                                   range: NSRange(location: pathStart, length: ns.length - pathStart))
            guard pathEnd.location != NSNotFound else { break }

            let alt = ns.substring(with: NSRange(location: altStart, length: altEnd.location - altStart))
            let rawPath = ns.substring(with: NSRange(location: pathStart, length: pathEnd.location - pathStart))
            // A title after the path — `![a](x.jpg "t")` — is not part of it.
            let path = rawPath.split(separator: " ").first.map(String.init) ?? rawPath

            found.append(Reference(
                range: NSRange(location: bang.location, length: pathEnd.location + 1 - bang.location),
                path: path, alt: alt))
            index = pathEnd.location + 1
        }
        return found
    }

    /// Resolves a Markdown path to a file on disk.
    ///
    /// Page-relative paths (`photo.jpg`) resolve beside the page. Root-relative
    /// ones (`/images/x.jpg`) resolve under `static/`. Anything else — an
    /// absolute URL, a missing file — returns nil, so the caller leaves the
    /// Markdown visible instead of showing a broken picture.
    static func resolve(_ path: String, pageURL: URL, projectRoot: URL) -> URL? {
        if path.isEmpty { return nil }
        // A remote URL is a legitimate thing to link to; it is not ours to load.
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return nil }
        if path.hasPrefix("data:") { return nil }

        let pageDirectory = pageURL.deletingLastPathComponent()

        if path.hasPrefix("/") {
            let relative = String(path.dropFirst())
            let inStatic = projectRoot.appendingPathComponent("static").appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: inStatic.path) { return inStatic }
            let inRoot = projectRoot.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: inRoot.path) { return inRoot }
            return nil
        }

        let beside = pageDirectory.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        // A page inside a bundle may reference a file one level up.
        let parent = pageDirectory.deletingLastPathComponent().appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: parent.path) { return parent }
        return nil
    }

    /// Loads an image, memoising the result.
    static func image(at url: URL) -> NSImage? {
        let key = url.path
        if let cached = cache[key] { return cached }
        let image = NSImage(contentsOf: url)
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = image
        return image
    }

    static func flushCache() { cache.removeAll() }
}

/// Draws one image inline, scaled to the text column and never taller than a
/// reasonable fraction of the writing area.
///
/// An `NSTextAttachmentCell` is used rather than an `NSTextView` because an
/// attachment participates in text layout properly: the line grows to fit it,
/// it flows with surrounding paragraphs, and it survives editing. A subview
/// would have to be repositioned by hand on every layout pass.
///
/// The two hooks that matter are exact, and this SDK's surface is narrower than
/// it first appears: sizing comes from `cellFrame(forTextContainer:…)` and
/// `cellSize()`, painting from `draw(withFrame:inView:characterIndex:)`. Neither
/// `imageBounds(forProposedBounds:…)` nor a `cellFrame` property is overridable
/// here, which is worth knowing before trying them.
final class ImageAttachmentCell: NSTextAttachmentCell {

    static let maximumHeight: CGFloat = 420
    private static let maximumWidth: CGFloat = 620

    /// The exact Markdown this attachment stands for, e.g. `![alt](photo.jpg)`.
    ///
    /// Carrying it here is what lets the document be read back as Markdown with
    /// no offset bookkeeping: the text storage holds one character per image, and
    /// this string replaces it on the way out.
    var markdown: String?
    /// Alt text, used for the tooltip.
    var alt: String?

    /// Width the image may occupy; normally the writing column.
    var targetWidth: CGFloat = 0

    /// The reserved rectangle, computed once when the cell is configured.
    ///
    /// `NSTextAttachment` measures through `NSTextAttachmentLayout`, and its
    /// default implementation returns the cell's own bounds — a square, since
    /// that is the default cell's bounds. Overriding `cellSize()` and
    /// `cellFrame(…)` is not enough, because neither is what that path reads.
    /// `ScaledImageAttachment` below is what actually supplies the size.
    var reserved: NSRect = .zero

    private var image_: NSImage?

    override var image: NSImage? {
        get { image_ }
        set { image_ = newValue }
    }

    /// The rectangle the image occupies within the offered width.
    private func imageRect(availableWidth: CGFloat) -> NSRect {
        guard let picture = image_ else { return .zero }
        let natural = picture.size
        guard natural.width > 0, natural.height > 0 else { return .zero }

        let available = availableWidth > 0 ? availableWidth : Self.maximumWidth
        var width = min(available, natural.width)
        var height = width * (natural.height / natural.width)
        if height > Self.maximumHeight {
            height = Self.maximumHeight
            width = height * (natural.width / natural.height)
        }
        // A small negative y keeps the picture off the line above it.
        return NSRect(x: 0, y: -4, width: width, height: height)
    }

    /// Sizing hook. Returning the image's rectangle is what makes the enclosing
    /// line grow to fit the picture.
    override func cellFrame(for container: NSTextContainer,
                            proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint,
                            characterIndex: Int) -> NSRect {
        imageRect(availableWidth: lineFrag.width)
    }

    /// `NSTextAttachment.attachmentBounds(forTextContainer:...)` is what the
    /// layout manager actually measures, and its default implementation returns
    /// `cell.bounds` — a square, because that is the default cell. Overriding
    /// only `cellSize()` and `cellFrame(...)` is not enough: the attachment
    /// reports the cell's own bounds, so the reserved space comes out square and
    /// the picture is drawn stretched into it.
    override func cellSize() -> NSSize {
        let rect = imageRect(availableWidth: targetWidth)
        return NSSize(width: rect.width, height: rect.height)
    }

    override func draw(withFrame cellFrame: NSRect, in view: NSView?,
                       characterIndex: Int) {
        guard let picture = image_ else { return }
        // The frame offered here is the reserved space, not a width to scale
        // into: scaling by its width would letterbox a wide image into a tall
        // slot. Fit inside it instead, preserving the picture's own proportions.
        let rect = fitted(in: cellFrame)
        guard rect.width > 0, rect.height > 0 else { return }
        picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// Scales the picture to fit inside `box`, keeping its proportions and
    /// centring it.
    private func fitted(in box: NSRect) -> NSRect {
        guard let picture = image_ else { return .zero }
        let natural = picture.size
        guard natural.width > 0, natural.height > 0, box.width > 0, box.height > 0 else { return .zero }

        let scale = min(box.width / natural.width, box.height / natural.height)
        let width = natural.width * scale
        let height = natural.height * scale
        return NSRect(x: box.midX - width / 2,
                      y: box.midY - height / 2,
                      width: width, height: height)
    }

    /// What a caller should show for this image, for a caption or a tooltip.
    var displayLabel: String {
        if let alt, !alt.isEmpty { return alt }
        if let name = image_?.name(), !name.isEmpty { return name }
        return "Image"
    }
}

/// The attachment that carries an inline image.
///
/// `NSTextAttachment` asks its `NSTextAttachmentLayout` methods how much space to
/// reserve, and the default answer comes from the cell's own bounds — a square.
/// That is why a 900x500 picture was being laid out in a square slot and drawn
/// stretched to fill it. Supplying the size here is what makes the reserved
/// rectangle match the picture's own proportions.
final class ScaledImageAttachment: NSTextAttachment {

    /// How wide the picture may be, normally the writing column.
    var contentWidth: CGFloat = 620

    /// The height the image should occupy, given its own proportions.
    private var fittedHeight: CGFloat = 0

    func fit(to width: CGFloat, natural: NSSize) {
        contentWidth = width
        guard natural.width > 0, natural.height > 0 else { return }
        let scale = min(width / natural.width, ImageAttachmentCell.maximumHeight / natural.height)
        fittedHeight = natural.height * scale
        // `bounds` is what the default layout path reads.
        bounds = NSRect(x: 0, y: 0, width: natural.width * scale, height: fittedHeight)
    }

    override func attachmentBounds(for container: NSTextContainer?,
                                   proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint,
                                   characterIndex: Int) -> NSRect {
        let width = min(contentWidth > 0 ? contentWidth : lineFrag.width, lineFrag.width)
        return NSRect(x: 0, y: -4, width: width, height: fittedHeight)
    }

    // No `image(for:…)` override: the cell's `draw(withFrame:…)` paints the
    // picture, and the attachment's own image lookup would only duplicate it.
}
