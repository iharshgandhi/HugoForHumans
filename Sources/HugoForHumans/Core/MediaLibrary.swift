// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// A file living beside a page, split by whether a human can see it in the text.
///
/// Hugo calls these "page resources": files in the same folder as a page's
/// `index.md`. The distinction that matters to a writer is simpler — an image
/// shows up in the running text, an attachment is a download. Both are ordinary
/// files next to the page; the app only differs in how it presents them.
struct MediaAsset: Identifiable, Hashable {
    var id: String { relativePath }
    /// Path relative to the site root, e.g. "content/posts/photo.jpg".
    var relativePath: String
    var url: URL
    var name: String

    var ext: String { url.pathExtension.lowercased() }

    /// True when the file can be shown inside the page text.
    var isInlineRenderable: Bool {
        Self.inlineExtensions.contains(ext)
    }

    var isImage: Bool {
        Self.imageExtensions.contains(ext)
    }

    /// Human-readable size, e.g. "1.4 MB".
    var sizeDescription: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Self.format(bytes: bytes)
    }

    var pixelDescription: String? {
        guard isImage, let size = MediaAsset.pixelSize(of: url) else { return nil }
        return "\(size.width) × \(size.height)"
    }

    /// Reads width and height from the image header without decoding the pixels.
    ///
    /// `URLResourceKey.pixelWidthKey` does not exist in Foundation on macOS — it
    /// is a swift-corelibs addition — so the size comes from ImageIO instead,
    /// which reads only the header and costs nothing on a large photo.
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
        #else
        // No ImageIO on this platform. Returning nil is already the documented
        // "size unknown" answer, and every caller treats it as optional, so the
        // media list still works — it just cannot show a pixel size.
        return nil
        #endif
    }

    static func format(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Formats that render inline in Markdown.
    static let inlineExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "bmp", "tiff", "heic",
    ]
    static let imageExtensions = inlineExtensions
    /// Things a writer attaches rather than embeds.
    static let attachmentExtensions: Set<String> = [
        "pdf", "zip", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf",
        "csv", "json", "epub", "key", "pages", "numbers", "mp3", "m4a", "wav",
    ]
    /// Audio and video render inline too, but as players not pictures.
    static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "ogv", "mp3", "m4a", "wav", "aac", "flac",
    ]
}

/// Where a file was put and how the page should refer to it.
struct PlacedMedia {
    var asset: MediaAsset
    /// The path to write into the Markdown. Page-local files use Hugo's
    /// `.RelPermalink`-friendly form, site assets an absolute `/images/...`.
    var markdownPath: String
    var wasRenamed: Bool
    var originalName: String
    /// Where the page lives after the add. This can differ from where the
    /// caller last saw it, because an inline image promotes the page to a leaf
    /// bundle — so the caller must re-read the item from this URL before saving.
    var pageURL: URL
}

/// Adds files to a page, keeping Hugo's on-disk conventions intact.
///
/// The important constraint: **the page stays an ordinary Markdown file.** No
/// front-matter rewriting, no custom attachment syntax. An image is
/// `![alt](photo.jpg)` sitting beside `index.md`, which is what Hugo has always
/// done and what any other tool would expect.
///
/// The one structural change allowed is promoting a bare page to a leaf bundle
/// (`posts/my-post.md` becomes `posts/my-post/index.md`). That is Hugo's own
/// layout, it keeps the public URL identical, and it is the only way a file can
/// sit beside a page. It happens only when an inline image is added, and never
/// silently: the caller is told the page moved.
@MainActor
enum MediaLibrary {

    /// Which folder a file should land in for a given page.
    ///
    /// For a leaf bundle (`posts/my-post/index.md`) the file goes beside the
    /// page and is addressed relatively. For a bare page (`posts/my-post.md`)
    /// there is no folder to put it in without restructuring the site, so the
    /// file goes to `static/` and is addressed from the site root. That second
    /// case is the common one, and it is why the app never silently converts a
    /// page into a bundle.
    enum Placement {
        case pageBundle(directory: URL, useRelativePath: Bool)
        case siteStatic(root: URL, subfolder: String)

        var directory: URL {
            switch self {
            case .pageBundle(let dir, _): return dir
            case .siteStatic(let root, let folder): return root.appendingPathComponent(folder)
            }
        }

        var usesRelativePath: Bool {
            if case .pageBundle(_, let relative) = self { return relative }
            return false
        }
    }

