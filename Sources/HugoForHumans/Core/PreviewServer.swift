// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
#if canImport(Combine)
import Combine
#endif

/// Owns `hugo server`: starts it, streams its output, and surfaces the URL.
@MainActor
final class PreviewServer: ObservationBase {

    init() {}

    enum State: Equatable {
        case stopped
        case starting
        case running(url: String, port: Int)
        case failed(String)

        var isRunning: Bool { if case .running = self { return true }; return false }
        var url: String? { if case .running(let url, _) = self { return url }; return nil }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var lines: [String] = []
    @Published public var includeDrafts = true
    @Published public var openBrowser = false
    @Published public var port: Int = 1313
    @Published public var minify = false

    private var process: Process?
    private var outputTask: Task<Void, Never>?

    /// Starts the preview. Returns immediately; state updates as Hugo reports.
    func start(root: URL, engine: SiteEngine) {
        guard process == nil else { return }
        guard let hugo = HugoBinary.resolve() else {
            state = .failed("Hugo binary not found")
            return
        }

        state = .starting
        lines.removeAll()
        append("Starting preview…")

        var args = ["server", "--port", "\(port)", "--bind", "127.0.0.1"]
        if includeDrafts { args.append("--buildDrafts") }
        if minify { args.append("--minify") }
        if openBrowser { args.append("--openBrowser") }

        let process = Process()
        process.executableURL = hugo
        process.arguments = args
        process.currentDirectoryURL = root
        process.environment = HFH.baseEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        self.process = process

        outputTask = Task { [weak self] in
            for await line in HFH.lines(of: pipe) {
                await self?.handle(line: line)
            }
        }

        // Watch for the process dying on its own (port clash, config error).
        Task { [weak self] in
            process.waitUntilExit()
            await self?.handleExit(status: process.terminationStatus)
        }
    }

    private func handle(line: String) {
        append(line)
        // Hugo prints the URL in a couple of shapes depending on version.
        if let range = line.range(of: "http://") {
            let candidate = line[range.lowerBound...]
                .split(whereSeparator: { $0 == " " })
                .first
                .map(String.init) ?? ""
            var url = candidate
            if url.hasSuffix("/") { url.removeLast() }
            if let detected = URL(string: url), detected.host != nil {
                state = .running(url: "http://127.0.0.1:\(port)", port: port)
            }
        }
        if line.contains("Web Server is available") {
            state = .running(url: "http://127.0.0.1:\(port)", port: port)
        }
    }

    private func handleExit(status: Int32) {
        outputTask?.cancel()
        outputTask = nil
        process = nil
        if state == .starting {
            state = .failed(status == 0 ? "Preview stopped" : "Hugo exited with status \(status)")
        } else if state.isRunning {
            state = .stopped
        }
    }

    func stop() {
        guard let process else {
            state = .stopped
            return
        }
        append("Stopping preview…")
        process.terminate()
        self.process = nil
        outputTask?.cancel()
        outputTask = nil
        state = .stopped

        // Give Hugo a moment to close its listener gracefully, then insist.
        // `isRunning` is the right check here — shelling out to a `hugo` subcommand
        // to ask whether a pid is alive does not exist.
        let pid = process.processIdentifier
        Task { [weak process] in
            for _ in 0..<20 {
                if process?.isRunning != true { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process?.isRunning == true { kill(pid, SIGKILL) }
        }
    }

    func toggle(root: URL, engine: SiteEngine) {
        if state.isRunning || state == .starting {
            stop()
        } else {
            start(root: root, engine: engine)
        }
    }

    private func append(_ line: String) {
        lines.append(line)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }
}
