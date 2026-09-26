// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Turns a pasted URL into the markup a Hugo page needs.
///
/// The rule behind every case here: a writer pastes a link, and the app works out
/// what it is. They should never have to know that a YouTube URL has to be
/// reduced to an eleven-character video ID, or that Twitter needs an oEmbed
/// script. Unrecognised URLs still work — they become a plain link — because
/// silently dropping content is worse than rendering it plainly.
enum EmbedKind: String, CaseIterable {
    case youtube
    case vimeo
    case twitter
    case instagram
    case facebook
    case link

    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .vimeo: return "Vimeo"
        case .twitter: return "X / Twitter"
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .link: return "Link"
        }
    }

    var symbolName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "v.circle.fill"
        case .twitter: return "bird"
        case .instagram: return "camera.fill"
        case .facebook: return "f.circle.fill"
        case .link: return "link"
        }
    }

    /// Whether this kind renders as a visible block rather than as text.
    var isBlock: Bool { self != .link }
}

/// A parsed embed: what it is, and the values needed to render it.
struct Embed: Equatable {
    var kind: EmbedKind
    /// The original URL exactly as pasted, kept for fallbacks and for the link
    /// caption, so nothing is lost if a renderer ever changes.
    var sourceURL: String
    /// Platform-specific identifier: a YouTube video ID, a Vimeo ID, a full
    /// status URL, and so on. Empty for `.link`.
    var identifier: String = ""
    /// Resolved width/height for video embeds, so themes can size them.
    var aspect: Double?

    var isBlock: Bool { kind.isBlock }
}

/// Pure URL analysis. No network, no rendering — which means every branch here
/// is directly testable.
enum EmbedParser {

    /// Analyses a pasted URL. Never fails: an unrecognised host is `.link`.
    static func parse(_ raw: String) -> Embed {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Writers paste a URL that has picked up a trailing period or a Markdown
        // closing paren on the way in. Both are not part of the address.
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,);>\"'"))

        if let id = youtubeID(in: cleaned) {
            return Embed(kind: .youtube, sourceURL: cleaned, identifier: id, aspect: 16.0 / 9.0)
        }
        if let id = vimeoID(in: cleaned) {
            return Embed(kind: .vimeo, sourceURL: cleaned, identifier: id, aspect: 16.0 / 9.0)
        }
        // Host matching is case-insensitive, so compare a lowercased copy, but
        // keep the original casing for anything that ends up in the output.
        let lower = cleaned.lowercased()
        if isTwitter(lower) {
            return Embed(kind: .twitter, sourceURL: cleaned, identifier: cleaned)
        }
        if isInstagram(lower) {
            return Embed(kind: .instagram, sourceURL: cleaned, identifier: cleaned)
        }
        if isFacebook(lower) {
            return Embed(kind: .facebook, sourceURL: cleaned, identifier: cleaned)
        }
        return Embed(kind: .link, sourceURL: cleaned)
    }

    /// True when the text is a single URL, which is what makes auto-conversion
    /// on paste safe. A sentence with a link in it is left alone.
    static func looksLikeBareURL(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" "), !t.contains("\n") else { return false }
        let lower = t.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("www.")
    }

    // MARK: - Platform ID extraction

    /// Accepts every shape YouTube hands out: watch pages, short links,
    /// /embed/ and /shorts/ paths, and a bare 11-character ID.
    ///
    /// The identifier is returned with its **original casing**. YouTube IDs are
    /// case-sensitive, so lowercasing one yields a shortcode that points at a
    /// video which does not exist. Host and path matching is therefore done
    /// against a lowercased copy, while the value extracted comes from the
    /// original string.
    static func youtubeID(in url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else {
            return nil
        }
        for marker in ["youtu.be/", "/embed/", "/shorts/", "v="] {
            guard let markerRange = lower.range(of: marker) else { continue }
            // Both strings are lowercased identically in length and layout, so
            // the offset from the lowercased copy indexes the original directly.
            let start = lower.distance(from: lower.startIndex, to: markerRange.upperBound)
            guard let id = identifier(in: url, startingAt: start) else { continue }
            if isYouTubeID(id) { return id }
        }
        // A bare ID pasted on its own.
        let bare = url.trimmingCharacters(in: .whitespaces)
        if isYouTubeID(bare) { return bare }
        return nil
    }

    /// Reads a run of URL-safe identifier characters starting at `offset`.
    private static func identifier(in url: String, startingAt offset: Int) -> String? {
        let chars = Array(url)
        guard offset <= chars.count else { return nil }
        var out = ""
        var index = offset
        while index < chars.count {
            let ch = chars[index]
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else {
                break
            }
            index += 1
        }
        return out.isEmpty ? nil : out
    }

    static func isYouTubeID(_ text: String) -> Bool {
        // Exactly 11 URL-safe characters. This is the actual YouTube rule and it
        // is what stops "youtu.be/some-page" from being treated as a video.
        text.count == 11 && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func vimeoID(in url: String) -> String? {
        let lower = url.lowercased()
        guard lower.contains("vimeo.com") else { return nil }
        // Vimeo ids are numeric, so case is not a concern here.
        let digits = lower.filter { $0.isNumber }
        // A Vimeo id is a long number; a year in a URL is not enough to be one.
        guard digits.count >= 6 else { return nil }
        return digits
    }

    static func isTwitter(_ url: String) -> Bool {
        guard url.contains("twitter.com") || url.contains("x.com") else { return false }
        return url.contains("/status/")
    }

    static func isInstagram(_ url: String) -> Bool {
        guard url.contains("instagram.com") else { return false }
        return url.contains("/p/") || url.contains("/reel/") || url.contains("/tv/")
    }

    static func isFacebook(_ url: String) -> Bool {
        guard url.contains("facebook.com") || url.contains("fb.watch") else { return false }
        return url.contains("/watch") || url.contains("/posts/") || url.contains("/share")
            || url.contains("/videos/")
    }
}

extension Embed {

    /// The Markdown/HTML to insert into the page.
    ///
    /// Video uses Hugo's built-in `youtube` and `vimeo` shortcodes, which every
    /// theme supports and which render a responsive player with no extra
    /// configuration. The social platforms have no Hugo equivalent, so they emit
    /// the platform's own embed markup — which is exactly what those services
    /// hand out when you use their "share" dialog.
    var markdown: String {
        switch kind {
        case .youtube:
            return "{{< youtube \(identifier) >}}"
        case .vimeo:
            return "{{< vimeo \(identifier) >}}"
        case .twitter:
            return """
            <blockquote class="twitter-tweet"><a href="\(sourceURL)"></a></blockquote>
            <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
            """
        case .instagram:
            return """
            <blockquote class="instagram-media" data-instgrm-permalink="\(sourceURL)"></blockquote>
            <script async src="https://www.instagram.com/embed.js"></script>
            """
        case .facebook:
            return """
            <div class="fb-post" data-href="\(sourceURL)"></div>
            <script async src="https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v19.0"></script>
            """
        case .link:
            let text = (sourceURL as NSString).lastPathComponent
            let label = text.isEmpty || text == sourceURL ? sourceURL : text
            return "[\(label)](\(sourceURL))"
        }
    }

    /// One-line summary for the "what did we just insert?" confirmation.
    var summary: String {
        switch kind {
        case .youtube: return "YouTube video \(identifier)"
        case .vimeo: return "Vimeo video \(identifier)"
        case .twitter: return "X / Twitter post"
        case .instagram: return "Instagram post"
        case .facebook: return "Facebook post"
        case .link: return "Link"
        }
    }
}
