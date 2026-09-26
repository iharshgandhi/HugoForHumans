// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// What the app looks like the moment a site is open: the state of things,
/// one click to the things you do most, and a live console.
struct DashboardView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer
    @EnvironmentObject private var builder: Builder
    @EnvironmentObject private var creator: SiteCreator

    @Binding var showPreview: Bool
    @Binding var showConsole: Bool

    @State private var inventory = Builder.Inventory()
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                statsGrid

                if builder.lastResult == .failure("") || hasError {
                    buildErrorBanner
                }

                HStack(alignment: .top, spacing: 18) {
                    quickActions
                    recentContent
                }

                if showConsole {
                    console
                }
            }
            .padding(Design.Metrics.padding)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if let root = engine.root {
                inventory = await builder.contentInventory(root: root)
            }
        }
    }

    private var hasError: Bool {
        if case .failure = builder.lastResult { return true }
        return false
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.siteName)
                    .font(.system(size: 26, weight: .semibold))
                Text(heroSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    buildNowButton
                    previewButton
                }
                .padding(.top, 4)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: themeIcon)
                        .font(.system(size: 12))
                    Text(engine.config.theme.isEmpty ? "No theme yet" : engine.config.theme)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Design.accentSoft, in: Capsule())
                .foregroundStyle(Design.accent)

                if case .success(let pages, let duration) = builder.lastResult {
                    Text("Built \(pages) pages in \(duration)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Design.Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Design.accent.opacity(0.10), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var heroSubtitle: String {
        let base = engine.config.completeness
        if base < 0.4 { return "A good start. Finish your settings to be ready to publish." }
        if base < 0.8 { return "Nearly there — your site settings could be a little more complete." }
        return "Everything is filled in. This site is ready to publish."
    }

    private var themeIcon: String {
        ThemeCatalog.theme(named: engine.config.theme) != nil ? "paintbrush.fill" : "exclamationmark.triangle.fill"
    }

    private var buildNowButton: some View {
        Button {
            Task {
                if let root = engine.root { await builder.build(root: root, engine: engine) }
            }
        } label: {
            HStack(spacing: 6) {
                if builder.isBuilding {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "hammer.fill")
                }
                Text(builder.isBuilding ? "Building…" : "Build Site")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(builder.isBuilding)
    }

    private var previewButton: some View {
        Button {
            if let root = engine.root { preview.toggle(root: root, engine: engine) }
        } label: {
            Label(preview.state.isRunning ? "Stop Preview" : "Start Preview",
                  systemImage: preview.state.isRunning ? "stop.fill" : "play.fill")
        }
        .controlSize(.regular)
    }

    private var buildErrorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("The last build did not finish")
                    .font(.system(size: 12, weight: .semibold))
                if case .failure(let message) = builder.lastResult {
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.orange.opacity(0.10)))
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            StatTile(value: "\(engine.publishedCount)", label: "Published", icon: "checkmark.seal.fill", tint: .green)
            StatTile(value: "\(engine.draftCount)", label: "Drafts", icon: "pencil.line", tint: .orange)
            StatTile(value: "\(engine.assetCount)", label: "Media files", icon: "photo.on.rectangle", tint: .blue)
            StatTile(value: "\(engine.totalWords)", label: "Words written", icon: "textformat", tint: .purple)
            StatTile(value: engine.config.theme.isEmpty ? "—" : engine.config.theme,
                     label: "Theme", icon: "paintbrush", tint: Design.accent)
            StatTile(value: "\(inventory.all)", label: "Indexed by Hugo", icon: "magnifyingglass", tint: .teal)
        }
    }

    // MARK: - Panels

    private var quickActions: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                Design.sectionHeader("Quick actions")
                actionRow(icon: "plus", title: "New page", detail: "Write something") {
                    NotificationCenter.default.post(name: .hfhNewPage, object: nil)
                }
                actionRow(icon: "folder.badge.plus", title: "New section", detail: "Group pages together") {
                    NotificationCenter.default.post(name: .hfhNewSection, object: nil)
                }
                actionRow(icon: "gearshape", title: "Site settings", detail: "Title, address, language") {
                    NotificationCenter.default.post(name: .hfhShowSettings, object: nil)
                }
                actionRow(icon: "paperplane", title: "Publish", detail: "Export to a folder") {
                    NotificationCenter.default.post(name: .hfhShowPublish, object: nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.accent)
                    .frame(width: 24, height: 24)
                    .background(Design.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentContent: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Design.sectionHeader("Content")
                    Spacer()
                    Text("\(engine.items.count) files")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if engine.items.isEmpty {
                    Text("No pages yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Create your first page") {
                        NotificationCenter.default.post(name: .hfhNewPage, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    ForEach(engine.items.prefix(6)) { item in
                        Button {
                            engine.selectedItemID = item.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.isDraft ? "pencil.line" : "doc.text")
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.isDraft ? .orange : .secondary)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Text(item.relativePath)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if item.isDraft {
                                    Text("DRAFT")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var console: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Design.sectionHeader("Activity")
                    Spacer()
                    Button("Clear") { engine.clearLog() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                    Button {
                        withAnimation { showConsole = false }
                    } label: {
                        Image(systemName: "chevron.up").font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(engine.log.suffix(40)) { LogRow(line: $0) }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }
}

extension Design {
    /// `card` with explicit alignment, so callers can pin content to the top.
    static func card<Content: View>(alignment: HorizontalAlignment,
                                    padding: CGFloat = Metrics.padding,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: alignment, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
