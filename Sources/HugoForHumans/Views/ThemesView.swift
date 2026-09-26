// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// Install, switch, and remove themes without touching the terminal.
struct ThemesView: View {
    @EnvironmentObject private var engine: SiteEngine
    @State private var installing: String?
    @State private var search = ""
    @State private var category: Theme.Category?
    @State private var message: String?
    /// Whether `message` reports a problem. The banner is not dressed as good
    /// news when an import was rejected.
    @State private var messageIsError = false
    @State private var confirmRemoval: Theme?

    private var results: [Theme] {
        ThemeCatalog.themes(in: category).filter { theme in
            guard !search.isEmpty else { return true }
            let q = search.lowercased()
            return theme.name.lowercased().contains(q)
                || theme.tagline.lowercased().contains(q)
                || theme.category.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(eyebrow: "THEMES", title: "Themes",
                            subtitle: "Every theme below was verified to build with Hugo \(shortVersion).") {
                if engine.root != nil {
                    Button {
                        engine.updateConfig(engine.config)
                        message = "Theme setting saved to hugo.toml"
                        clearMessageSoon()
                    } label: {
                        Label("Save Current", systemImage: "checkmark.circle")
                    }
                    .controlSize(.small)
                    .disabled(engine.config.theme.isEmpty)
                    .help("Write the selected theme into hugo.toml")
                }

                // A theme the user built themselves, or downloaded from
                // somewhere the catalogue does not list. It lands in the same
                // themes/ folder a catalogue theme would, so everything
                // downstream is unchanged.
                Menu {
                    Button {
                        importThemeFromFolder()
                    } label: {
                        Label("Choose a Theme Folder…", systemImage: "folder")
                    }
                    Button {
                        importThemeFromArchive()
                    } label: {
                        Label("Choose a Theme Archive…", systemImage: "archivebox")
                    }
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(engine.root == nil)
                .help("Use a Hugo theme from your own disk")
            }

            VStack(spacing: 0) {
                filterBar
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        ForEach(results) { theme in
                            card(theme)
                        }
                    }
                    .padding(Design.Metrics.padding)
                }
            }

            if let message {
                HStack(spacing: 8) {
                    Image(systemName: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(messageIsError ? .orange : .green)
                    Text(message).font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, Design.Metrics.padding)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Remove theme?", isPresented: Binding(
            get: { confirmRemoval != nil },
            set: { if !$0 { confirmRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                if let theme = confirmRemoval { remove(theme) }
                confirmRemoval = nil
            }
            Button("Cancel", role: .cancel) { confirmRemoval = nil }
        } message: {
            Text("The theme folder will be deleted from this site. Your content is not affected.")
        }
    }

    private var shortVersion: String {
        HugoBinary.shortVersion() ?? "extended"
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $category) {
                Text("All").tag(Theme.Category?.none)
                ForEach(Theme.Category.allCases) { c in
                    Text(c.rawValue).tag(Theme.Category?.some(c))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search themes", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06)))
            .frame(maxWidth: 200)
            Spacer()
        }
        .padding(.horizontal, Design.Metrics.padding)
        .padding(.vertical, 10)
    }

    private func card(_ theme: Theme) -> some View {
        let isInstalled = engine.installedThemes.contains { $0.lowercased() == theme.name.lowercased() }
        let isActive = engine.config.theme.lowercased() == theme.name.lowercased()

        return VStack(alignment: .leading, spacing: 10) {
            ThemeThumbnail(theme: theme, isSelected: isActive)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: .semibold))
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Design.accent, in: Capsule())
                            .foregroundStyle(.white)
                    } else if isInstalled {
                        Text("INSTALLED")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(theme.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if installing == theme.name {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Installing…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        if isInstalled {
                            confirmRemoval = theme
                        } else {
                            install(theme)
                        }
                    } label: {
                        Text(isInstalled ? "Remove" : "Install")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Button {
                        activate(theme)
                    } label: {
                        Text("Use")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isInstalled)

                    Spacer()

                    if let url = theme.repoURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                        }
                        .help("View on GitHub")
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Design.accent : Color.primary.opacity(0.08),
                              lineWidth: isActive ? 2 : 1)
        )
    }

    // MARK: - Importing a local theme

    private func importThemeFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your theme folder — the one containing layouts/"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTheme(.directory(url))
    }

    private func importThemeFromArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a theme archive (.zip, .tar, .tar.gz)"
        // A theme may also arrive as a bare folder, so both are allowed.
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTheme(url.pathExtension.lowercased().isEmpty ? .directory(url) : .archive(url))
    }

    private func importTheme(_ source: LocalThemeInstaller.Source) {
        guard let root = engine.root else { return }
        installing = "your theme"
        Task {
            // Reading and copying a large theme takes a moment, so it runs off
            // the main actor and reports back when finished.
            let outcome: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try LocalThemeInstaller.install(source, into: root)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                installing = nil
                switch outcome {
                case .success(let destination):
                    let name = destination.lastPathComponent
                    messageIsError = false
                    message = "\(name) imported from your own disk. Press Use to switch to it."
                    // The gallery lists catalogue themes, so an imported one is
                    // not in `results` — refresh so the installed set is right.
                    engine.reloadAll()
                case .failure(let error):
                    messageIsError = true
                    message = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Actions

    private func install(_ theme: Theme) {
        guard let root = engine.root else { return }
        installing = theme.name
        Task {
            let result = await HFH.run(["mod", "init"], workingDirectory: root) { _ in }
            _ = result

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["clone", "--depth", "1", theme.repoURL!.absoluteString,
                                root.appendingPathComponent("themes/\(theme.name)").path]
            process.currentDirectoryURL = root
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do { try process.run() } catch {
                installing = nil
                message = nil
                return
            }
            process.waitUntilExit()

            await MainActor.run {
                installing = nil
                if process.terminationStatus == 0 {
                    let gitDir = root.appendingPathComponent("themes/\(theme.name)/.git")
                    try? FileManager.default.removeItem(at: gitDir)
                    engine.reloadAll()
                    messageIsError = false
                    message = "\(theme.name) installed. Press Use to switch to it."
                } else {
                    messageIsError = true
                    message = "Could not install \(theme.name). Check your internet connection."
                }
                clearMessageSoon()
            }
        }
    }

    private func activate(_ theme: Theme) {
        var config = engine.config
        config.theme = theme.name
        engine.updateConfig(config)
        message = "\(theme.name) is now your theme. Build to see it."
        clearMessageSoon()
    }

    private func remove(_ theme: Theme) {
        guard let root = engine.root else { return }
        let path = root.appendingPathComponent("themes/\(theme.name)")
        do {
            try FileManager.default.removeItem(at: path)
            if engine.config.theme.lowercased() == theme.name.lowercased() {
                var config = engine.config
                config.theme = ""
                engine.updateConfig(config)
            }
            engine.reloadAll()
            message = "\(theme.name) removed."
            clearMessageSoon()
        } catch {
            message = "Could not remove the theme."
            clearMessageSoon()
        }
    }

    private func clearMessageSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { message = nil }
        }
    }
}
