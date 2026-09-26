// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// Every field in hugo.toml, as a form. The point is that nothing here requires
/// knowing what a TOML file is.
struct SiteSettingsView: View {
    @EnvironmentObject private var engine: SiteEngine

    @State private var draft = SiteConfig()
    @State private var taxonomiesText = ""
    @State private var loaded = false
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorkspaceHeader(eyebrow: "SETTINGS", title: "Site Settings",
                                subtitle: "These write directly to \(SiteConfig.configFileName(in: engine.root ?? URL(fileURLWithPath: "/")))") {
                    if savedFlash {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                if let root = engine.root {
                    VStack(alignment: .leading, spacing: 20) {
                        group("Identity", icon: "person.text.rectangle") {
                            field("Site title", help: "The name at the top of every page.") {
                                TextField("My Site", text: $draft.title)
                            }
                            field("Description", help: "Used by search engines and social previews.") {
                                TextField("A short description", text: $draft.description, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                            field("Your name", help: "Shown on post pages when the theme supports an author.") {
                                TextField("Your name", text: $draft.author)
                            }
                            field("Copyright", help: "Appears in the footer of most themes.") {
                                TextField("© 2026", text: $draft.copyright)
                            }
                        }

                        group("Address", icon: "globe") {
                            field("Web address", help: "Where the finished site will live. Include https:// and a trailing slash.") {
                                TextField("https://example.org/", text: $draft.baseURL)
                            }
                            field("Language", help: "A locale such as en-us, en-gb, de-de, hi-in.") {
                                TextField("en-us", text: $draft.languageCode)
                            }
                            field("Summary length", help: "How many words a page summary shows in a list.") {
                                Stepper("\(draft.summaryLength) words",
                                        value: $draft.summaryLength, in: 10...200, step: 10)
                            }
                        }

                        group("Appearance", icon: "paintbrush") {
                            field("Theme", help: "Installed themes are in your site's themes folder.") {
                                HStack {
                                    Picker("", selection: $draft.theme) {
                                        Text("None").tag("")
                                        ForEach(SiteEngine.themes(in: root), id: \.self) { name in
                                            Text(name).tag(name)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 220)
                                    if !ThemeCatalog.notes(for: ThemeCatalog.all.first { $0.name == draft.theme } ?? ThemeCatalog.all[0]).isEmpty {
                                        Text("Needs extra setup")
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            Toggle("Let Markdown include raw HTML (needed by many themes)", isOn: $rawHTMLEnabled)
                        }

                        group("Organising", icon: "square.grid.3x3") {
                            field("Taxonomies", help: "These create the /tags/ and /categories/ pages.") {
                                TextField("tags, categories", text: $taxonomiesText)
                            }
                            Toggle("Generate robots.txt for search engines", isOn: $draft.enableRobotsTXT)
                            Toggle("Show emoji shortcodes like :smile:", isOn: $draft.enableEmoji)
                            Toggle("Attach Git commit details to each page", isOn: $draft.enableGitInfo)
                        }

                        HStack {
                            Spacer()
                            Button("Save Settings") { save() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, Design.Metrics.padding)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadIfNeeded)
        .onChange(of: engine.root) { _, _ in loaded = false; loadIfNeeded() }
    }

    /// Raw HTML is stored in the [markup] table, which SiteConfig always writes as
    /// true; surfaced here as a toggle for transparency.
    @State private var rawHTMLEnabled = true

    private func loadIfNeeded() {
        guard !loaded, engine.root != nil else { return }
        draft = engine.config
        taxonomiesText = engine.config.taxonomies.joined(separator: ", ")
        loaded = true
    }

    private func save() {
        draft.taxonomies = taxonomiesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        engine.updateConfig(draft)
        withAnimation(.easeOut(duration: 0.2)) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.2)) { savedFlash = false }
        }
    }

    private func group<Content: View>(_ title: String, icon: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
            Design.card(alignment: .leading) {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
    }

    private func field<Content: View>(_ label: String, help: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            content()
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

/// The app-level settings pane (Settings… from the menu).
struct SettingsView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer

    @AppStorage("defaultPort") private var defaultPort = 1313
    @AppStorage("includeDraftsByDefault") private var includeDrafts = true
    @AppStorage("clearCacheOnQuit") private var clearCache = false

    var body: some View {
        TabView {
            previewSettings
                .tabItem { Label("Preview", systemImage: "play.rectangle") }
            engineSettings
                .tabItem { Label("Hugo", systemImage: "gearshape.2") }
        }
        .padding(16)
    }

    private var previewSettings: some View {
        Form {
            Section("Live preview") {
                Stepper("Port: \(defaultPort)", value: $defaultPort, in: 1024...65535, step: 1)
                Toggle("Show drafts in the preview", isOn: $includeDrafts)
                Toggle("Open your browser when preview starts", isOn: $preview.openBrowser)
            }
            .onChange(of: defaultPort) { _, newValue in preview.port = newValue }
            .onChange(of: includeDrafts) { _, newValue in preview.includeDrafts = newValue }

            Section {
                HStack {
                    Text("Cache folder")
                    Spacer()
                    Button("Open") {
                        NSWorkspace.shared.open(HugoBinary.supportDirectory.appendingPathComponent("hugo_cache"))
                    }
                }
                Toggle("Clear the cache when the app quits", isOn: $clearCache)
            } header: {
                Text("Performance")
            } footer: {
                Text("Hugo keeps a build cache between runs. Clearing it makes the next build slower but frees disk space.")
            }
        }
        .formStyle(.grouped)
    }

    private var engineSettings: some View {
        Form {
            Section("Hugo engine") {
                if let url = HugoBinary.resolve(), let version = HugoBinary.version(of: url) {
                    LabeledContent("Version", value: HugoBinary.displayVersion(of: url) ?? url.lastPathComponent)
                    LabeledContent("Binary", value: url.path)
                    LabeledContent("Build", value: version.contains("extended") ? "extended (SCSS supported)" : "standard")
                } else {
                    Label("No Hugo binary found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Your sites") {
                if RecentSites.all().isEmpty {
                    Text("No sites yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(RecentSites.all(), id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer()
                            if url == engine.root {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                            Button("Remove") { RecentSites.forget(url) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                Button("Reveal Support Folder") {
                    NSWorkspace.shared.open(HugoBinary.supportDirectory)
                }
            } footer: {
                Text("Hugo for Humans keeps its downloaded themes and cache here, outside your site folders.")
            }
        }
        .formStyle(.grouped)
    }
}
