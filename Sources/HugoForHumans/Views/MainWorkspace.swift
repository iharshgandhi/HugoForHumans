// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// The three-pane Mac layout: sites and content on the left, the editor in the
/// middle, live preview on the right.
struct MainWorkspace: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer
    @EnvironmentObject private var builder: Builder

    @State private var showInspector = true
    @State private var showPreview = true
    @State private var showConsole = false
    @State private var newPageSheet: NewItemSheet?
    @State private var pendingDelete: ContentItem?
    @State private var showingSettings = false

    enum Pane: Hashable { case editor, settings, publish, themes, dashboard }

    /// Which kind of thing the new-item sheet is creating.
    enum NewItemSheet: Identifiable, Hashable {
        case page, section
        var id: String { self == .page ? "page" : "section" }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(newPageSheet: $newPageSheet, pane: paneBinding)
                .navigationSplitViewColumnWidth(min: 230, ideal: Design.Metrics.sidebarWidth, max: 340)
        } detail: {
            VStack(spacing: 0) {
                workspaceHeader

                switch currentPane {
                case .dashboard:
                    DashboardView(showPreview: $showPreview, showConsole: $showConsole)
                case .settings:
                    SiteSettingsView()
                case .publish:
                    PublishView()
                case .themes:
                    ThemesView()
                case .editor:
                    editorArea
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $newPageSheet) { sheet in
            NewItemSheetController(sheet: sheet)
        }
        .modifier(WorkspaceHandlers(
            onNewPage: { newPageSheet = .page },
            onNewSection: { newPageSheet = .section },
            onBuild: { if let root = engine.root { Task { await builder.build(root: root, engine: engine) } } },
            onShowSettings: { currentPane = .settings; engine.selectedItemID = nil },
            onShowPublish: { currentPane = .publish; engine.selectedItemID = nil },
            onDelete: { pendingDelete = $0 },
            onTogglePreview: { if let root = engine.root { preview.toggle(root: root, engine: engine) } }
        ))
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { engine.delete(item) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The file is removed from disk. This cannot be undone.")
        }
    }

    @State private var currentPane: Pane = .dashboard

    // Split out from `body`: a long chain of modifiers in one expression makes
    // the type-checker time out, so the menu plumbing lives in its own modifier.
    private var deleteConfirmation: some View {
        confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { engine.delete(item) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The file is removed from disk. This cannot be undone.")
        }
    }

    /// Menu-bar and shortcut commands arrive as notifications; this modifier turns
    /// them into the closures the workspace needs, keeping `body` readable.
    private struct WorkspaceHandlers: ViewModifier {
        var onNewPage: () -> Void
        var onNewSection: () -> Void
        var onBuild: () -> Void
        var onShowSettings: () -> Void
        var onShowPublish: () -> Void
        var onDelete: (ContentItem) -> Void
        var onTogglePreview: () -> Void

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: .hfhNewPage)) { _ in onNewPage() }
                .onReceive(NotificationCenter.default.publisher(for: .hfhNewSection)) { _ in onNewSection() }
                .onReceive(NotificationCenter.default.publisher(for: .hfhBuild)) { _ in onBuild() }
                .onReceive(NotificationCenter.default.publisher(for: .hfhShowSettings)) { _ in onShowSettings() }
                .onReceive(NotificationCenter.default.publisher(for: .hfhShowPublish)) { _ in onShowPublish() }
                .onReceive(NotificationCenter.default.publisher(for: .hfhDelete)) { note in
                    if let item = note.object as? ContentItem { onDelete(item) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .hfhTogglePreview)) { _ in
                    onTogglePreview()
                }
        }
    }

    /// Selecting a pane in the sidebar swaps the detail area; selecting a page
    /// clears the pane so the editor takes over.
    private var paneBinding: Binding<Pane?> {
        Binding(
            get: { engine.selectedItemID == nil ? currentPane : nil },
            set: { newValue in
                if let newValue {
                    currentPane = newValue
                } else {
                    currentPane = .editor
                }
            }
        )
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        HStack(spacing: 10) {
            Button {
                currentPane = .dashboard
                engine.selectedItemID = nil
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                    Text(engine.siteName)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .help("Dashboard")

            Spacer()

            HStack(spacing: 8) {
                Button {
                    newPageSheet = .page
                } label: {
                    Label("New Page", systemImage: "plus")
                }
                .help("Create a page (⇧⌘N)")

                Button {
                    newPageSheet = .section
                } label: {
                    Label("New Section", systemImage: "folder.badge.plus")
                }
                .help("Create a section (⌥⌘N)")

                Divider().frame(height: 18)

                buildButton

                previewButton
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Design.Metrics.padding)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var buildButton: some View {
        Button {
            Task {
                if let root = engine.root {
                    await builder.build(root: root, engine: engine)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if builder.isBuilding {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "hammer.fill")
                }
                Text(builder.isBuilding ? "Building" : "Build")
            }
        }
        .help("Build the site into public/ (⌘B)")
        .disabled(builder.isBuilding || engine.root == nil)
    }

    private var previewButton: some View {
        Button {
            if let root = engine.root { preview.toggle(root: root, engine: engine) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(preview.state.isRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(preview.state.isRunning ? "Stop" : "Preview")
            }
        }
        .help("Start or stop the live preview (⌘R)")
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorArea: some View {
        if let id = engine.selectedItemID, let item = engine.item(withID: id) {
            HStack(spacing: 0) {
                EditorPane(item: item, showInspector: $showInspector)
                if showPreview {
                    Divider()
                    PreviewPane(item: item)
                        .frame(minWidth: 380)
                }
            }
        } else {
            EmptyStateView(
                icon: "square.and.pencil",
                title: "Nothing open",
                message: "Pick a page in the sidebar, or create a new one to start writing.",
                actionTitle: "New Page",
                action: { newPageSheet = .page }
            )
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer
    @Binding var newPageSheet: MainWorkspace.NewItemSheet?
    @Binding var pane: MainWorkspace.Pane?

    var body: some View {
        VStack(spacing: 0) {
            sitePicker

            List(selection: selectionBinding) {
                Section {
                    row(icon: "square.grid.2x2", title: "Dashboard", badge: nil, pane: .dashboard)
                    row(icon: "gearshape", title: "Site Settings", badge: nil, pane: .settings)
                    row(icon: "paintbrush", title: "Themes", badge: engine.installedThemes.isEmpty ? nil : "\(engine.installedThemes.count)", pane: .themes)
                    row(icon: "paperplane", title: "Publish", badge: nil, pane: .publish)
                }

                if !engine.sections.isEmpty {
                    Section {
                        ForEach(engine.sections) { section in
                            sectionRows(section)
                        }
                    } header: {
                        HStack {
                            Text("CONTENT")
                            Spacer()
                            Button {
                                newPageSheet = .page
                            } label: {
                                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .help("New page")
                        }
                    }
                }

                let media = engine.items.filter { $0.kind == .asset }
                if !media.isEmpty {
                    Section("MEDIA") {
                        ForEach(media) { item in
                            contentRow(item, pane: .editor)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            footer
        }
        .searchable(text: searchBinding, placement: .sidebar, prompt: "Search pages")
    }

    private var sitePicker: some View {
        Menu {
            ForEach(RecentSites.all(), id: \.self) { url in
                Button {
                    engine.openSite(at: url)
                } label: {
                    if url == engine.root {
                        Label(url.lastPathComponent, systemImage: "checkmark")
                    } else {
                        Text(url.lastPathComponent)
                    }
                }
            }
            if !RecentSites.all().isEmpty { Divider() }
            Button("New Site…") { NotificationCenter.default.post(name: .hfhShowWelcome, object: nil) }
            Button("Open Folder…") { openSitePanel() }
            if !RecentSites.all().isEmpty {
                Divider()
                Button("Forget This Site") {
                    if let root = engine.root { RecentSites.forget(root) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.siteName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(engine.root?.lastPathComponent ?? "No site")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func row(icon: String, title: String, badge: String?, pane: MainWorkspace.Pane) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(PaneTag.pane(pane))
    }

    @ViewBuilder
    private func sectionRows(_ section: ContentSection) -> some View {
        let pages = section.items.filter { $0.kind != .asset }
        let assets = section.items.filter { $0.kind == .asset }
        DisclosureGroup {
            ForEach(pages) { item in
                contentRow(item, pane: .editor)
            }
            ForEach(assets) { item in
                contentRow(item, pane: .editor)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Design.accent.opacity(0.8))
                Text(section.displayName)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if section.draftCount > 0 {
                    Text("\(section.draftCount) draft")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text("\(section.pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func contentRow(_ item: ContentItem, pane: MainWorkspace.Pane) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: item))
                .font(.system(size: 10))
                .foregroundStyle(item.isDraft ? .orange : .secondary)
                .frame(width: 14)
            Text(item.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .italic(item.isDraft)
            Spacer(minLength: 2)
            if item.isDraft {
                Circle().fill(Color.orange).frame(width: 5, height: 5)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 8)
        .tag(PaneTag.item(item.id))
        .contextMenu {
            Button(item.isDraft ? "Publish" : "Move to Drafts") {
                engine.toggleDraft(item)
            }
            Button("Duplicate") { duplicate(item) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Delete", role: .destructive) { NotificationCenter.default.post(name: .hfhDelete, object: item) }
        }
    }

    private func icon(for item: ContentItem) -> String {
        switch item.kind {
        case .section: return "folder"
        case .bundle: return "square.stack"
        case .page: return "doc.text"
        case .asset:
            switch item.ext {
            case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
            case "pdf": return "doc.richtext"
            default: return "paperclip"
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(preview.state.isRunning ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(preview.state.isRunning ? "Preview on \(preview.state.url ?? "")" : "Preview off")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if engine.root != nil {
                    Button {
                        if let root = engine.root { preview.toggle(root: root, engine: engine) }
                    } label: {
                        Image(systemName: preview.state.isRunning ? "stop.fill" : "play.fill").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .help(preview.state.isRunning ? "Stop preview" : "Start preview")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Bindings & actions

    private var selectionBinding: Binding<PaneTag?> {
        Binding(
            get: {
                if let id = engine.selectedItemID { return .item(id) }
                if let pane { return .pane(pane) }
                return .pane(.dashboard)
            },
            set: { tag in
                switch tag {
                case .item(let id):
                    engine.selectedItemID = id
                case .pane(let value):
                    engine.selectedItemID = nil
                    pane = value
                case nil:
                    engine.selectedItemID = nil
                }
            }
        )
    }

    private var searchBinding: Binding<String> {
        Binding(get: { engine.searchText }, set: { engine.searchText = $0 })
    }

    private func duplicate(_ item: ContentItem) {
        guard let root = engine.root else { return }
        let copy = item.url.deletingLastPathComponent()
            .appendingPathComponent("\(item.baseName)-copy.md")
        try? FileManager.default.copyItem(at: item.url, to: copy)
        engine.scanContent()
        if let reloaded = ContentItem.load(from: copy, projectRoot: root) {
            engine.selectedItemID = reloaded.id
        }
    }

    private func openSitePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder that contains hugo.toml"
        if panel.runModal() == .OK, let url = panel.url {
            engine.openSite(at: url)
        }
    }
}

/// List selection needs a single tag type mixing panes and content items.
enum PaneTag: Hashable {
    case pane(MainWorkspace.Pane)
    case item(String)
}
