// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// Build options and export. Every Hugo build flag that matters in practice is a
/// checkbox here, with the equivalent command shown underneath.
struct PublishView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var builder: Builder

    @State private var showCommand = false
    @State private var tab: PublishTab = .deploy

    enum PublishTab: String, CaseIterable, Identifiable {
        case deploy = "Put it online"
        case build = "Build and export"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The deploy tab brings its own header, so the outer one is only
            // shown for the build tab — two stacked headers read as a mistake.
            if tab == .build {
                WorkspaceHeader(eyebrow: "PUBLISH", title: "Publish",
                                subtitle: "Build the final site, then send it anywhere that serves static files.") {
                    Button {
                        Task {
                            if let root = engine.root { await builder.build(root: root, engine: engine) }
                        }
                    } label: {
                        if builder.isBuilding {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Label("Build", systemImage: "hammer.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(builder.isBuilding)
                }
            }

            Picker("", selection: $tab) {
                ForEach(PublishTab.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Design.Metrics.padding)
            .padding(.bottom, 10)
            .frame(maxWidth: 430, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))

            switch tab {
            case .deploy:
                DeployView()
            case .build:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        resultCard

                        HStack(alignment: .top, spacing: 18) {
                            optionsCard
                            exportCard
                        }

                        commandCard
                    }
                    .padding(Design.Metrics.padding)
                    .frame(maxWidth: 900, alignment: .leading)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Result

    @ViewBuilder
    private var resultCard: some View {
        switch builder.lastResult {
        case .idle:
            Design.card(alignment: .leading) {
                HStack(spacing: 12) {
                    Image(systemName: "hammer.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No build yet").font(.system(size: 14, weight: .semibold))
                        Text("Build to generate the final HTML into your site's public folder.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .building:
            Design.card(alignment: .leading) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Building…").font(.system(size: 14, weight: .medium))
                }
            }
        case .success(let pages, let duration):
            Design.card(alignment: .leading) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built \(pages) pages in \(duration)")
                            .font(.system(size: 14, weight: .semibold))
                        if let publicDir = engine.publicDirectory {
                            Text(publicDir.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                }
            }
        case .failure(let message):
            Design.card(alignment: .leading) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The build failed").font(.system(size: 14, weight: .semibold))
                        Text(message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Options

    private var optionsCard: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                Design.sectionHeader("Build options")
                ForEach(builder.options, id: \.key) { option in
                    Toggle(isOn: binding(for: option.key)) {
                        HStack(spacing: 8) {
                            Text(option.label).font(.system(size: 12.5))
                            Text(option.key)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06), in: Rectangle())
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment")
                        .font(.system(size: 12, weight: .medium))
                    TextField("production", text: $builder.environment)
                        .textFieldStyle(.roundedBorder)
                    Text("Config overrides live in config/ using this name.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL override")
                        .font(.system(size: 12, weight: .medium))
                    TextField("leave blank to use the site setting", text: $builder.baseURLOverride)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                switch key {
                case "-D": return builder.includeDrafts
                case "-F": return builder.includeFuture
                case "-E": return builder.includeExpired
                case "--minify": return builder.minify
                case "--cleanDestinationDir": return builder.cleanDestination
                case "--enableGitInfo": return builder.enableGitInfo
                case "--gc": return builder.gc
                case "-M": return builder.renderToMemory
                default: return false
                }
            },
            set: { newValue in
                switch key {
                case "-D": builder.includeDrafts = newValue
                case "-F": builder.includeFuture = newValue
                case "-E": builder.includeExpired = newValue
                case "--minify": builder.minify = newValue
                case "--cleanDestinationDir": builder.cleanDestination = newValue
                case "--enableGitInfo": builder.enableGitInfo = newValue
                case "--gc": builder.gc = newValue
                case "-M": builder.renderToMemory = newValue
                default: break
                }
            }
        )
    }

    // MARK: - Export

    private var exportCard: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                Design.sectionHeader("Take it live")

                exportRow(icon: "folder", title: "Reveal public folder",
                          detail: "Open the built site in Finder") {
                    if let dir = engine.publicDirectory, FileManager.default.fileExists(atPath: dir.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([dir])
                    }
                }

                exportRow(icon: "safari", title: "Preview the built site",
                          detail: "Serve public/ like a real host would") {
                    openInBrowser()
                }

                exportRow(icon: "square.and.arrow.up", title: "Export a .zip",
                          detail: "Upload this to any static host") {
                    exportZip()
                }

                Divider()
                Text("Most hosts need two more things")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("netlify.toml")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(netlifyConfig)
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    Button("Copy netlify.toml") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(netlifyConfig, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func exportRow(icon: String, title: String, detail: String,
                           action: @escaping () -> Void) -> some View {
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var commandCard: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Design.sectionHeader("The command behind this")
                    Spacer()
                    Button {
                        withAnimation { showCommand.toggle() }
                    } label: {
                        Image(systemName: showCommand ? "chevron.up" : "chevron.down").font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                }
                if showCommand {
                    Text(builder.previewCommand)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    Text("Paste this into a terminal and you get exactly what this app just did.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(builder.previewCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var netlifyConfig: String {
        """
        [build]
          command = "hugo"
          publish = "public"

        [build.environment]
          HUGO_VERSION = "\(hugoVersion)"
        """
    }

    private var hugoVersion: String {
        HugoBinary.shortVersion() ?? "0.166.0"
    }

    private func openInBrowser() {
        guard let dir = engine.publicDirectory, FileManager.default.fileExists(atPath: dir.path) else { return }
        // Opening index.html directly works for simple sites; a local server is more
        // faithful, so fall back to the preview server if one is already running.
        if previewRunning {
            NSWorkspace.shared.open(URL(string: "http://127.0.0.1:1313")!)
        } else {
            NSWorkspace.shared.open(dir.appendingPathComponent("index.html"))
        }
    }

    private var previewRunning: Bool { false }

    private func exportZip() {
        guard let publicDir = engine.publicDirectory,
              FileManager.default.fileExists(atPath: publicDir.path) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(engine.siteName.replacingOccurrences(of: " ", with: "-")).zip"
        panel.message = "Save the built site as a zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                             publicDir.path, destination.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                engine.log(.success, "Exported \(destination.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } else {
                engine.log(.error, "Export failed")
            }
        } catch {
            engine.log(.error, "Export failed: \(error.localizedDescription)")
        }
    }
}
