// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import AppKit

/// Per-page JavaScript, written in a small editor and saved into the page's own
/// folder so Hugo serves it.
///
/// How it works: the code goes into `custom.js` beside the page, and the page
/// gains one line of Markdown calling a shortcode. That is the mechanism Hugo
/// itself offers for injecting raw HTML, so nothing here depends on a theme
/// cooperating — a theme that does not know about the shortcode still gets the
/// script, because the shortcode is ours and lives in the site.
///
/// The alternative — writing to `layouts/` and hoping a theme inherits it — is
/// exactly the kind of thing that silently does nothing.
struct CustomScriptSheet: View {
    @EnvironmentObject private var engine: SiteEngine
    @Environment(\.dismiss) private var dismiss

    let itemID: String
    var onSaved: (Bool) -> Void

    @State private var code = ""
    @State private var includeOnThisPage = true
    @State private var statusText: String?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 440)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "curlybraces")
                .foregroundStyle(Design.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Custom JavaScript")
                    .font(.system(size: 13, weight: .semibold))
                Text("Runs on this page only, after the page loads.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Include on this page", isOn: $includeOnThisPage)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $code)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: code) { _, _ in statusText = nil }

            if let statusText {
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Saved to \(PageScript.fileName) beside this page.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Load and save

    private func load() {
        guard !loaded, let item = engine.item(withID: itemID) else { return }
        loaded = true
        let directory = MediaLibrary.placement(
            for: item, projectRoot: engine.root ?? item.url.deletingLastPathComponent(),
            kind: .inline).directory
        let file = directory.appendingPathComponent(PageScript.fileName)
        if let existing = try? String(contentsOf: file, encoding: .utf8) {
            code = existing
        }
        includeOnThisPage = PageScript.hasScriptMarker(in: item.frontMatter.body)
    }

    private func save() {
        guard let root = engine.root, var item = engine.item(withID: itemID) else { return }

        // A site created before this feature exists has no shortcode, and the
        // marker would then render as literal text on the published page. Writing
        // the script would look like it worked and fail only at the site, so the
        // shortcode is installed here rather than assumed.
        if !SiteShortcodes.isInstalled(in: root) {
            _ = SiteShortcodes.install(in: root)
        }

        let placement = MediaLibrary.placement(for: item, projectRoot: root, kind: .inline)
        let directory = placement.directory
        let file = directory.appendingPathComponent(PageScript.fileName)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            } else {
                try (trimmed + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            statusText = "Could not save: \(error.localizedDescription)"
            return
        }

        // Add or remove the shortcode line in the page body.
        item.frontMatter.body = PageScript.applyingMarker(includeOnThisPage, to: item.frontMatter.body)
        engine.save(item)
        engine.scanContent()
        statusText = "Saved"
        InlineImageLoader.flushCache()
        onSaved(true)
        dismiss()
    }
}
