// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import AppKit

/// A Markdown editor that also *shows* the images it describes.
///
/// The document is still Markdown — that is what gets saved, and what any other
/// tool would read. But `![alt](photo.jpg)` is drawn as the picture itself,
/// with the image's Markdown held on the attachment rather than in the text.
///
/// That is the whole trick, and it is what keeps this robust: an image occupies
/// exactly one character position in the text storage, and the original
/// Markdown travels inside the `NSTextAttachmentCell`. Reading the document back
/// means substituting each attachment for the Markdown it stands for. There is
/// no offset arithmetic to keep in step, and no second copy of the text to fall
/// out of sync — the same approach a word processor uses for a picture.
final class ImageRenderingTextView: MarkdownTextView {

    /// Where images are resolved from.
    var pageURL: URL = URL(fileURLWithPath: "/")
    var projectRoot: URL = URL(fileURLWithPath: "/")
    /// How wide an image may be, normally the width of the writing column.
    var contentWidth: CGFloat = 620

    private var rendering = false

    /// The document as Markdown, with every rendered image put back.
    var markdown: String {
        guard let storage = textStorage else { return string }
        let ns = storage.string as NSString
        var out = ""
        var index = 0
        while index < ns.length {
            if ns.character(at: index) == 0xFFFC,
               let cell = attachmentCell(at: index),
               let source = cell.markdown {
                out += source
            } else {
                out += ns.substring(with: NSRange(location: index, length: 1))
            }
            index += 1
        }
        return out
    }

    /// The Markdown an attachment at `index` stands for, if there is one there.
    ///
    /// `NSTextAttachment` on this SDK has no `cell` property, so the Markdown is
    /// carried as a custom attributed-string attribute set alongside the
    /// attachment. Nothing is retained globally, so there is no leak and no
    /// bookkeeping to keep in step with the text.
    private func attachmentCell(at index: Int) -> ImageAttachmentCell? {
        guard let storage = textStorage, index < storage.length else { return nil }
        var effective = NSRange()
        storage.attribute(.attachment, at: index, effectiveRange: &effective)
        let cell = storage.attribute(Self.markdownAttribute, at: index, effectiveRange: &effective)
        return cell as? ImageAttachmentCell
    }

    /// The attribute the image's Markdown rides on, next to the attachment.
    static let markdownAttribute = NSAttributedString.Key("hfh.imageMarkdown")

    /// Rebuilds the display from the Markdown, rendering images in place.
    func renderImages() {
        guard !rendering else { return }
        guard let storage = textStorage else { return }

        rendering = true
        defer { rendering = false }

        let source = markdown
        let refs = InlineImageLoader.references(in: source)
        guard !refs.isEmpty else {
            // Nothing to draw: if a previous render left attachments behind,
            // put the plain Markdown back so the text is not left decorated.
            if string != source, !source.isEmpty {
                preserveSelection { storage.setAttributedString(baseString(source)) }
            }
            return
        }

        let ns = source as NSString
        let full = NSMutableAttributedString()
        var last = 0
        // Maps a Markdown offset to the corresponding display offset, so the
        // caret does not jump to the end of the document on every render.
        var caretMap: [(markdown: Int, display: Int)] = []

        for ref in refs {
            let before = NSRange(location: last, length: ref.range.location - last)
            if before.length > 0 {
                caretMap.append((markdown: before.location, display: full.length))
                full.append(NSMutableAttributedString(string: ns.substring(with: before),
                                                      attributes: baseAttributes()))
            }

            let markdown = ns.substring(with: ref.range)
            let url = InlineImageLoader.resolve(ref.path, pageURL: pageURL, projectRoot: projectRoot)
            if let url, let image = InlineImageLoader.image(at: url) {
                let cell = ImageAttachmentCell()
                cell.image = image
                cell.targetWidth = contentWidth
                cell.markdown = markdown
                cell.alt = ref.alt
                // One character carries both the attachment (which draws the
                // picture) and our attribute (which remembers the Markdown).
                // The text storage can therefore hand the document back as
                // Markdown without any global table of our own.
                // A fresh NSTextAttachment has no cell, so the layout manager has
                // nothing to measure and the image reserves a single line's worth
                // of space — it renders as nothing. The cell has to be attached
                // before the string is built, not after.
                //
                // The attachment is a subclass because the default one reserves
                // space from the cell's square bounds, which stretches a wide
                // picture into a tall slot.
                let attachment = ScaledImageAttachment()
                attachment.attachmentCell = cell
                attachment.fit(to: contentWidth, natural: image.size)
                let slot = NSMutableAttributedString(attachment: attachment)
                slot.addAttribute(Self.markdownAttribute, value: cell, range: NSRange(location: 0, length: 1))
                full.append(slot)
            } else {
                // Unresolvable: keep the Markdown visible rather than hiding it.
                full.append(NSMutableAttributedString(string: markdown, attributes: baseAttributes()))
            }
            last = NSMaxRange(ref.range)
        }
        if last < ns.length {
            caretMap.append((markdown: last, display: full.length))
            full.append(NSMutableAttributedString(string: ns.substring(from: last),
                                                  attributes: baseAttributes()))
        }

        let previous = selectedRange().location
        preserveSelection {
            storage.setAttributedString(full)
            setSelectedRange(NSRange(location: Self.mapCaret(previous, using: caretMap,
                                                               limit: full.length), length: 0))
        }
    }

    /// Maps a caret position in display space using the recorded anchors,
    /// which are in ascending order for both spaces.
    private static func mapCaret(_ displayOffset: Int, using anchors: [(markdown: Int, display: Int)],
                                 limit: Int) -> Int {
        guard !anchors.isEmpty else { return min(displayOffset, limit) }
        // Find the anchors bracketing the caret and interpolate linearly, so the
        // caret stays on the same sentence instead of drifting to the end.
        for pair in zip(anchors, anchors.dropFirst()) {
            let a = pair.0, b = pair.1
            if displayOffset >= a.display && displayOffset <= b.display {
                let span = b.display - a.display
                guard span > 0 else { return a.display }
                let fraction = Double(displayOffset - a.display) / Double(span)
                return min(a.markdown + Int((Double(b.markdown - a.markdown) * fraction).rounded()), limit)
            }
        }
        return min(anchors.last?.display ?? displayOffset, limit)
    }

    private func baseString(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: baseAttributes())
    }

    /// Runs `work` with the selection captured and restored.
    private func preserveSelection(_ work: () -> Void) {
        let previous = selectedRange()
        work()
        let limit = textStorage?.length ?? 0
        setSelectedRange(NSRange(location: min(previous.location, limit), length: 0))
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textColor ?? .labelColor,
        ]
    }

    /// Re-renders after the document settles, rather than on every keystroke —
    /// re-decorating mid-typing makes the caret jump.
    func scheduleRender() {
        guard !rendering else { return }
        rendering = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rendering = false
            self.renderImages()
        }
    }

    /// Called when the user edits, so the parent can pull Markdown back out.
    override func didChangeText() {
        super.didChangeText()
    }
}
