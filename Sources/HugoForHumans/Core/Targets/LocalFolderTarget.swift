// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Copies the built site to a folder the user picks. Always available, needs
/// no account, and is the honest fallback when nothing else is configured.
struct LocalFolderTarget: PublishTarget {

    static let descriptor = TargetDescriptor(
        id: "local-folder",
        name: "A folder on this Mac",
        tagline: "Copy the built site somewhere you choose",
        icon: "folder",
        category: .local,
        needsCredentials: false,
        fields: [
            .text("destination", "Destination folder",
                  placeholder: "~/Sites/my-site-live",
                  help: "The built site is copied here. Existing files of the same name are replaced.")
        ],
        notes: "Useful for a local server, a NAS mount, or handing the folder to another tool."
    )

    func validate(_ config: DeployConfig) async throws -> [String] {
        let path = config.value("destination").trimmingCharacters(in: .whitespaces)
        if path.isEmpty { throw DeployError.notConfigured("a destination folder") }

        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue {
            throw DeployError.notConfigured("a folder — that path is a file")
        }
        var notes: [String] = []
        if !FileManager.default.fileExists(atPath: expanded) {
            notes.append("The folder does not exist yet and will be created.")
        }
        return notes
    }

    func deploy(_ build: BuildOutput, config: DeployConfig,
                report: @escaping @Sendable (String) -> Void) async throws -> DeployReport {
        let started = Date()
        let path = config.value("destination").trimmingCharacters(in: .whitespaces)
        let destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)

        report("Preparing \(destination.path)")
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw DeployError.transferFailed("Could not create the destination: \(error.localizedDescription)")
        }

        let files = BuildDirectory.files(in: build.directory)
        report("Copying \(files.count) files (\(build.sizeDescription))")
        var copied = 0
        for relative in files {
            let from = build.directory.appendingPathComponent(relative)
            let to = destination.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(
                at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            // ditto preserves resource forks and permissions, which naive
            // copying loses. A built site with a mangled .htaccess is a bad day.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [from.path, to.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do { try process.run() } catch {
                throw DeployError.transferFailed("Could not run ditto: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw DeployError.transferFailed("Could not copy \(relative).")
            }
            copied += 1
            if copied % 25 == 0 { report("  \(copied)/\(files.count) files") }
        }

        return DeployReport(
            targetName: Self.descriptor.name,
            success: true,
            liveURL: destination.absoluteString,
            notes: ["Copied \(copied) files to \(destination.path)"],
            commandSummary: "ditto <file> \(destination.path)/<file>",
            duration: Self.format(Date().timeIntervalSince(started))
        )
    }

    static func format(_ seconds: TimeInterval) -> String {
        seconds < 1 ? String(format: "%.0f ms", seconds * 1000) : String(format: "%.1f s", seconds)
    }
}
