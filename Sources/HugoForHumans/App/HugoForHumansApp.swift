// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import AppKit

@main
struct HugoForHumansApp: App {
    @StateObject private var engine = SiteEngine()
    @StateObject private var preview = PreviewServer()
    @StateObject private var builder = Builder()
    @StateObject private var creator = SiteCreator()

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup("Hugo for Humans") {
            RootView()
                .environmentObject(engine)
                .environmentObject(preview)
                .environmentObject(builder)
                .environmentObject(creator)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear(perform: bootstrap)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands(engine: engine, preview: preview, builder: builder, creator: creator) }

        Settings {
            SettingsView()
                .environmentObject(engine)
                .environmentObject(preview)
                .environmentObject(builder)
                .frame(width: 520, height: 420)
        }
    }

    /// Reopen the last site automatically — a Mac app should remember where you were.
    private func bootstrap() {
        guard !hasSeenWelcome else {
            if engine.root == nil,
               let last = RecentSites.all().first(where: {
                   FileManager.default.fileExists(atPath: $0.appendingPathComponent("hugo.toml").path)
               }) {
                engine.openSite(at: last)
            }
            return
        }
        hasSeenWelcome = true
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: SiteEngine

    var body: some View {
        Group {
            if engine.isOpen {
                MainWorkspace()
            } else {
                WelcomeView()
            }
        }
        .animation(.smooth(duration: 0.25), value: engine.isOpen)
    }
}

// MARK: - Menu commands

struct AppCommands: Commands {
    var engine: SiteEngine
    var preview: PreviewServer
    var builder: Builder
    var creator: SiteCreator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Site…") {
                NSApp.keyWindow?.endEditing(for: nil)
                NotificationCenter.default.post(name: .hfhShowWelcome, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Site…") { openSitePanel() }
                .keyboardShortcut("o", modifiers: .command)

            Button("New Page") { NotificationCenter.default.post(name: .hfhNewPage, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!engine.isOpen)

            Button("New Section") { NotificationCenter.default.post(name: .hfhNewSection, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!engine.isOpen)
        }

        CommandGroup(after: .toolbar) {
            Button(engine.root == nil ? "No Site Open" : "Build Site") {
                NotificationCenter.default.post(name: .hfhBuild, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!engine.isOpen)

            Button(preview.state.isRunning ? "Stop Preview" : "Start Preview") {
                NotificationCenter.default.post(name: .hfhTogglePreview, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!engine.isOpen)

            Divider()

            Button("Reveal Site in Finder") {
                if let root = engine.root {
                    NSWorkspace.shared.activateFileViewerSelecting([root])
                }
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(!engine.isOpen)

            Button("Open Site Folder") {
                if let root = engine.root {
                    NSWorkspace.shared.open(root)
                }
            }
            .disabled(!engine.isOpen)
        }
    }

    private func openSitePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder that contains hugo.toml"
        panel.prompt = "Open Site"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in engine.openSite(at: url) }
        }
    }
}