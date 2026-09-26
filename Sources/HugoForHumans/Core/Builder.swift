// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
#if canImport(Combine)
import Combine
#endif

/// Wraps the build half of Hugo: `hugo`, `hugo --minify`, and the deploy-shaped
/// options, all driven from UI controls.
@MainActor
final class Builder: ObservationBase {

    init() {}

    @Published public var includeDrafts = false
    @Published public var includeFuture = false
    @Published public var includeExpired = false
    @Published public var minify = false
    @Published public var cleanDestination = true
    @Published public var enableGitInfo = false
    @Published public var environment = "production"
    @Published public var baseURLOverride = ""
    @Published public var renderToMemory = false
    @Published public var gc = false

    @Published private(set) var isBuilding = false
    @Published private(set) var lastResult: SiteEngine.BuildStatus = .idle
    @Published private(set) var output: String = ""

    var options: [(label: String, key: String, isOn: Bool)] {
        [("Include drafts", "-D", includeDrafts),
         ("Include future", "-F", includeFuture),
         ("Include expired", "-E", includeExpired),
         ("Minify HTML", "--minify", minify),
         ("Clean destination", "--cleanDestinationDir", cleanDestination),
         ("Git info", "--enableGitInfo", enableGitInfo),
         ("Run cleanup", "--gc", gc),
         ("Render to memory", "-M", renderToMemory)]
    }

    /// The literal command line, shown to the user so the GUI is never a black box.
    var previewCommand: String {
        var args = ["hugo"]
        if includeDrafts { args.append("-D") }
        if includeFuture { args.append("-F") }
        if includeExpired { args.append("-E") }
        if minify { args.append("--minify") }
        if cleanDestination { args.append("--cleanDestinationDir") }
        if enableGitInfo { args.append("--enableGitInfo") }
        if gc { args.append("--gc") }
        if !environment.isEmpty { args += ["-e", environment] }
        if !baseURLOverride.isEmpty { args += ["-b", baseURLOverride] }
        return args.joined(separator: " ")
    }

    @discardableResult
    func build(root: URL, engine: SiteEngine) async -> SiteEngine.BuildStatus {
        guard !isBuilding else { return .idle }
        isBuilding = true
        defer { isBuilding = false }

        var args: [String] = []
        if includeDrafts { args.append("-D") }
        if includeFuture { args.append("-F") }
        if includeExpired { args.append("-E") }
        if minify { args.append("--minify") }
        if cleanDestination { args.append("--cleanDestinationDir") }
        if enableGitInfo { args.append("--enableGitInfo") }
        if gc { args.append("--gc") }
        if renderToMemory { args.append("-M") }
        if !environment.isEmpty { args += ["-e", environment] }
        if !baseURLOverride.isEmpty { args += ["-b", baseURLOverride] }

        let commandLine = "hugo " + args.joined(separator: " ")
        engine.log(.command, commandLine)

        var collected = ""
        let result = await HFH.run(args, workingDirectory: root) { line in
            collected += line + "\n"
            Task { @MainActor in
                self.output = line
                if line.contains("ERROR") || line.contains("Error:") {
                    engine.log(.error, line)
                } else if line.contains("WARN") {
                    engine.log(.warning, line)
                } else {
                    engine.log(.info, line)
                }
            }
        }
        output = collected

        guard let result else {
            lastResult = .failure("Hugo binary not found")
            return lastResult
        }

        // A Hugo build can exit 0 while still reporting errors in the output, so
        // check the text as well as the exit code.
        let hasError = result.combined.contains("ERROR")
        if result.succeeded && !hasError && result.looksLikeSuccessfulBuild {
            let pages = Self.parsePages(result.combined)
            let duration = Self.parseDuration(result.combined)
            lastResult = .success(pages: pages, duration: duration)
            engine.log(.success, "Built \(pages) pages in \(duration)")
            engine.scanContent()
        } else {
            let message = Self.firstError(in: result.combined) ?? "Build failed (status \(result.status))"
            lastResult = .failure(message)
            engine.log(.error, message)
        }
        return lastResult
    }

    // These parse Hugo's output text and have no state, so they are safe to call
    // from anywhere — including tests, which are not on the main actor.
    nonisolated static func parsePages(_ text: String) -> Int {
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: "│").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0] == "Pages", let n = Int(parts[1]) { return n }
        }
        return 0
    }

    nonisolated static func parseDuration(_ text: String) -> String {
        for line in text.components(separatedBy: "\n") where line.contains("Total in") {
            if let range = line.range(of: "Total in") {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return "—"
    }

    nonisolated static func firstError(in text: String) -> String? {
        for line in text.components(separatedBy: "\n") where line.contains("ERROR") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Everything `hugo list` can tell us, exposed as UI-friendly counts.
    func contentInventory(root: URL) async -> Inventory {
        var inventory = Inventory()
        guard let result = HFH.runSync(["list", "all"], workingDirectory: root) else { return inventory }
        inventory.all = Self.countRows(result.standardOutput)
        if let drafts = HFH.runSync(["list", "drafts"], workingDirectory: root) {
            inventory.drafts = Self.countRows(drafts.standardOutput)
        }
        if let future = HFH.runSync(["list", "future"], workingDirectory: root) {
            inventory.future = Self.countRows(future.standardOutput)
        }
        if let published = HFH.runSync(["list", "published"], workingDirectory: root) {
            inventory.published = Self.countRows(published.standardOutput)
        }
        return inventory
    }

    /// `hugo list` prints a CSV with a header row.
    nonisolated static func countRows(_ csv: String) -> Int {
        let lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return max(0, lines.count - 1)
    }

    struct Inventory: Equatable {
        var all = 0
        var drafts = 0
        var future = 0
        var published = 0
    }
}
