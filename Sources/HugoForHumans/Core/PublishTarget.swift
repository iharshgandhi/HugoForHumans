// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// A place a built site can be sent.
///
/// This is the seam that makes connectivity pluggable. Everything the app knows
/// about *pushing a folder of files somewhere* is expressed by this protocol, so
/// adding Netlify, Cloudflare Pages, S3, or a self-hosted scp target means
/// writing one new type — no changes to the app, and no conditionals in the UI.
///
/// ## Adding your own
///
/// ```swift
/// struct NetlifyTarget: PublishTarget {
///     static let descriptor = TargetDescriptor(
///         id: "netlify",
///         name: "Netlify",
///         tagline: "Drag-and-drop hosting with instant deploys",
///         icon: "bolt.horizontal.fill",
///         kind: .hostedService,
///         needsCredentials: true
///     )
///
///     func validate(_ config: DeployConfig) async throws -> [String] { [] }
///     func deploy(_ build: BuildOutput, config: DeployConfig) async throws -> DeployReport { ... }
/// }
/// ```
///
/// Register it once at launch:
///
/// ```swift
/// PublishTargetRegistry.shared.register(NetlifyTarget())
/// ```
///
/// The publish screen builds its list from the registry, so a new target appears
/// with a working form, Keychain-backed credentials, progress, and error
/// reporting without a single edit elsewhere in the app.
protocol PublishTarget: Sendable {

    /// Static identity. The UI is generated from this, so a target that does not
    /// provide one will not render.
    static var descriptor: TargetDescriptor { get }

    /// Checks a configuration before any files move. Returning messages means
    /// "usable, but here is what you should know"; throwing means unusable.
    func validate(_ config: DeployConfig) async throws -> [String]

    /// Sends a built site. Progress is reported through `report` so the same
    /// protocol works for a two-second scp and a ten-minute S3 sync.
    func deploy(_ build: BuildOutput, config: DeployConfig,
                report: @escaping @Sendable (String) -> Void) async throws -> DeployReport
}

/// Static description of a target, used to build the UI generically.
struct TargetDescriptor: Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        /// A hosted service with its own API: GitHub Pages, Netlify, Vercel.
        case hostedService
        /// A web host reached over FTP or SFTP.
        case webHost
        /// Something on the user's own machine or LAN.
        case local

        var displayName: String {
            switch self {
            case .hostedService: return "Hosted service"
            case .webHost: return "Web host"
            case .local: return "On this Mac"
            }
        }

        var symbol: String {
            switch self {
            case .hostedService: return "globe"
            case .webHost: return "server.rack"
            case .local: return "internaldrive"
            }
        }
    }

    var id: String
    var name: String
    var tagline: String
    var icon: String
    var category: Category
    /// Whether the target needs a password or token to work.
    var needsCredentials: Bool
    /// Which credential fields to show, in order. Empty for targets needing none.
    var fields: [CredentialField] = []
    /// Longer explanation, shown under the form.
    var notes: String = ""

    static func == (lhs: TargetDescriptor, rhs: TargetDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One input a target needs, described so the form can be built from it.
struct CredentialField: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case text
        case password
        case toggle
        case choice([String])
    }
    var key: String
    var label: String
    var placeholder: String
    var kind: Kind
    var help: String = ""
    /// For password fields: the Keychain account this is stored under.
    var keychainService: String?

    static func text(_ key: String, _ label: String, placeholder: String = "", help: String = "") -> CredentialField {
        CredentialField(key: key, label: label, placeholder: placeholder, kind: .text, help: help)
    }
    static func secret(_ key: String, _ label: String, service: String, help: String = "") -> CredentialField {
        CredentialField(key: key, label: label, placeholder: "", kind: .password, help: help,
                       keychainService: service)
    }
    static func choice(_ key: String, _ label: String, options: [String]) -> CredentialField {
        CredentialField(key: key, label: label, placeholder: "", kind: .choice(options))
    }
}

/// Non-secret configuration for one site + target pair.
struct DeployConfig: Equatable, Sendable {
    /// Plain values only. Secrets are fetched from the Keychain at deploy time
    /// and never live here, so this struct is safe to log or persist.
    var fields: [String: String] = [:]

    func value(_ key: String) -> String { fields[key] ?? "" }
    func bool(_ key: String, default fallback: Bool = false) -> Bool {
        guard let raw = fields[key] else { return fallback }
        return raw == "true" || raw == "1" || raw == "yes"
    }
    mutating func set(_ key: String, _ value: String) { fields[key] = value }
}

/// The built site handed to a target.
struct BuildOutput: Sendable {
    /// The `public/` directory Hugo produced.
    var directory: URL
    /// How many files will be sent.
    var fileCount: Int
    var totalBytes: Int
    /// The site title, for targets that want it.
    var siteName: String
    var baseURL: String

