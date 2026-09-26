// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import AppKit

/// A Markdown text editor backed by NSTextView.
///
/// SwiftUI's `TextEditor` exposes no selection, so a formatting toolbar built on
/// it can only ever append text. NSTextView gives the real selected range, which
/// is what makes bold/italic/link behave the way a writing app should.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    /// Called on every keystroke so the parent can mark the document dirty.
    var onChange: (() -> Void)?
    /// Focus request, raised when the parent wants the caret in the document.
    var focusRequest: Int
    /// Enables inline image rendering and says where to resolve image paths.
    var rendersImages: Bool = false
    var pageURL: URL = URL(fileURLWithPath: "/")
    var projectRoot: URL = URL(fileURLWithPath: "/")
    /// Bumped by the parent to ask for a re-render, e.g. after inserting a file.
    var renderRequest: Int = 0
    /// Whether ⌘V should try to turn a pasted image into a file.
    var acceptsImagePaste: Bool = false
    /// Called with the Markdown to insert for a pasted image. Returning false
    /// means the paste was not an image and should go through unchanged.
    var onImagePaste: ((ClipboardImage.Pasted) -> String?)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = rendersImages ? ImageRenderingTextView() : MarkdownTextView()
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor]
        if let rendering = textView as? ImageRenderingTextView {
            rendering.pageURL = pageURL
            rendering.projectRoot = projectRoot
            rendering.isAutomaticLinkDetectionEnabled = false
            // The first paint has to render too, or a page opened straight from
            // the sidebar shows its Markdown until something forces an update.
            rendering.renderImages()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.rendersImages = rendersImages
        context.coordinator.parent = self
        // Let the enclosing EditorPane's toolbar reach this view so formatting
        // commands can act on the real selection.
        EditorPane.activeTextView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // With images rendering, the AppKit string contains attachment
        // placeholders, so it can never be compared against the Markdown
        // binding. Compare against the Markdown the view reports instead.
        let currentMarkdown = (textView as? ImageRenderingTextView)?.markdown ?? textView.string
        if currentMarkdown != text {
            let previous = textView.selectedRange()
            textView.string = text
            if let rendering = textView as? ImageRenderingTextView {
                rendering.pageURL = pageURL
                rendering.projectRoot = projectRoot
                rendering.renderImages()
            }
            // Keep the caret roughly where it was, clamped to the new length.
            let limit = text.utf16.count
            textView.setSelectedRange(NSRange(location: min(previous.location, limit), length: 0))
        }
        if let rendering = textView as? ImageRenderingTextView {
            rendering.pageURL = pageURL
            rendering.projectRoot = projectRoot
            if context.coordinator.lastRenderRequest != renderRequest {
                context.coordinator.lastRenderRequest = renderRequest
                rendering.scheduleRender()
            }
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        var lastFocusRequest = 0
        var lastRenderRequest = 0
        var rendersImages = false
        /// Guards against echoing our own programmatic edits back as user input.
        var isApplyingExternalText = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView else { return }
            // Read Markdown, not the decorated string: with images rendering,
            // `string` contains one placeholder character per image.
            let newValue = (textView as? ImageRenderingTextView)?.markdown ?? textView.string
            if parent.text != newValue {
                parent.text = newValue
            }
            parent.onChange?()
            // Re-decorate after the edit settles, so the caret is not fighting
            // the renderer while the user types.
            (textView as? ImageRenderingTextView)?.scheduleRender()
        }

        /// A screenshot pasted into the editor becomes a file beside the page,
        /// inserted as an ordinary Markdown image.
        ///
        /// `NSTextView` otherwise pastes the raw bytes into the document, which
        /// for a screenshot means tens of thousands of meaningless characters in
        /// the post. Plain text pastes are left alone: pasting a URL must still
        /// paste a URL.
        func textView(_ view: NSTextView, paste sender: Any) {
            guard parent.acceptsImagePaste, let handler = parent.onImagePaste else {
                view.perform(NSSelectorFromString("paste:"), with: sender)
                return
            }
            if let pasted = ClipboardImage.first(), let markdown = handler(pasted) {
                let insertion = NSRange(location: view.selectedRange().location, length: 0)
                view.insertText(markdown, replacementRange: insertion)
                view.didChangeText()
            } else {
                view.perform(NSSelectorFromString("paste:"), with: sender)
            }
        }
    }
}

/// The editor view itself, with a couple of Markdown-friendly keybindings.
class MarkdownTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        // Tab should indent, not move focus. Writers expect the former.
        if event.keyCode == 48,
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.command) {
            insertPlain("\t")
            return
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        insertPlain("\t")
    }

    /// NSTextView's `insertText` is deprecated for programmatic edits; going
    /// through the text storage keeps undo working and avoids input-system state.
    private func insertPlain(_ text: String) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        storage.replaceCharacters(in: range, with: text)
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        didChangeText()
    }
}

// MARK: - Programmatic editing

extension NSTextView {
    /// Wraps the current selection (or inserts `placeholder`) in `prefix`/`suffix`.
    func wrapSelection(_ prefix: String, _ suffix: String, placeholder: String) {
        let range = selectedRange()
        let ns = string as NSString
        let selected = range.length > 0 ? ns.substring(with: range) : placeholder
        replace(range, with: prefix + selected + suffix)
        // Reselect just the text the user was working on.
        setSelectedRange(NSRange(location: range.location + prefix.utf16.count,
                                 length: selected.utf16.count))
    }

    /// Prefixes every line touched by the selection, or toggles the prefix off.
    func toggleLinePrefix(_ prefix: String) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        let lines = ns.substring(with: lineRange).components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(prefix) }
        let transformed = lines.map { line -> String in
            if line.isEmpty { return line }
            return allPrefixed ? String(line.dropFirst(prefix.count)) : prefix + line
        }.joined(separator: "\n")
        replace(lineRange, with: transformed)
        setSelectedRange(NSRange(location: lineRange.location, length: transformed.utf16.count))
    }

    func insertBlock(_ block: String) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        // Blocks need their own line, so add a leading newline when not at the top.
        let insertion = (lineRange.location > 0 ? "\n" : "") + block
        replace(lineRange, with: insertion)
        setSelectedRange(NSRange(location: lineRange.location + insertion.utf16.count, length: 0))
    }

    /// Replaces a range and tells the delegate, so the SwiftUI binding updates.
    private func replace(_ range: NSRange, with text: String) {
        let mutable = NSMutableString(string: string)
        mutable.replaceCharacters(in: range, with: text)
        string = mutable as String
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}
