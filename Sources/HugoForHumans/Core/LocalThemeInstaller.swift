// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Installs a theme the user already has, rather than one from the catalogue.
///
/// The catalogue themes arrive over the network, but someone building their own
/// theme — or working offline, or testing a local copy — needs to point the app
/// at a folder or an archive on their disk. The destination is the same
/// `themes/<name>/` a cloned theme would land in, so nothing downstream has to
/// know how it got there.
enum LocalThemeInstaller {

    /// What the user chose to import.
    enum Source {
        /// A folder already in theme shape.
        case directory(URL)
        /// A zip archive, as downloaded from a theme's release page.
        case archive(URL)
    }

    /// Why an import failed, phrased for the person who just clicked Import.
    enum ImportError: LocalizedError {
        case notATheme(String)
        case archiveWithoutThemesDirectory
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notATheme(let name):
                return """
                "\(name)" is not a Hugo theme. A theme folder needs at least one of \
                layouts/, layouts/ with templates, or a theme.toml. Check that the \
                selected folder is the theme itself and not its parent.
                """
            case .archiveWithoutThemesDirectory:
                return """
                That archive has no theme in it. A theme archive normally contains a \
                single top-level folder holding layouts/ — some contain a themes/ \
                folder with one or more themes inside. Unzip it and select the \
                folder that has layouts/ in it.
                """
            case .unreadable(let reason):
                return "Could not read that: \(reason)"
            }
        }
    }

    /// The file types a theme can arrive as.
    static let supportedExtensions: [String] = ["zip", "tar", "gz", "tgz", "tar.gz", "hugo.zip"]

    /// Installs `source` into `projectRoot`, returning the theme's directory.
    @discardableResult
    static func install(_ source: Source, into projectRoot: URL) throws -> URL {
        let themesDir = projectRoot.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)

        switch source {
        case .directory(let url):
            return try installDirectory(url, into: themesDir)
        case .archive(let url):
            return try installArchive(url, into: themesDir)
        }
    }

    /// A theme's name, which Hugo takes from the folder or `theme.toml`.
    static func name(for url: URL) -> String {
        if let toml = try? String(contentsOf: url.appendingPathComponent("theme.toml"), encoding: .utf8),
           let name = tomlValue(toml, key: "name"), !name.isEmpty {
            return sanitize(name)
        }
        return sanitize(url.lastPathComponent)
    }

    /// Whether a folder looks like a Hugo theme.
    ///
    /// Deliberately permissive: a theme is judged by having layouts, because
    /// that is the one thing Hugo cannot do without. A theme with a broken
    /// template still has `layouts/`, and rejecting it here would be wrong —
    /// Hugo's own error is more precise than anything guessed in advance.
    static func isTheme(_ url: URL) -> Bool {
        // A zip made on macOS carries a `__MACOSX/` folder of AppleDouble files
        // that mirrors the real tree. It sorts first alphabetically and its
        // subfolders are named the same as the real ones, so without this check
        // an importer happily installs the resource-fork copy of the theme.
        if url.lastPathComponent == "__MACOSX" { return false }
        let layouts = url.appendingPathComponent("layouts", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: layouts.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return true
        }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("theme.toml").path)
    }

    // MARK: - Folders

    private static func installDirectory(_ url: URL, into themesDir: URL) throws -> URL {
        guard isTheme(url) else {
            throw ImportError.notATheme(url.lastPathComponent)
        }
        let name = name(for: url)
        let destination = uniqueDestination(in: themesDir, for: name)

        // Copy rather than move: the user may be importing a theme that is
        // itself a git working tree, and moving it would take their .git with it
        // and break the thing they are still working on.
        try FileManager.default.copyItem(at: url, to: destination)
        // A `.git` directory would be dead weight in a site that never pushes a
        // theme, and Hugo ignores it. Leaving it would be a surprise, so it goes.
        let gitDir = destination.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            try? FileManager.default.removeItem(at: gitDir)
        }
        return destination
    }

    // MARK: - Archives

    private static func installArchive(_ url: URL, into themesDir: URL) throws -> URL {
        let extracted = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-theme-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            try unarchive(url, to: extracted)

            // Three shapes are common in the wild, in this order of preference:
            //   archive/themes/<name>/   (Hugo's module archives)
            //   archive/themes/<name>.zip (nested zip, so: extract again)
            //   archive/<name>/layouts/  (a plain zip of the theme)
            let nestedThemes = extracted.appendingPathComponent("themes", isDirectory: true)
            if let candidate = try firstTheme(inside: nestedThemes) {
                return try installDirectory(candidate, into: themesDir)
            }
            if let candidate = try firstTheme(inside: extracted) {
                return try installDirectory(candidate, into: themesDir)
            }
            throw ImportError.archiveWithoutThemesDirectory
        } catch {
            try? FileManager.default.removeItem(at: extracted)
            throw error
        }
    }

    /// The first theme-shaped directory, recursing one level at a time.
    ///
    /// A missing directory is not an error: most archives do not have a
    /// `themes/` folder at all, and the caller tries several layouts in turn.
    private static func firstTheme(inside root: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let contents = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        for child in contents.sorted(by: { $0.path < $1.path }) {
            // Skip the macOS resource-fork mirror and the dot-files it contains.
            if child.lastPathComponent == "__MACOSX" || child.lastPathComponent.hasPrefix("._") {
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            if isTheme(child) { return child }
            // One level deeper, for a `themes/x.zip` that itself contains a zip.
            if child.pathExtension.lowercased() == "zip" {
                let inner = FileManager.default.temporaryDirectory
                    .appendingPathComponent("hfh-inner-\(UUID().uuidString)", isDirectory: true)
                try? FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
                if (try? unarchive(child, to: inner)) != nil,
                   let found = try firstTheme(inside: inner) {
                    return found
                }
                try? FileManager.default.removeItem(at: inner)
            }
            if let found = try firstTheme(inside: child) { return found }
        }
        return nil
    }

    /// Expands a zip, a tar, or a tar.gz.
    ///
    /// `Process` rather than a ZIP library: the app bundles no third-party code,
    /// and these three formats cover what theme repositories actually publish.
    private static func unarchive(_ url: URL, to destination: URL) throws {
        let name = url.lastPathComponent.lowercased()

        if name.hasSuffix(".zip") {
            try runUnzip(url, to: destination)
        } else if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            try runTar(url, to: destination, extraArgs: [])
        } else if name.hasSuffix(".tar") {
            try runTar(url, to: destination, extraArgs: [])
        } else {
            throw ImportError.unreadable("\(url.lastPathComponent) is not a zip or tar archive.")
        }
    }

    private static func runUnzip(_ url: URL, to destination: URL) throws {
        // macOS ships no `unzip` guarantee across releases, so fall back to
        // ditto, which is always present and handles zip natively.
        let candidates: [[String]] = [
            ["/usr/bin/unzip", "-q", "-o", url.path, "-d", destination.path],
            ["/usr/bin/ditto", "-x", "-k", url.path, destination.path],
        ]
        for arguments in candidates {
            let tool = URL(fileURLWithPath: arguments[0])
            guard FileManager.default.isExecutableFile(atPath: tool.path) else { continue }
            if (try? run(tool, arguments: Array(arguments.dropFirst()))) == true { return }
        }
        throw ImportError.unreadable("this machine has no way to expand a zip file.")
    }

    private static func runTar(_ url: URL, to destination: URL, extraArgs: [String]) throws {
        let tar = URL(fileURLWithPath: "/usr/bin/tar")
        guard FileManager.default.isExecutableFile(atPath: tar.path) else {
            throw ImportError.unreadable("this machine has no way to expand a tar archive.")
        }
        let arguments = ["-xf", url.path, "-C", destination.path] + extraArgs
        guard (try? run(tar, arguments: arguments)) == true else {
            throw ImportError.unreadable("the archive could not be expanded.")
        }
    }

    private static func run(_ tool: URL, arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let errors = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Names

    /// Keeps a name safe to use as a folder, and recognisable in the gallery.
    static func sanitize(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = lowered.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        var name = String(cleaned)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if name.isEmpty { name = "theme" }
        return name.prefix(60).lowercased()
    }

    /// `themes/name` or `themes/name-2`, never overwriting what is there.
    private static func uniqueDestination(in themesDir: URL, for name: String) -> URL {
        var candidate = themesDir.appendingPathComponent(name, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = themesDir.appendingPathComponent("\(name)-\(counter)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    /// A `key = "value"` line from a theme.toml, without a TOML parser.
    ///
    /// theme.toml is a three-line file written by hand; a parser would be a
    /// dependency for nothing.
    private static func tomlValue(_ text: String, key: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            guard parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }
}
