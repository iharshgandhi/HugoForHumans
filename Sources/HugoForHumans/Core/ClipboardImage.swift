// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

/// Reads images off the system pasteboard, including screenshots.
///
/// A screenshot is the common case and the awkward one: the OS hands over raw
/// pixels with no filename, no extension and no hint of what it was, so the file
/// has to be given a name and a format here. Everything else — a file copied in
/// Finder, an image dragged from a browser — arrives with enough information to
/// keep its own name and type.
enum ClipboardImage {

    /// One image taken from the pasteboard.
    struct Pasted {
        /// The bytes, in a format that can be written to disk.
        var data: Data
        /// The file extension to use, without a dot, e.g. `png`.
        var fileExtension: String
        /// A name for the file, without an extension. Never empty.
        var suggestedName: String
    }

    /// Everything on the pasteboard that can be saved as an image.
    ///
    /// Both sources are checked: a copied file arrives as a URL, and a screenshot
    /// arrives as raw image data. Reading only the first is why pasting a
    /// screenshot used to do nothing.
    static func images() -> [Pasted] {
        var found: [Pasted] = []

        // 1. Files copied in Finder or from another app.
        //
        // `NSFilenamesPboardType` is the historical name; the modern
        // `public.file-url` carries the same information and survives more apps.
        let fileURLs = readFileURLs()
        for url in fileURLs {
            if let pasted = fromFile(url) { found.append(pasted) }
        }

        // 2. Raw image data — a screenshot, or an image copied as bytes.
        if let pasted = fromRawData() {
            found.append(pasted)
        }
        return found
    }

    /// The first image on the pasteboard, or nil.
    static func first() -> Pasted? { images().first }

    /// Whether there is anything worth handling, so a menu item can grey out.
    static var hasImage: Bool { !images().isEmpty }

    // MARK: - Sources

    private static func readFileURLs() -> [URL] {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []

        if let modern = pasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            urls.append(contentsOf: modern)
        }
        if urls.isEmpty, let legacy = pasteboard.propertyList(forType: NSPasteboard.PasteboardType.fileURL) as? [String] {
            urls.append(contentsOf: legacy.map { URL(fileURLWithPath: $0) })
        }
        return urls
    }

    private static func fromFile(_ url: URL) -> Pasted? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.isEmpty
            ? (inferredExtension(for: data) ?? "")
            : url.pathExtension
        guard !ext.isEmpty else { return nil }
        var name = url.deletingPathExtension().lastPathComponent
        if name.isEmpty { name = timestampedName() }
        return Pasted(data: data, fileExtension: ext, suggestedName: name)
    }

    /// Reads a screenshot, or an image some app put on the pasteboard as bytes.
    ///
    /// `NSPasteboard` exposes image types as `Data` rather than as an object, so
    /// the UTIs are probed in turn and the first that yields data is used. The
    /// order matters: PNG and TIFF are checked before anything that would
    /// re-encode, because re-encoding a screenshot loses fidelity for no gain.
    private static func fromRawData() -> Pasted? {
        let pasteboard = NSPasteboard.general

        let preferred = [
            "public.png",
            "public.tiff",
            UTType.jpeg.identifier,
            UTType.heic.identifier,
            UTType.gif.identifier,
        ]
        for type in preferred {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)),
               !data.isEmpty {
                // Trust the declared type, but confirm it looks like an image —
                // a pasteboard can lie, and a .png containing HTML is a real
                // thing on the web.
                guard isImageData(data),
                      let ext = extForUTI(type) ?? inferredExtension(for: data),
                      !ext.isEmpty else { continue }
                return Pasted(data: data, fileExtension: ext, suggestedName: timestampedName())
            }
        }

        // Some apps only expose a TIFF-backed NSImage.
        if let image = NSImage(pasteboard: pasteboard) {
            if let tiff = image.tiffRepresentation, isImageData(tiff) {
                return Pasted(data: tiff, fileExtension: "tiff", suggestedName: timestampedName())
            }
        }
        return nil
    }

    // MARK: - Naming

    /// A name for a screenshot, which has none of its own.
    ///
    /// Timestamped so repeated pastes do not collide, and so the order in a
    /// folder matches the order they were taken.
    static func timestampedName(now: Date = Date(),
                                formatter: DateFormatter? = nil,
                                timeZone: TimeZone = .current) -> String {
        let formatter = formatter ?? defaultFormatter()
        // The zone is applied unconditionally: a formatter built elsewhere may
        // already carry a different one, and the name is written to disk, so it
        // has to be predictable rather than merely local.
        formatter.timeZone = timeZone
        return "pasted-" + formatter.string(from: now)
    }

    private static func defaultFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        // Sortable and filesystem-safe: `pasted-2026-09-26-204512`.
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }

    // MARK: - Format detection

    /// The file extension implied by a UTI.
    static func extForUTI(_ uti: String) -> String? {
        if let type = UTType(uti), let ext = type.preferredFilenameExtension { return ext }
        // A few types are common enough to be worth naming directly, because
        // their identifiers are not round-trippable.
        switch uti {
        case "public.png": return "png"
        case "public.tiff": return "tiff"
        default: return nil
        }
    }

    /// The extension implied by the file's own magic bytes.
    ///
    /// Used when the pasteboard gives a type this code does not recognise, and
    /// for files with no extension at all.
    static func inferredExtension(for data: Data) -> String? {
        let first = Array(data.prefix(12))
        // PNG: 89 50 4E 47
        if first.count >= 4, first[0] == 0x89, first[1] == 0x50,
           first[2] == 0x4E, first[3] == 0x47 { return "png" }
        // JPEG: FF D8 FF
        if first.count >= 3, first[0] == 0xFF, first[1] == 0xD8, first[2] == 0xFF { return "jpg" }
        // GIF: "GIF8"
        if first.count >= 4, first[0] == 0x47, first[1] == 0x49,
           first[2] == 0x46, first[3] == 0x38 { return "gif" }
        // TIFF: "II*\0" little-endian or "MM\0*" big-endian.
        if first.count >= 4,
           (first[0] == 0x49 && first[1] == 0x49 && first[2] == 0x2A && first[3] == 0x00)
            || (first[0] == 0x4D && first[1] == 0x4D && first[2] == 0x00 && first[3] == 0x2A) {
            return "tiff"
        }
        // WebP: "RIFF" .... "WEBP"
        if first.count >= 12, first[0] == 0x52, first[1] == 0x49, first[2] == 0x46, first[3] == 0x46,
           first[8] == 0x57, first[9] == 0x45, first[10] == 0x42, first[11] == 0x50 { return "webp" }
        // HEIC/AVIF share an ISO-BMFF container; the brand follows the box size.
        if first.count >= 12, first[4] == 0x66, first[5] == 0x74, first[6] == 0x79, first[7] == 0x70 {
            let brand = String(bytes: first[8..<12], encoding: .ascii) ?? ""
            if brand == "heic" || brand == "heix" || brand == "mif1" { return "heic" }
            if brand == "avif" || brand == "avis" { return "avif" }
        }
        return nil
    }

    /// Whether the bytes look like an image we can write out.
    static func isImageData(_ data: Data) -> Bool {
        // A header is at most 12 bytes, so requiring more than that would reject
        // every file that carries nothing but a header.
        guard data.count >= 8 else { return false }
        return inferredExtension(for: data) != nil
    }
}
#endif  // canImport(AppKit)
