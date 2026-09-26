// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI
import WebKit

/// In-app live preview. Loads the page straight from `hugo server`, so what you
/// see is Hugo's real output — not an approximation rendered by the app.
struct PreviewPane: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var preview: PreviewServer
    @EnvironmentObject private var builder: Builder

    var item: ContentItem
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            bar
            content
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if preview.state.isRunning {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(preview.state.url ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 5) {
                    Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    Text("Preview stopped")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let root = engine.root {
                Button {
                    preview.toggle(root: root, engine: engine)
                } label: {
                    Image(systemName: preview.state.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(preview.state.isRunning ? "Stop preview" : "Start preview")

                Button {
                    NSWorkspace.shared.open(URL(string: preview.state.url ?? "http://127.0.0.1:\(preview.port)")!)
                } label: {
                    Image(systemName: "safari").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Open in your browser")
                .disabled(!preview.state.isRunning)

                Button {
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Reload")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var content: some View {
        switch preview.state {
        case .running:
            PreviewWebView(url: previewURL, reloadToken: reloadToken)
                .id(reloadToken)
        case .starting:
            VStack(spacing: 10) {
                ProgressView()
                Text("Hugo is starting…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stopped:
            EmptyStateView(
                icon: "eye.slash",
                title: "Preview is off",
                message: "Start the preview to see your site render exactly as Hugo builds it.",
                actionTitle: "Start Preview",
                action: {
                    if let root = engine.root { preview.start(root: root, engine: engine) }
                }
            )
        case .failed(let message):
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Preview could not start",
                message: message,
                actionTitle: "Try Again",
                action: {
                    if let root = engine.root { preview.start(root: root, engine: engine) }
                }
            )
        }
    }

    /// The preview URL for the selected page, derived the way Hugo derives it.
    private var previewURL: URL? {
        guard let base = preview.state.url else { return nil }
        var path = "/"
        if item.kind != .section {
            let section = item.section
            let slug = item.frontMatter["slug"]?.stringValue ?? item.baseName
            path = section.isEmpty ? "/\(slug)/" : "/\(section)/\(slug)/"
        } else if !item.section.isEmpty {
            path = "/\(item.section)/"
        }
        return URL(string: base + path)
    }
}

/// A WKWebView that reloads when the token changes.
struct PreviewWebView: NSViewRepresentable {
    var url: URL?
    var reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        // A transparent-ish chrome makes the preview blend into the app.
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else { return }
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            webView.load(URLRequest(url: url))
        } else if reloadToken != context.coordinator.lastToken {
            webView.reload()
        }
        context.coordinator.lastToken = reloadToken
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
        var lastToken: Int = 0
    }
}