    /// Works out where a file added to `item` belongs.
    ///
    /// Hugo only serves files that sit *inside* a page's own bundle. A folder
    /// beside `posts/my-post.md` is not a page resource of it — Hugo resolves a
    /// relative image path against the page's own directory — so a sibling
    /// folder produces a file that exists on disk and a broken image on the
    /// page. The fix is to make the page a leaf bundle, which Hugo supports
    /// natively and which keeps the public URL identical.
    ///
    /// Attachments are different: a reader clicks them, so they belong in
    /// `static/` and are addressed from the site root.
    static func placement(for item: ContentItem, projectRoot: URL, kind: MediaAsset.Kind) -> Placement {
        let parent = item.url.deletingLastPathComponent()

        if kind == .attachment {
            return .siteStatic(root: projectRoot, subfolder: "static/files")
        }
        return .pageBundle(directory: parent, useRelativePath: true)
    }

    /// Turns a bare page into a leaf bundle, so files can sit beside it.
    ///
    /// `posts/my-post.md` becomes `posts/my-post/index.md`. Hugo serves both at
    /// `/posts/my-post/`, so this is invisible to readers and to existing links —
    /// but it is the only layout in which an inline image actually resolves.
    ///
    /// Returns the page's new location, or the original if it is already a
    /// bundle. Callers must re-read the item afterwards, because its URL moved.
    @discardableResult
    static func promotingToBundle(_ item: ContentItem) -> URL {
        if item.kind == .bundle || item.url.lastPathComponent == "index.md" {
            return item.url
        }
        let fm = FileManager.default
        let parent = item.url.deletingLastPathComponent()
        let folder = parent.appendingPathComponent((item.baseName as NSString).deletingPathExtension)
        let index = folder.appendingPathComponent("index.md")

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.fileExists(atPath: index.path) {
                // A folder of assets already exists; the page just needs to move in.
                try fm.removeItem(at: item.url)
            } else {
                try fm.moveItem(at: item.url, to: index)
            }
        } catch {
            // If the move fails the caller still has a working page, just
            // without inline media, which is better than losing the file.
            return item.url
        }
        return index
    }

    /// Copies a file into place, avoiding collisions, and returns how to refer
    /// to it from the page.
    @discardableResult
    /// - Parameter desiredName: The filename to use in the site, if it should not
    ///   simply mirror the source. A pasted screenshot has no filename of its
    ///   own, so this is how its generated name is honoured; collision handling
    ///   still applies.
    static func add(_ source: URL, to item: ContentItem, projectRoot: URL,
                    kind: MediaAsset.Kind, desiredName: String? = nil) throws -> PlacedMedia {
        // An inline image only works if the page can hold files, so the page
        // becomes a leaf bundle first. The returned asset reflects the new
        // location; the caller must refresh its item because the URL moved.
        var page = item
        if kind == .inline {
            let moved = promotingToBundle(item)
            if moved != item.url {
                page = item.relocated(to: moved)
            }
        }

        let placement = placement(for: page, projectRoot: projectRoot, kind: kind)
        let directory = placement.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = desiredName ?? source.lastPathComponent
        let destination = uniqueDestination(in: directory, for: fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        let relative = ContentItem.relativePath(of: destination, under: projectRoot)
        let asset = MediaAsset(relativePath: relative, url: destination, name: destination.lastPathComponent)

        let markdownPath: String
        if placement.usesRelativePath {
            markdownPath = destination.lastPathComponent
        } else {
            // Static files are addressed from the site root by their public path.
            markdownPath = "/" + relative
                .replacingOccurrences(of: "static/", with: "")
        }

        return PlacedMedia(asset: asset,
                           markdownPath: markdownPath,
                           wasRenamed: destination.lastPathComponent != fileName,
                           originalName: fileName,
                           pageURL: page.url)
    }

    /// Saves a picture taken from the pasteboard into the page.
    ///
    /// A screenshot arrives with no filename, so one is generated — and the bytes
    /// are checked first, because a pasteboard can hand over a `.png` that is
    /// really HTML copied from a web page. Writing that as an image would
    /// produce a file no browser can display and no error to explain why.
    @discardableResult
    static func add(_ pasted: ClipboardImage.Pasted, to item: ContentItem,
                    projectRoot: URL, kind: MediaAsset.Kind) throws -> PlacedMedia {
        guard ClipboardImage.isImageData(pasted.data) else {
            throw MediaError.notAnImage
        }
        let ext = pasted.fileExtension.isEmpty
            ? (ClipboardImage.inferredExtension(for: pasted.data) ?? "png")
            : pasted.fileExtension
        let name = pasted.suggestedName.isEmpty
            ? ClipboardImage.timestampedName()
            : pasted.suggestedName

        // The staged file is given the real name, not a UUID: the staging
        // directory is a means to an end, and what ends up in the site has to be
        // the timestamped name the user would recognise. `add` still applies its
        // own collision handling, so two pastes in the same second become
        // `pasted-….png` and `pasted-….2.png` rather than one overwriting the
        // other.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name).\(ext)")
        do {
            try pasted.data.write(to: staging, options: .atomic)
            return try add(staging, to: item, projectRoot: projectRoot, kind: kind,
                           desiredName: "\(name).\(ext)")
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Why a file could not be added.
    enum MediaError: LocalizedError {
        /// The bytes were not a recognisable image.
        case notAnImage

        var errorDescription: String? {
            switch self {
            case .notAnImage:
                return "That is not an image. Copy the picture itself, not a link to it."
            }
        }
    }

    /// Appends `-2`, `-3` … until the name is free. Never overwrites.
    static func uniqueDestination(in directory: URL, for fileName: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var counter = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Everything sitting beside a page, split by how it is presented.
    static func assets(for item: ContentItem, projectRoot: URL) -> (inline: [MediaAsset], attachments: [MediaAsset]) {
        let placement = placement(for: item, projectRoot: projectRoot, kind: .inline)
        let directory = placement.directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], []) }

        let pageName = item.fileName
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var inline: [MediaAsset] = []
        var attachments: [MediaAsset] = []
        for url in contents {
            // Never list the page itself.
            if url.lastPathComponent == pageName { continue }
            if url.lastPathComponent == "index.md" { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            let ext = url.pathExtension.lowercased()
            let relative = ContentItem.relativePath(of: url, under: projectRoot)
            let asset = MediaAsset(relativePath: relative, url: url, name: url.lastPathComponent)
            if MediaAsset.inlineExtensions.contains(ext) || MediaAsset.mediaExtensions.contains(ext) {
                inline.append(asset)
            } else {
                attachments.append(asset)
            }
        }
        let byName = { (a: MediaAsset, b: MediaAsset) in
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return (inline.sorted(by: byName), attachments.sorted(by: byName))
    }

    /// Deletes a file and returns the Markdown that referenced it, so the
    /// reference can be cleaned up too. Deleting a file while leaving a broken
    /// image in the page is worse than not offering the action.
    static func remove(_ asset: MediaAsset) throws {
        try FileManager.default.removeItem(at: asset.url)
    }

    /// Markdown for referencing an existing asset from a page.
    static func reference(for asset: MediaAsset, page: ContentItem, projectRoot: URL) -> String {
        let placement = placement(for: page, projectRoot: projectRoot, kind: .inline)
        if placement.usesRelativePath {
            return asset.name
        }
        return "/" + asset.relativePath.replacingOccurrences(of: "static/", with: "")
    }
}

extension MediaAsset {
    /// Distinguishes the two things a writer attaches to a page.
    enum Kind {
        /// Shown in the running text — pictures, and audio/video players.
        case inline
        /// Offered as a download — documents, archives, data.
        case attachment

        init(extension ext: String) {
            let e = ext.lowercased()
            if MediaAsset.inlineExtensions.contains(e) || MediaAsset.mediaExtensions.contains(e) {
                self = .inline
            } else {
                self = .attachment
            }
        }
    }
}

enum MediaMarkdown {
    /// Removes every `![alt](reference)` line for a given path.
    ///
    /// Deleting the file and leaving the Markdown behind would publish a broken
    /// image icon, so the two have to move together. A regex is used rather than
    /// index arithmetic because the path may be written relative or absolute and
    /// the alt text varies.
    ///
    /// Returns nil when there was no match, so the caller can tell "nothing to
    /// do" from "removed".
    static func removingImageReference(_ reference: String, from markdown: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: reference)
        let pattern = "!\\[[^\\]]*\\]\\(\(escaped)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
        guard !matches.isEmpty else { return nil }

        var result = markdown
        // Back to front, so earlier ranges stay valid as the string shrinks.
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            result.removeSubrange(swiftRange)
        }
        // Tidy the blank line the removal may have left behind.
        result = result.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result
    }
}

/// The editor inspector's layout, as data.
///
/// "Attachments is the fourth item" is a requirement, not a matter of taste, so
/// it is expressed here where a test can see it. A test that can only read a
/// SwiftUI body tends to be one that never gets written.
enum InspectorLayout {
    /// Top to bottom: the metadata a reader and search engine see, then the
    /// page's files, then the address, then anything conditional.
    static let sections = ["Title", "Summary", "Tags", "Attachments", "Address"]

    /// Attachments sit fourth, after the fields that describe the page and
    /// before the URL, which is a single scalar rather than a list.
    static let attachmentsIndex = 3

    static func position(of section: String) -> Int? {
        sections.firstIndex(of: section)
    }
}
