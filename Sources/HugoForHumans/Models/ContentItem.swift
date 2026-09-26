// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// One file in the site's content directory.
struct ContentItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case page        // a regular page
        case section     // _index.md — a section landing page
        case bundle      // index.md inside a folder (leaf bundle)
        case asset       // image / pdf / anything non-markdown

        var displayName: String {
            switch self {
            case .page: return "Page"
            case .section: return "Section"
            case .bundle: return "Page Bundle"
            case .asset: return "Media"
            }
        }
    }

    var id: String { relativePath }
    /// Path relative to the content directory, e.g. "posts/hello.md".
    var relativePath: String
    /// Path relative to the project root, e.g. "content/posts/hello.md".
    var projectRelativePath: String { "content/" + relativePath }
    var url: URL
    var kind: Kind
    var frontMatter: FrontMatter

    var fileName: String { (relativePath as NSString).lastPathComponent }
    var baseName: String { (fileName as NSString).deletingPathExtension }
    var ext: String { (fileName as NSString).pathExtension.lowercased() }

    /// Top-level section this item belongs to ("posts"), or "" for the site root.
    var section: String {
        let parts = relativePath.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : ""
    }

    /// The same page, after its file has moved.
    ///
    /// Used when a page is promoted to a leaf bundle: the content is unchanged,
    /// only the path, so the id and the sidebar's selection must be updated too
    /// or the app will keep looking for a file that is no longer there.
    func relocated(to newURL: URL, contentRoot: URL? = nil) -> ContentItem {
        let root = contentRoot ?? url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let newRelative = ContentItem.relativePath(of: newURL, under: root)
        var copy = self
        copy.url = newURL
        copy.relativePath = newRelative
        copy.kind = newURL.lastPathComponent == "index.md" ? .bundle : kind
        // The id is derived from the path, so it has to be recomputed.
        return copy
    }

    /// Folder nesting below the section, used for indented sidebar rows.
    var depth: Int {
        max(0, relativePath.split(separator: "/").count - 2)
    }

    var title: String {
        if kind == .asset { return baseName }
        let t = frontMatter.title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        if kind == .section { return section.isEmpty ? "Home" : baseName.capitalized }
        return baseName.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var isDraft: Bool { kind != .asset && frontMatter.isDraft }
    var isPublished: Bool { !isDraft }

    var subtitle: String {
        switch kind {
        case .asset:
            return ext.uppercased()
        case .section:
            return "\(itemCountDescription) · section"
        default:
            return frontMatter.dateString.isEmpty
                ? kind.displayName
                : Self.formattedDate(frontMatter.dateString)
        }
    }

    private var itemCountDescription: String {
        let words = frontMatter.body.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        return words > 0 ? "\(words) words" : "empty"
    }

    static func formattedDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: iso)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: iso)
        }
        if date == nil {
            let plain = DateFormatter()
            plain.dateFormat = "yyyy-MM-dd"
            date = plain.date(from: String(iso.prefix(10)))
        }
        guard let date else { return iso }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    static func load(from url: URL, projectRoot: URL) -> ContentItem? {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let isText = Self.textExtensions.contains(ext)
        let kind: Kind
        if isText {
            if name == "_index.md" || name == "_index.markdown" {
                kind = .section
            } else if name == "index.md" {
                kind = .bundle
            } else {
                kind = .page
            }
        } else {
            kind = .asset
        }

        let relative = Self.relativePath(of: url, under: projectRoot.appendingPathComponent("content"))

        // Only text files have front matter. Reading a JPEG as UTF-8 fails, and
        // treating that failure as "skip this file" would hide every image from
        // the sidebar — so assets get an empty front matter instead.
        var frontMatter = FrontMatter(format: .toml, values: [], body: "")
        if isText, let raw = try? String(contentsOf: url, encoding: .utf8) {
            frontMatter = FrontMatter.parse(raw)
        }
        return ContentItem(relativePath: relative, url: url, kind: kind, frontMatter: frontMatter)
    }

    /// Extensions Hugo treats as page bundles / pages rather than media.
    static let textExtensions: Set<String> = ["md", "markdown", "mdown", "html", "htm", "asciidoc", "adoc", "org", "rst"]

    static func relativePath(of url: URL, under base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        if fullPath.hasPrefix(basePath) {
            return String(fullPath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}

/// A section (top-level content folder) in the sidebar.
struct ContentSection: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var items: [ContentItem]

    var displayName: String { name.isEmpty ? "Home" : name.capitalized }
    var pageCount: Int { items.filter { $0.kind != .asset }.count }
    var draftCount: Int { items.filter(\.isDraft).count }
    var wordCount: Int { items.reduce(0) { $0 + $1.frontMatter.wordCount } }
}
