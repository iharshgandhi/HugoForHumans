// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

struct CommandResult {
    var status: Int32
    var standardOutput: String
    var standardError: String

    var combined: String { standardOutput + standardError }
    var succeeded: Bool { status == 0 }
    /// True when Hugo's build table was printed, i.e. the build really happened.
    var looksLikeSuccessfulBuild: Bool { combined.contains("Total in") }
}

/// Gathers the streamed lines from a command's two pipes into one result.
///
/// Two tasks append at once — stdout and stderr are read concurrently — so this
/// uses a lock rather than plain properties.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""

    func append(_ line: String, isError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if isError {
            err += line + "\n"
        } else {
            out += line + "\n"
        }
    }

    var standardOutput: String {
        lock.lock(); defer { lock.unlock() }
        return out
    }

    var standardError: String {
        lock.lock(); defer { lock.unlock() }
        return err
    }
}

enum HFH {

    /// Blocking run, used at startup and in tests.
    static func runSync(_ arguments: [String], workingDirectory: URL?) -> CommandResult? {
        guard let hugo = HugoBinary.resolve() else { return nil }
        return syncRun([hugo.path] + arguments, workingDirectory: workingDirectory)
    }

    @discardableResult
    static func syncRun(_ launchPath: [String], workingDirectory: URL?) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath[0])
        process.arguments = Array(launchPath.dropFirst())
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        // Hugo needs a writable cache and a predictable locale regardless of how the
        // user launched us (Finder, Terminal, Spotlight).
        process.environment = baseEnvironment()

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, standardOutput: "", standardError: error.localizedDescription)
        }

        // Drain both pipes concurrently: a child that fills one pipe's buffer while
        // we block on the other would deadlock.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hfh.pipe", attributes: .concurrent)
        queue.async(group: group) { outData = out.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = err.fileHandleForReading.readDataToEndOfFile() }
        process.waitUntilExit()
        group.wait()

        return CommandResult(status: process.terminationStatus,
                             standardOutput: String(decoding: outData, as: UTF8.self),
                             standardError: String(decoding: errData, as: UTF8.self))
    }

    /// Async run with streamed output line by line, for anything with a progress bar.
    static func run(_ arguments: [String],
                    workingDirectory: URL?,
                    onOutput: @escaping (String) -> Void) async -> CommandResult? {
        guard let hugo = HugoBinary.resolve() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hugo.path)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        process.environment = baseEnvironment()

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Set the handler before `run()` so there is no window in which a fast
        // process exits before anyone is listening.
        //
        // The exit is awaited through this semaphore rather than
        // `waitUntilExit()`. That call spins the current run loop, and a
        // command-line `@main` has none — it blocked forever. A handler is
        // delivered on a dispatch queue, so it works in every context.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch {
            return CommandResult(status: -1, standardOutput: "", standardError: error.localizedDescription)
        }

        // Accumulate the streamed lines so the result carries the real output.
        // `HFH.lines` yields each line, so appending here keeps one copy of the
        // text without a second pass over the pipes.
        let collector = OutputCollector()

        // The pipes are drained concurrently, so a child filling one buffer
        // while we block on the other cannot deadlock. Both reach EOF when the
        // child exits, so awaiting the group also waits for completion.
        await withTaskGroup(of: Void.self) { group in
            for pipe in [out, err] {
                let isError = pipe === err
                group.addTask {
                    for await line in HFH.lines(of: pipe) {
                        onOutput(line)
                        collector.append(line, isError: isError)
                    }
                }
            }
        }

        // Normally already signalled by the time the pipes hit EOF; waiting
        // guarantees terminationStatus is final before it is read.
        exited.wait()

        // The caller needs the text, not just the live feed: Builder decides
        // success by looking for Hugo's build table in the output. Returning an
        // empty result here made every streamed build look like a failure.
        return CommandResult(status: process.terminationStatus,
                             standardOutput: collector.standardOutput,
                             standardError: collector.standardError)
    }

    static func lines(of pipe: Pipe) -> AsyncStream<String> {
        AsyncStream { continuation in
            DispatchQueue.global().async {
                let handle = pipe.fileHandleForReading
                var buffer = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        if !buffer.isEmpty {
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                        }
                        break
                    }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        continuation.yield(String(decoding: lineData, as: UTF8.self))
                    }
                }
                continuation.finish()
            }
        }
    }

    static func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Keep Hugo's cache inside the app's own container so a non-GUI launch and a
        // Finder launch agree on the same cache and never fight over a lock file.
        let cache = HugoBinary.supportDirectory.appendingPathComponent("hugo_cache")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        env["HUGO_CACHEDIR"] = cache.path
        env["TMPDIR"] = NSTemporaryDirectory()
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }
}
