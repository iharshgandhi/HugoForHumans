// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Locates the Hugo executable.
///
/// Priority order:
///  1. A binary the user already has on PATH (so power users keep their own version).
///  2. The copy bundled inside the app bundle (Contents/Resources/bin/hugo).
///     This is what makes the .dmg self-contained: no Homebrew, no Go, no setup.
///  3. A previously downloaded copy in the app's support directory.
enum HugoBinary {

    static let bundledRelativePath = "Resources/bin/hugo"

    static var bundledURL: URL? {
        // The binary sits next to the executable inside a .app bundle.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var bundleRoot = executable.deletingLastPathComponent()
        // Walk up looking for Contents/Resources — handles both the .app and dev builds.
        for _ in 0..<4 {
            let candidate = bundleRoot.appendingPathComponent("Resources/bin/hugo")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            bundleRoot = bundleRoot.deletingLastPathComponent()
        }
        return nil
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HugoForHumans", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        "/opt/homebrew/sbin", "/usr/local/sbin",
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("go/bin").path,
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin").path,
    ]

    /// First Hugo found on the user's PATH.
    static func systemURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let pathDirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("hugo")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// The binary the app should use.
    static func resolve() -> URL? {
        // A binary inside a running .app is the most trustworthy: it is the version
        // the app was tested against. A system Hugo wins only when it is extended,
        // because non-extended builds cannot compile SCSS and many themes need it.
        if let system = systemURL() {
            if let v = version(of: system), v.contains("extended") {
                return system
            }
        }
        if let bundled = bundledURL { return bundled }
        return systemURL()
    }

    /// `hugo version` output, or nil when the binary will not run.
    ///
    /// This deliberately calls `HFH.syncRun` with an explicit path rather than
    /// `HFH.runSync`. `runSync` resolves the binary first, and `resolve()` asks
    /// us for its version — going through it here recurses until the stack dies.
    static func version(of url: URL) -> String? {
        guard let result = HFH.syncRun([url.path, "version"], workingDirectory: nil),
              result.status == 0 else { return nil }
        let text = (result.standardOutput + result.standardError).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The version number on its own — `0.166.0`, not the whole `hugo version` line.
    ///
    /// `hugo version` prints `hugo v0.166.0-78400b4de8adc992…+extended darwin/arm64 …`,
    /// so a naive "first space-separated token" keeps the build hash with it and
    /// produces unreadable strings in the UI.
    static func shortVersion(of url: URL? = nil) -> String? {
        guard let raw = version(of: url ?? resolve() ?? URL(fileURLWithPath: "/")) else { return nil }
        // Drop the leading "hugo", then keep the vX.Y.Z prefix of the next token.
        let token = raw.split(separator: " ").dropFirst().first.map(String.init) ?? raw
        let cleaned = token.hasPrefix("v") ? String(token.dropFirst()) : token
        let number = cleaned.prefix { $0.isNumber || $0 == "." }
        return number.isEmpty ? cleaned : String(number)
    }

    /// Human label for the engine, e.g. "0.166.0 (extended)".
    static func displayVersion(of url: URL? = nil) -> String? {
        guard let target = url ?? resolve(), let short = shortVersion(of: target) else { return nil }
        let kind = version(of: target)?.contains("extended") == true ? "extended" : "standard"
        return "\(short) (\(kind))"
    }

    static var isExtended: Bool {
        guard let url = resolve(), let v = version(of: url) else { return false }
        return v.contains("extended")
    }
}
