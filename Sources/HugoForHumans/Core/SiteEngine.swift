// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
#if canImport(Combine)
import Combine
#endif

/// A Hugo project on disk, plus everything the UI needs to know about it.
@MainActor
final class SiteEngine: ObservationBase {

    // MARK: - Observable state

    @Published private(set) var root: URL?
    @Published private(set) var config = SiteConfig()
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var installedThemes: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?

    @Published public var log: [LogLine] = []
    @Published public var buildStatus: BuildStatus = .idle
    @Published public var selectedItemID: String?
    @Published public var searchText: String = ""
    @Published public var errorMessage: String?

    enum BuildStatus: Equatable {
        case idle
        case building
        case success(pages: Int, duration: String)
        case failure(String)

        var isBusy: Bool { self == .building }
    }

    struct LogLine: Identifiable, Equatable {
        enum Level: String { case info, success, warning, error, command }
        var id = UUID()
        var level: Level
        var text: String
        var time = Date()
    }

    // MARK: - Init

    init() {}

    var siteName: String {
        config.title.isEmpty ? (root?.lastPathComponent ?? "Untitled Site") : config.title
    }

    var isOpen: Bool { root != nil }

    var contentDirectory: URL? { root?.appendingPathComponent("content") }
    var publicDirectory: URL? { root?.appendingPathComponent("public") }

    // MARK: - Opening and creating sites