    var sizeDescription: String { MediaAsset.format(bytes: totalBytes) }
}

/// What a target reports back.
struct DeployReport: Sendable {
    var targetName: String
    var success: Bool
    /// A URL the site is now live at, when the target knows one.
    var liveURL: String?
    /// Human-readable notes: what was skipped, what was slow, what to do next.
    var notes: [String] = []
    /// The exact command or request that was issued, shown in the UI so the
    /// operation is never a black box.
    var commandSummary: String = ""
    var duration: String = ""
}

/// Errors a target can throw, so the UI can show something better than "failed".
enum DeployError: LocalizedError {
    case notConfigured(String)
    case missingCredential(String)
    case authenticationFailed(String)
    case transferFailed(String)
    case buildMissing
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what):
            return "This target still needs \(what)."
        case .missingCredential(let what):
            return "No stored password for \(what). Add it in the connection settings."
        case .authenticationFailed(let detail):
            return "The host rejected those credentials. \(detail)"
        case .transferFailed(let detail):
            return "The files could not be uploaded. \(detail)"
        case .buildMissing:
            return "Build the site first — there is nothing to publish yet."
        case .cancelled:
            return "Cancelled."
        }
    }
}

/// Every target the app knows about.
///
/// Targets register themselves at launch. A third-party target is a single
/// `PublishTarget` conformance plus one `register` call, which is the whole
/// integration surface.
@MainActor
final class PublishTargetRegistry: ObservableObject {
    static let shared = PublishTargetRegistry()

    @Published private(set) var targets: [PublishTarget] = []

    private init() {}

    func register(_ target: PublishTarget) {
        let id = type(of: target).descriptor.id
        targets.removeAll { type(of: $0).descriptor.id == id }
        targets.append(target)
    }

    func registerBuiltIns() {
        register(LocalFolderTarget())
        register(GitHubPagesTarget())
        register(WebHostTarget())
    }

    func target(withID id: String) -> PublishTarget? {
        targets.first { type(of: $0).descriptor.id == id }
    }

    var grouped: [(category: TargetDescriptor.Category, targets: [PublishTarget])] {
        TargetDescriptor.Category.allCases.compactMap { category in
            let matching = targets.filter { type(of: $0).descriptor.category == category }
            return matching.isEmpty ? nil : (category, matching)
        }
    }
}

// MARK: - Configuration storage

/// Remembers which target each site uses and what was typed into the form.
///
/// Secrets are deliberately excluded: this writes a JSON file next to the
/// project's `.hugo-for-humans/` directory containing only non-secret values.
/// Nothing here should ever be committed, and `.gitignore` is written for it.
struct DeploySettingsStore {
    static let directoryName = ".hugo-for-humans"
    static let fileName = "deploy.json"

    struct Persisted: Codable {
        var targetID: String = ""
        var config: [String: String] = [:]
    }

    static func settingsURL(for projectRoot: URL) -> URL {
        projectRoot
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func load(for projectRoot: URL) -> Persisted {
        let url = settingsURL(for: projectRoot)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return Persisted()
        }
        return decoded
    }

    @discardableResult
    static func save(_ settings: Persisted, for projectRoot: URL) -> Bool {
        let url = settingsURL(for: projectRoot)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Makes sure the app's own state directory is never committed.
    @discardableResult
    static func ensureGitIgnored(projectRoot: URL) -> Bool {
        let gitignore = projectRoot.appendingPathComponent(".gitignore")
        let marker = "/\(directoryName)/"
        if let existing = try? String(contentsOf: gitignore, encoding: .utf8) {
            guard !existing.contains(marker) else { return true }
            let updated = existing.hasSuffix("\n") ? existing + "\n\(marker)\n" : existing + "\n\n\(marker)\n"
            return (try? updated.write(to: gitignore, atomically: true, encoding: .utf8)) != nil
        }
        return (try? "\(marker)\n".write(to: gitignore, atomically: true, encoding: .utf8)) != nil
    }
}

// MARK: - Shared file walking

enum BuildDirectory {
    /// Every file in a built site, as relative paths. Directories Hugo left
    /// behind (`.nojekyll`, caches) are included: the target decides.
    static func files(in root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [String] = []
        var total = 0
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let relative = ContentItem.relativePath(of: url, under: root)
            if !relative.isEmpty {
                found.append(relative)
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return found.sorted()
    }

    static func totalSize(in root: URL) -> Int {
        files(in: root).reduce(0) { sum, relative in
            sum + ((try? root.appendingPathComponent(relative)
                .resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
