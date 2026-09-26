// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// The shortcodes a site needs for the app's own features to work.
///
/// Hugo renders a `{{< shortcode >}}` call by finding a template of that name in
/// `layouts/shortcodes/`. The built-in `youtube` and `vimeo` shortcodes ship
/// with Hugo itself, but there is no equivalent for "run this page's custom
/// script" — so the app installs one into the site.
///
/// Writing it into `layouts/` rather than relying on a theme is the important
/// choice: a theme that does not know about the shortcode still gets the
/// behaviour, because the shortcode is resolved before the theme is consulted.
enum SiteShortcodes {

    /// The custom-script shortcode, which emits the page's own `custom.js`.
    static let customScriptName = "hfh-custom-script"

    /// `custom.js` sits beside the page, so it is a *page* resource. `resources.Get`
    /// looks in `assets/` and would silently find nothing, which is why this uses
    /// the page's own resource collection.
    static let customScriptTemplate = """
    {{- /* Injects this page's custom.js. Installed by Hugo for Humans. */ -}}
    {{- with .Page.Resources.Get "custom.js" -}}
    <script src="{{ .RelPermalink }}"></script>
    {{- else -}}
    {{- /* No script for this page: emit nothing rather than a broken tag. */ -}}
    {{- end -}}
    """

    /// Installs any missing shortcodes into a site, without touching the ones
    /// already there. Returns the names it wrote.
    @discardableResult
    static func install(in root: URL) -> [String] {
        let directory = root.appendingPathComponent("layouts/shortcodes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return []
        }

        var written: [String] = []
        let target = directory.appendingPathComponent(customScriptName + ".html")
        // Never overwrite a user's own version of the shortcode.
        if !FileManager.default.fileExists(atPath: target.path) {
            if (try? customScriptTemplate.write(to: target, atomically: true, encoding: .utf8)) != nil {
                written.append(customScriptName)
            }
        }
        return written
    }

    /// True when the shortcode the app needs is present in the site.
    static func isInstalled(in root: URL) -> Bool {
        let target = root
            .appendingPathComponent("layouts/shortcodes")
            .appendingPathComponent(customScriptName + ".html")
        return FileManager.default.fileExists(atPath: target.path)
    }
}

/// The per-page custom script, as stored in the page's Markdown.
///
/// A page keeps its script in two places: `custom.js` beside the page holds the
/// code, and one shortcode line in the body pulls it in. Keeping the line in the
/// body is what makes the behaviour visible in the Markdown — a reader of the
/// file can see that something is injected, which matters for a file that is
/// meant to stay portable.
enum PageScript {
    /// The line that pulls the script into the page.
    static let marker = "{{< hfh-custom-script >}}"

    /// The file the code is written to, relative to the page's folder.
    static let fileName = "custom.js"

    static func hasScriptMarker(in body: String) -> Bool {
        body.contains(marker)
    }

    /// Inserts or strips the shortcode call.
    ///
    /// Idempotent on purpose: saving twice must not stack two markers, because
    /// that would load the script twice on the published page.
    static func applyingMarker(_ wanted: Bool, to body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces) == marker }
        if wanted {
            // Near the top, after any opening paragraph, so a script that tags
            // the page has run by the time the reader reaches it.
            lines.insert(marker, at: min(1, lines.count))
        }
        // Strip the blank line the removal left behind.
        while lines.count > 1, (lines.last ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
