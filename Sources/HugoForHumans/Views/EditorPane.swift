// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import AppKit

/// Writing surface: front-matter fields on the right, Markdown on the left,
/// with autosave so there is never a "save" anxiety.
struct EditorPane: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var builder: Builder
    var item: ContentItem
    @Binding var showInspector: Bool

    @State private var draft: ContentItem?
    @State private var bodyText: String = ""
    @State private var title: String = ""
    @State private var tagsText: String = ""
    @State private var summary: String = ""
    @State private var slug: String = ""
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showRawFrontMatter = false
    @State private var rawText: String = ""
    @State private var focusToken = 0
    /// Bumped to ask the text view to redraw its inline images.
    @State private var renderToken = 0
    /// Media attached to this page, refreshed after any add or remove.
    @State private var inlineMedia: [MediaAsset] = []
    @State private var attachments: [MediaAsset] = []
    @State private var showEmbedPrompt = false
    @State private var embedURL = ""
    @State private var showScriptSheet = false
    @State private var statusMessage: String?
    @State private var openMenu: PickerKind?

    /// The extra dropdowns in the toolbar.
    enum PickerKind: String, Identifiable {
        case embed, media
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            HStack(spacing: 0) {
                writingArea
                if showInspector {
                    Divider()
                    InspectorPane(
                        title: $title,
                        tagsText: $tagsText,
                        summary: $summary,
                        slug: $slug,
                        isDirty: isDirty,
                        inlineMedia: inlineMedia,
                        attachments: attachments,
                        statusMessage: statusMessage,
                        onCommit: commit,
                        onAttach: { attachFile(asAttachment: true) },
                        onInsertImage: { insertImage() },
                        onRemoveMedia: { removeMedia($0) },
                        onEditScript: { showScriptSheet = true }
                    )
                    .frame(width: Design.Metrics.inspectorWidth)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: item.id) { _, _ in
            flushPendingSave()
            load()
            refreshMedia()
        }
        .onChange(of: bodyText) { _, _ in refreshMedia() }
        .alert("Embed", isPresented: $showEmbedPrompt) {
            TextField("Paste the URL", text: $embedURL)
            Button("Insert") { insertEmbed(from: embedURL) }
            Button("Cancel", role: .cancel) { embedURL = "" }
        } message: {
            Text("Paste a YouTube, Vimeo, X, Instagram or Facebook link and the right markup is written for you.")
        }
        .sheet(isPresented: $showScriptSheet) {
            CustomScriptSheet(itemID: item.id) { saved in
                statusMessage = saved ? "Custom script saved" : nil
                load()
            }
            .frame(width: 560, height: 520)
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .onChange(of: title) { _, _ in markDirty() }
                HStack(spacing: 5) {
                    Text(item.projectRelativePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(wordCount) words · \(readingTime) min read")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isDirty {
                HStack(spacing: 5) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Unsaved")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showRawFrontMatter.toggle()
            } label: {
                Image(systemName: showRawFrontMatter ? "list.bullet.indent" : "curlybraces")
            }
            .buttonStyle(.borderless)
            .help("Edit front matter as text")

            Button {
                commit()
            } label: {
                Text("Save").frame(width: 42)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isDirty)

            Menu {
                Button(item.isDraft ? "Publish Now" : "Move to Drafts") {
                    engine.toggleDraft(item)
                    load()
                }
                Divider()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bodyText, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Writing area

    private var writingArea: some View {
        VStack(spacing: 0) {
            if showRawFrontMatter {
                frontMatterEditor
            } else {
                formatBar
                MarkdownEditor(text: $bodyText,
                               onChange: { markDirty() },
                               focusRequest: focusToken,
                               rendersImages: true,
                               pageURL: item.url,
                               projectRoot: engine.root ?? item.url.deletingLastPathComponent(),
                               renderRequest: renderToken,
                               acceptsImagePaste: true,
                               onImagePaste: pasteImage)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            formatButton("bold", tip: "Bold  ⌘B") { edit { $0.wrapSelection("**", "**", placeholder: "bold text") } }
            formatButton("italic", tip: "Italic  ⌘I") { edit { $0.wrapSelection("*", "*", placeholder: "italic text") } }
            Divider().frame(height: 14).padding(.horizontal, 4)
            formatButton("textformat.size.larger", tip: "Heading") { edit { $0.toggleLinePrefix("## ") } }
            formatButton("list.bullet", tip: "Bullet list") { edit { $0.toggleLinePrefix("- ") } }
            formatButton("list.number", tip: "Numbered list") { edit { $0.toggleLinePrefix("1. ") } }
            Divider().frame(height: 14).padding(.horizontal, 4)
            formatButton("link", tip: "Link  ⌘K") { edit { $0.wrapSelection("[", "](https://)", placeholder: "link text") } }
            formatButton("quote.opening", tip: "Quote") { edit { $0.toggleLinePrefix("> ") } }
            formatButton("chevron.left.forwardslash.chevron.right", tip: "Code block") { edit { $0.wrapSelection("```\n", "\n```", placeholder: "code") } }
            Divider().frame(height: 14).padding(.horizontal, 4)
            formatButton("tablecells", tip: "Table") { edit { $0.insertBlock(Self.tableTemplate) } }
            formatButton("minus", tip: "Divider") { edit { $0.insertBlock("---") } }
            Divider().frame(height: 14).padding(.horizontal, 4)

            // Real image insertion: the file is copied into the site and the
            // Markdown is written for us, rather than asking the writer to know
            // a path.
            formatButton("photo", tip: "Insert image…") { insertImage() }

            // ⌘V already does this, but a screenshot is the one thing a writer
            // will never think to look for a button for.
            formatButton("doc.on.clipboard", tip: "Paste an image from the clipboard") {
                pasteFromClipboard()
            }

            Menu {
                Button("YouTube or Vimeo video…") { showEmbedPrompt = true }
                Button("X / Twitter post…") { showEmbedPrompt = true }
                Button("Instagram post…") { showEmbedPrompt = true }
                Button("Facebook post…") { showEmbedPrompt = true }
                Divider()
                Button("Paste a link directly") { edit { $0.wrapSelection("[", "](https://)", placeholder: "link text") } }
            } label: {
                Image(systemName: "play.rectangle").font(.system(size: 11.5))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 22)
            .fixedSize()
            .help("Embed a video or a social post by pasting its URL")

            Menu {
                Button("Attach a file…") { attachFile(asAttachment: true) }
                Button("Insert an image…") { insertImage() }
                Divider()
                Button("Refresh") { refreshMedia() }
            } label: {
                Image(systemName: "paperclip").font(.system(size: 11.5))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 22)
            .fixedSize()
            .help("Attach a file, or insert an image")

            Spacer()
            // Moves keyboard focus into the writing area, so the user can start
            // typing without clicking. Labelled as an action, not as content.
            Button {
                focusToken += 1
            } label: {
                Label("Start writing", systemImage: "text.cursor")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .help("Move the cursor into the page and start typing")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func formatButton(_ symbol: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5))
        }
        .buttonStyle(.borderless)
        .frame(width: 26, height: 22)
        .help(tip)
    }

    private var frontMatterEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Front matter — the fields Hugo reads")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
            TextEditor(text: $rawText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: rawText) { _, _ in markDirty() }
        }
    }

    // MARK: - State

    private var wordCount: Int {
        bodyText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    private var readingTime: Int {
        max(1, Int((Double(wordCount) / 220.0).rounded()))
    }

    private func load() {
        guard let current = engine.item(withID: item.id) else { return }
        draft = current
        title = current.frontMatter.title
        bodyText = current.frontMatter.body
        tagsText = current.frontMatter.tags.joined(separator: ", ")
        summary = current.frontMatter.summary
        slug = current.frontMatter["slug"]?.stringValue ?? ""
        rawText = current.frontMatter.serialized()
        isDirty = false
    }

    private func markDirty() {
        isDirty = true
        scheduleAutosave()
    }

    /// Autosave after a short pause, so a crash never costs more than a sentence.
    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { commit() }
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        if isDirty { commit() }
    }

    private func commit() {
        saveTask?.cancel()
        guard var updated = engine.item(withID: item.id) else { return }

        if showRawFrontMatter {
            // Re-parse whatever the user typed in the raw front-matter view.
            let combined = rawText
            let parsed = FrontMatter.parse(combined)
            updated.frontMatter = FrontMatter(
                format: parsed.format,
                values: parsed.values,
                body: bodyText.isEmpty ? parsed.body : bodyText
            )
            title = updated.frontMatter.title
        } else {
            updated.frontMatter["title"] = .string(title)
            updated.frontMatter["description"] = .string(summary)
            let tags = tagsText.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            if tags.isEmpty {
                updated.frontMatter["tags"] = nil
            } else {
                updated.frontMatter["tags"] = .list(tags)
            }
            if !slug.isEmpty {
                updated.frontMatter["slug"] = .string(slug)
            }
            updated.frontMatter.body = bodyText
        }

        engine.save(updated)
        isDirty = false
        if let reloaded = engine.item(withID: item.id) {
            draft = reloaded
            rawText = reloaded.frontMatter.serialized()
        }
    }

    // MARK: - Media and embeds

    /// Picks an image, copies it into the site, and writes the Markdown.
    ///
    /// The file lands beside the page (or in `static/` when the page is not a
    /// bundle), and the page itself is never rewritten: it gains one line of
    /// ordinary Markdown that any Hugo site, and any other tool, understands.
    private func insertImage() {
        let panel = NSOpenPanel()
        panel.title = "Insert an image"
        panel.message = "Choose an image. It is copied into your site and referenced by Markdown."
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        guard let root = engine.root, let current = engine.item(withID: item.id) else { return }
        var inserted: [String] = []
        // Adding the first image promotes the page to a leaf bundle, which moves
        // its file — so `current` is re-read each pass and the editor follows it.
        var page = current
        for url in panel.urls {
            do {
                let placed = try MediaLibrary.add(url, to: page, projectRoot: root, kind: .inline)
                page = page.relocated(to: placed.pageURL,
                                      contentRoot: root.appendingPathComponent("content"))
                // Alt text defaults to a cleaned-up filename, which is far more
                // useful for accessibility and for search than an empty string.
                let alt = Self.altText(from: placed.asset.name)
                inserted.append("![\(alt)](\(placed.markdownPath))")
            } catch {
                statusMessage = "Could not add \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        guard !inserted.isEmpty else { return }
        if page.url != current.url {
            // The page moved into a bundle, so the sidebar and everything keyed
            // on the old id have to be rebuilt against the new path.
            engine.scanContent()
        }
        // One blank line between images so they do not run together.
        edit { $0.insertBlock(inserted.joined(separator: "\n\n")) }
        markDirty()
        refreshMedia()
        renderToken += 1
        statusMessage = inserted.count == 1
            ? "Image added"
            : "\(inserted.count) images added"
    }

    /// Inserts whatever image is on the clipboard, for the toolbar button.
    ///
    /// Separate from the ⌘V path so the status message can explain a failure,
    /// which a paste cannot.
    private func pasteFromClipboard() {
        guard let pasted = ClipboardImage.first() else {
            statusMessage = "There is no image on the clipboard"
            return
        }
        guard let markdown = pasteImage(pasted) else {
            statusMessage = "That is not an image — copy the picture itself, not a link"
            return
        }
        edit { $0.insertBlock(markdown) }
        markDirty()
    }

    /// Saves a pasted screenshot beside the page and returns its Markdown.
    ///
    /// Returns nil when the paste was not an image, so the caller can fall
    /// through to normal text pasting.
    private func pasteImage(_ pasted: ClipboardImage.Pasted) -> String? {
        guard let root = engine.root, let current = engine.item(withID: item.id) else { return nil }
        do {
            let placed = try MediaLibrary.add(pasted, to: current, projectRoot: root, kind: .inline)
            let alt = Self.altText(from: placed.asset.name)
            engine.scanContent()
            refreshMedia()
            renderToken += 1
            statusMessage = "Pasted \(placed.asset.name)"
            return "![\(alt)](\(placed.markdownPath))"
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    /// Attaches any file. Attachments are not renderable in the page text, so
    /// they are listed in the inspector instead of being inserted inline.
    private func attachFile(asAttachment: Bool) {
        let panel = NSOpenPanel()
        panel.title = "Attach a file"
        panel.message = "Choose a file to make available with this page."
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        guard let root = engine.root, let current = engine.item(withID: item.id) else { return }
        for url in panel.urls {
            do {
                let placed = try MediaLibrary.add(url, to: current, projectRoot: root, kind: .attachment)
                statusMessage = "Attached \(placed.asset.name)"
            } catch {
                statusMessage = "Could not attach \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        engine.scanContent()
        refreshMedia()
    }

    /// Turns a pasted URL into the right markup, or a plain link if it is not
    /// something we recognise. Never silently discards the URL.
    private func insertEmbed(from raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        embedURL = ""
        guard !trimmed.isEmpty else { return }
        let embed = EmbedParser.parse(trimmed)
        edit { $0.insertBlock(embed.markdown) }
        markDirty()
        statusMessage = "Inserted \(embed.summary)"
    }

    /// Reloads the inline/attachment split for this page.
    private func refreshMedia() {
        guard let root = engine.root, let current = engine.item(withID: item.id) else {
            inlineMedia = []
            attachments = []
            return
        }
        let assets = MediaLibrary.assets(for: current, projectRoot: root)
        inlineMedia = assets.inline
        attachments = assets.attachments
    }

    /// Removes a file and, if the page referred to it, the reference too.
    ///
    /// Deleting a picture but leaving `![alt](photo.jpg)` behind would render a
    /// broken image on the published page, so both go together.
    private func removeMedia(_ asset: MediaAsset) {
        guard let root = engine.root, let current = engine.item(withID: item.id) else { return }
        let reference = MediaLibrary.reference(for: asset, page: current, projectRoot: root)

        if let cleaned = MediaMarkdown.removingImageReference(reference, from: bodyText) {
            bodyText = cleaned
        }

        do {
            try MediaLibrary.remove(asset)
            statusMessage = "Removed \(asset.name)"
        } catch {
            statusMessage = "Could not remove \(asset.name): \(error.localizedDescription)"
        }
        engine.scanContent()
        refreshMedia()
        markDirty()
        renderToken += 1
    }

    /// `holiday-photo-2.jpg` becomes "Holiday photo 2" — a starting alt text.
    static func altText(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        let words = stem.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: - Markdown helpers

    /// The formatting toolbar needs the live NSTextView to act on a selection,
    /// which SwiftUI's `TextEditor` cannot expose. The editor registers itself
    /// here on creation and the toolbar drives it directly.
    static weak var activeTextView: NSTextView?

    private func edit(_ action: (NSTextView) -> Void) {
        guard let view = Self.activeTextView else { return }
        // Make sure the view is first responder so the selection is current.
        view.window?.makeFirstResponder(view)
        action(view)
    }

    private static let tableTemplate = """

    | Column | Column |
    |--------|--------|
    | Value  | Value  |
    """
}

/// The right-hand column: the fields a writer actually thinks about.
struct InspectorPane: View {
    @EnvironmentObject private var engine: SiteEngine
    @Binding var title: String
    @Binding var tagsText: String
    @Binding var summary: String
    @Binding var slug: String
    var isDirty: Bool
    var inlineMedia: [MediaAsset] = []
    var attachments: [MediaAsset] = []
    var statusMessage: String? = nil
    var onCommit: () -> Void
    var onAttach: () -> Void = {}
    var onInsertImage: () -> Void = {}
    var onRemoveMedia: (MediaAsset) -> Void = { _ in }
    var onEditScript: () -> Void = {}

    /// The order of the inspector's sections. Asserted by a test, because a
    /// requirement like "attachments is the fourth item" is otherwise invisible.
    static let sectionOrder = InspectorLayout.sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                field("Title") {
                    TextField("Untitled", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(onCommit)
                }

                field("Summary") {
                    TextField("One sentence for search engines", text: $summary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .onSubmit(onCommit)
                }

                field("Tags") {
                    TextField("comma, separated", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(onCommit)
                    Text("Tags build the tag archive page automatically.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Files that travel with the page but are not part of its text.
                // Fourth in the inspector, because it is a per-page list like the
                // ones above it — Address is a URL, not a list.
                field("Attachments") {
                    VStack(alignment: .leading, spacing: 6) {
                        if attachments.isEmpty {
                            Text("No files attached yet.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(attachments) { asset in
                                attachmentRow(asset)
                            }
                        }
                        HStack(spacing: 6) {
                            Button {
                                onAttach()
                            } label: {
                                Label("Attach a file", systemImage: "paperclip")
                                    .font(.system(size: 10.5))
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                    }
                }

                field("Address") {
                    HStack(spacing: 6) {
                        Text("/").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        TextField("auto", text: $slug)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .onSubmit(onCommit)
                    }
                    Text("Leave blank to use the page title.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if !inlineMedia.isEmpty {
                    field("Images in this page") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(inlineMedia) { asset in
                                attachmentRow(asset)
                            }
                        }
                    }
                }

                field("Custom script") {
                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            onEditScript()
                        } label: {
                            Label("Add JavaScript for this page", systemImage: "curlybraces")
                                .font(.system(size: 10.5))
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        Text("Runs on the published page only. Useful for embeds and analytics that need a script tag.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .background(.bar)
    }

    /// One attached file, with its size and a way to remove it.
    private func attachmentRow(_ asset: MediaAsset) -> some View {
        HStack(spacing: 7) {
            Image(systemName: asset.isImage ? "photo" : "doc")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(asset.name)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(asset.pixelDescription ?? asset.sizeDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
            } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            Button {
                onRemoveMedia(asset)
            } label: {
                Image(systemName: "trash").font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .help("Remove this file")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