    /// Whether a folder is a Hugo project.
    ///
    /// Accepts the project root (`hugo.toml` or the older `config.toml`) and also
    /// `config/_default/`, so a site laid out the modern way is not wrongly
    /// rejected.
    nonisolated static func isHugoSite(_ url: URL) -> Bool {
        let fm = FileManager.default
        // A directory of the right name is not a config file, and this has come
        // up: a half-finished clone can leave the name in place as a folder.
        for name in ["hugo.toml", "config.toml", "config.yaml", "config.json"] {
            var isDirectory: ObjCBool = false
            let candidate = url.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return true
            }
        }
        let modern = url.appendingPathComponent("config/_default")
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: modern.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        return false
    }

    func openSite(at url: URL) {
        root = url
        RecentSites.record(url)
        reloadAll()
        log(.command, "Opened \(url.lastPathComponent)")
    }

    func closeSite() {
        root = nil
        config = SiteConfig()
        items = []
        installedThemes = []
        selectedItemID = nil
        log = []
        buildStatus = .idle
    }

    func reloadAll() {
        guard let root else { return }
        config = SiteConfig.load(root: root)
        installedThemes = Self.themes(in: root)
        scanContent()
    }

    /// Every top-level folder in themes/, which is what Hugo itself treats as installable.
    static func themes(in root: URL) -> [String] {
        let themesDir = root.appendingPathComponent("themes")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: themesDir.path)) ?? []
        return contents.filter { name in
            let path = themesDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
            return exists && isDir.boolValue && !name.hasPrefix(".")
        }.sorted()
    }

    // MARK: - Content scanning

    func scanContent() {
        guard let root, let contentDir = contentDirectory else { return }
        isScanning = true
        defer { isScanning = false; lastScan = Date() }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: contentDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        var found: [ContentItem] = []
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            if url.lastPathComponent.hasPrefix(".") { continue }
            // Draft scaffolding directories Hugo sometimes creates.
            if url.pathExtension.lowercased() == "tmp" { continue }
            if let item = ContentItem.load(from: url, projectRoot: root) {
                found.append(item)
            }
        }
        items = found.sorted { lhs, rhs in
            // Sections first, then pages, then media; alphabetical within each group.
            if lhs.kind != rhs.kind { return order(lhs.kind) < order(rhs.kind) }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private func order(_ kind: ContentItem.Kind) -> Int {
        switch kind {
        case .section: return 0
        case .page, .bundle: return 1
        case .asset: return 2
        }
    }

    /// Content split into top-level sections, the WordPress mental model.
    var sections: [ContentSection] {
        var order: [String] = []
        var buckets: [String: [ContentItem]] = [:]
        for item in items where item.kind != .asset {
            let key = item.section
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { ContentSection(name: $0, items: buckets[$0] ?? []) }
    }

    var filteredItems: [ContentItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.lowercased().contains(query)
                || item.relativePath.lowercased().contains(query)
                || item.frontMatter.body.lowercased().contains(query)
                || item.frontMatter.tags.contains(where: { $0.lowercased().contains(query) })
        }
    }

    func item(withID id: String) -> ContentItem? {
        items.first { $0.id == id }
    }

    var totalWords: Int { items.reduce(0) { $0 + $1.frontMatter.wordCount } }
    var publishedCount: Int { items.filter { !$0.isDraft && $0.kind != .asset }.count }
    var draftCount: Int { items.filter(\.isDraft).count }
    var assetCount: Int { items.filter { $0.kind == .asset }.count }

    // MARK: - Mutations

    func save(_ item: ContentItem) {
        do {
            try item.frontMatter.serialized().write(to: item.url, atomically: true, encoding: .utf8)
            scanContent()
            log(.success, "Saved \(item.fileName)")
        } catch {
            errorMessage = "Could not save \(item.fileName): \(error.localizedDescription)"
            log(.error, "Save failed: \(error.localizedDescription)")
        }
    }

    /// Creates a page through Hugo itself, so archetypes and date/title handling
    /// stay exactly what a terminal user would get.
    @discardableResult
    func createPage(section: String, name: String, kind: String? = nil, force: Bool = false) async -> ContentItem? {
        guard let root else { return nil }
        let safeName = Self.slugify(name)
        guard !safeName.isEmpty else {
            errorMessage = "Give the page a name first."
            return nil
        }
        let isSection = kind == "section"
        let fileName = isSection ? "_index.md" : "\(safeName).md"
        let relative = section.isEmpty ? fileName : "\(section)/\(fileName)"

        log(.command, "hugo new content \(relative)")
        var args = ["new", "content", relative]
        if let kind { args += ["--kind", kind] }
        if force { args.append("--force") }

        // Hugo resolves content relative to the project root, not an arbitrary path.
        let result = await HFH.run(args, workingDirectory: root) { [weak self] line in
            Task { @MainActor in self?.log(.info, line) }
        }
        guard result?.succeeded == true else {
            let message = "Hugo could not create that page."
            errorMessage = message
            log(.error, message)
            return nil
        }
        scanContent()
        let created = items.first { $0.relativePath == relative }
        if let created {
            log(.success, "Created \(created.title)")
        }
        return created
    }

    func delete(_ item: ContentItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            if selectedItemID == item.id { selectedItemID = nil }
            scanContent()
            log(.success, "Deleted \(item.fileName)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDraft(_ item: ContentItem) {
        var updated = item
        updated.frontMatter["draft"] = .bool(!item.isDraft)
        save(updated)
    }

    func rename(_ item: ContentItem, to newName: String) {
        let slug = Self.slugify(newName)
        guard !slug.isEmpty, let root else { return }
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent("\(slug).md")
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            errorMessage = "A file called \(slug).md already exists here."
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            var updated = item
            updated.frontMatter["title"] = .string(newName)
            try updated.frontMatter.serialized().write(to: newURL, atomically: true, encoding: .utf8)
            scanContent()
            selectedItemID = ContentItem.relativePath(of: newURL, under: root.appendingPathComponent("content"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Nonisolated: it is pure string work used by the UI, the creator and tests.
    nonisolated static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let mapped = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return " "
        }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    // MARK: - Media

    /// Copies an image into the page's own folder so Hugo picks it up as a
    /// page resource, or into static/ for site-wide use.
    func addMedia(from source: URL, to item: ContentItem?, asSiteAsset: Bool) {
        guard let root else { return }
        let destinationDirectory: URL
        if asSiteAsset || item == nil {
            destinationDirectory = root.appendingPathComponent("static/images")
        } else {
            destinationDirectory = item!.url.deletingLastPathComponent()
        }
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            var destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            var counter = 1
            while FileManager.default.fileExists(atPath: destination.path) {
                let base = source.deletingPathExtension().lastPathComponent
                destination = destinationDirectory.appendingPathComponent("\(base)-\(counter).\(source.pathExtension)")
                counter += 1
            }
            try FileManager.default.copyItem(at: source, to: destination)
            scanContent()
            log(.success, "Added \(destination.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Settings

    func updateConfig(_ newConfig: SiteConfig) {
        guard let root else { return }
        do {
            try newConfig.write(to: root)
            config = SiteConfig.load(root: root)
            log(.success, "Saved settings")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Logging

    func log(_ level: LogLine.Level, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        log.append(LogLine(level: level, text: trimmed))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    func clearLog() { log.removeAll() }
}

/// Cross-view signals. These live in the library because both the app shell and
/// the views need them, and they must be the same static values.
extension Notification.Name {
    static let hfhShowWelcome = Notification.Name("hfh.showWelcome")
    static let hfhNewPage = Notification.Name("hfh.newPage")
    static let hfhNewSection = Notification.Name("hfh.newSection")
    static let hfhBuild = Notification.Name("hfh.build")
    static let hfhTogglePreview = Notification.Name("hfh.togglePreview")
    static let hfhShowSettings = Notification.Name("hfh.showSettings")
    static let hfhShowPublish = Notification.Name("hfh.showPublish")
    static let hfhDelete = Notification.Name("hfh.delete")
}

enum RecentSites {
    private static let key = "recentSites"

    static func all() -> [URL] {
        UserDefaults.standard.stringArray(forKey: key)?.compactMap(URL.init(string:)) ?? []
    }

    static func record(_ url: URL) {
        var list = all().filter { $0 != url }
        list.insert(url, at: 0)
        UserDefaults.standard.set(list.prefix(10).map(\.absoluteString), forKey: key)
    }

    static func forget(_ url: URL) {
        UserDefaults.standard.set(all().filter { $0 != url }.map(\.absoluteString), forKey: key)
    }
}
