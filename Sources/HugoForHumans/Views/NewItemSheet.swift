// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// The "New Page / New Section" sheet — the WordPress core gesture.
struct NewItemSheetController: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer
    @Environment(\.dismiss) private var dismiss

    let sheet: MainWorkspace.NewItemSheet
    @State private var title = ""
    @State private var section = ""
    @State private var isCreating = false
    @FocusState private var nameFocused: Bool

    private var isSection: Bool { sheet == .section }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 18) {
                field("Name") {
                    TextField(isSection ? "Projects" : "My new page", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { create() }
                }

                if isSection {
                    field("Folder", help: "A section is a folder of pages. The address becomes /\(slug)/.") {
                        Text("/" + (slug.isEmpty ? "name" : slug) + "/")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    field("Section", help: "Where this page lives.") {
                        Picker("", selection: $section) {
                            Text("Top level (no section)").tag("")
                            ForEach(engine.sections, id: \.name) { s in
                                Text(s.displayName).tag(s.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                    }
                    field("Address", help: "This becomes the page's web address.") {
                        Text("/" + (section.isEmpty ? "" : section + "/") + (slug.isEmpty ? "name" : slug) + "/")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if isSection {
                    Toggle("Create the first page inside it", isOn: .constant(false))
                        .disabled(true)
                        .opacity(0.5)
                        .help("You can add pages right after the section is created.")
                }
            }
            .padding(Design.Metrics.padding)

            Divider()

            HStack {
                if let error = engine.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSection ? "Create Section" : "Create Page") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(.horizontal, Design.Metrics.padding)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .onAppear { nameFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isSection ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(Design.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(isSection ? "New Section" : "New Page")
                    .font(.system(size: 16, weight: .semibold))
                Text(isSection
                     ? "Sections group related pages, like posts or docs."
                     : "A single page of writing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Design.Metrics.padding)
    }

    private var slug: String {
        SiteEngine.slugify(title)
    }

    private func field<Content: View>(_ label: String, help: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            content()
            if let help {
                Text(help)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        engine.errorMessage = nil

        Task {
            let created: ContentItem?
            if isSection {
                created = await engine.createPage(section: section.isEmpty ? "" : section + "/" + slug,
                                                  name: name,
                                                  kind: "section")
            } else {
                created = await engine.createPage(section: section, name: name, kind: "page")
            }
            isCreating = false
            if let created {
                engine.selectedItemID = created.id
                dismiss()
            }
        }
    }
}
