// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// The typed, editable view of a site's configuration file.
/// The file on disk stays the source of truth; this is a lens over it.
struct SiteConfig: Equatable {
    var baseURL: String = "https://example.org/"
    var title: String = ""
    var languageCode: String = "en-us"
    var theme: String = ""
    var author: String = ""
    var description: String = ""
    var copyright: String = ""
    var enableRobotsTXT: Bool = true
    var enableGitInfo: Bool = false
    var enableEmoji: Bool = true
    var summaryLength: Int = 30
    var taxonomies: [String] = ["tags", "categories"]
    var hasBuildDraftsDefault: Bool = false
    var raw: String = ""

    var summaryLine: String {
        description.isEmpty ? "\(title) — built with Hugo for Humans" : description
    }

    /// Megabyte-accurate guess at how fast this site builds, shown as a stat.
    var completeness: Double {
        var score = 0.0
        if !title.isEmpty { score += 1 }
        if !baseURL.isEmpty && !baseURL.contains("example.org") { score += 1 }
        if !theme.isEmpty { score += 1 }
        if !description.isEmpty { score += 1 }
        if !author.isEmpty { score += 1 }
        return score / 5.0
    }

    // MARK: - File format

    static func configFileName(in root: URL) -> String {
        for name in ["hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json"] {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
                return name
            }
        }
        return "hugo.toml"
    }

    static func load(root: URL) -> SiteConfig {
        var config = SiteConfig()
        let name = configFileName(in: root)
        let url = root.appendingPathComponent(name)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return config }
        config.raw = raw
        apply(raw: raw, format: name.hasSuffix("json") ? .json : (name.contains("yaml") || name.hasSuffix("yml") ? .yaml : .toml),
              into: &config)
        return config
    }

    /// Reads top-level keys out of a config file.
    ///
    /// This deliberately does not use `FrontMatter.parse`: a config file has no
    /// `+++`/`---` delimiter, it is a bare TOML/YAML document. Walking the lines
    /// directly also means keys inside `[params]` and other tables are not
    /// mistaken for top-level settings.
    private static func apply(raw: String, format: FrontMatterFormat, into config: inout SiteConfig) {
        var inTopLevel = true
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // A table header ends the top-level section. `[params]` itself is
            // never a table header followed by keys we care about, but stepping
            // out of it on any bracket line is the simplest correct rule.
            if trimmed.hasPrefix("[") {
                inTopLevel = false
                continue
            }
            guard inTopLevel else { continue }

            let key: String
            let valueText: String
            switch format {
            case .toml:
                guard let eq = trimmed.firstIndex(of: "=") else { continue }
                key = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                valueText = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            case .yaml:
                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                valueText = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            case .json:
                continue
            }

            let value = parseScalar(valueText)
            switch key {
            case "baseURL": config.baseURL = value
            case "title": config.title = value
            case "languageCode", "locale", "defaultContentLanguage": config.languageCode = value
            case "theme": config.theme = value
            case "enableRobotsTXT": config.enableRobotsTXT = (value == "true")
            case "enableGitInfo": config.enableGitInfo = (value == "true")
            case "enableEmoji": config.enableEmoji = (value == "true")
            case "summaryLength": config.summaryLength = Int(value) ?? 30
            case "taxonomy", "tag", "category", "series":
                if !config.taxonomies.contains(value) { config.taxonomies.append(value) }
            default: break
            }
        }

        // The compact taxonomy form is `taxonomy = "tag"`.
        if let match = raw.range(of: "(?m)^\\s*taxonomy\\s*=\\s*'([^']+)'", options: .regularExpression) {
            let name = raw[match].replacingOccurrences(
                of: #"^\s*taxonomy\s*=\s*'|"$"#, with: "", options: .regularExpression
            )
            if !name.isEmpty && !config.taxonomies.contains(name) {
                config.taxonomies.append(name)
            }
        }
    }

    /// Strips quotes from a config value.
    private static func parseScalar(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Params live under their own table, so they are handled separately.
    static func params(in root: URL) -> [String: String] {
        let name = configFileName(in: root)
        guard let raw = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        var inParams = false
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inParams = (trimmed == "[params]" || trimmed == "[params.author]")
                continue
            }
            guard inParams, let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("'") && value.hasSuffix("'") { value = String(value.dropFirst().dropLast()) }
            if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            result[key] = value
        }
        return result
    }

    /// Writes the config back, rewriting the whole file.
    /// Hugo config files are short and fully owned by this app's settings screen,
    /// so a full rewrite is clearer than surgical edits and keeps the file tidy.
    func write(to root: URL) throws {
        let name = Self.configFileName(in: root)
        let text = serialize()
        try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func serialize() -> String {
        var lines: [String] = []
        lines.append("baseURL = \(FrontMatterValue.tomlString(baseURL))")
        // Hugo renamed this key to `locale` in v0.158 and warns on the old name.
        // The property keeps its old name because that is what the UI shows, but
        // the file we write uses the current spelling.
        lines.append("locale = \(FrontMatterValue.tomlString(languageCode))")
        lines.append("title = \(FrontMatterValue.tomlString(title))")
        if !theme.isEmpty { lines.append("theme = \(FrontMatterValue.tomlString(theme))") }
        if enableRobotsTXT { lines.append("enableRobotsTXT = true") }
        if enableEmoji { lines.append("enableEmoji = true") }
        if enableGitInfo { lines.append("enableGitInfo = true") }
        lines.append("summaryLength = \(summaryLength)")
        lines.append("timeZone = \(FrontMatterValue.tomlString(TimeZone.current.identifier))")
        if taxonomies.count == 1, let only = taxonomies.first {
            lines.append("[taxonomies]")
            lines.append("\(only) = \(FrontMatterValue.tomlString(only))")
        } else if !taxonomies.isEmpty {
            lines.append("[taxonomies]")
            for t in taxonomies { lines.append("\(t) = \(FrontMatterValue.tomlString(t))") }
        }
        lines.append("")
        lines.append("[params]")
        if !author.isEmpty { lines.append("  author = \(FrontMatterValue.tomlString(author))") }
        if !description.isEmpty { lines.append("  description = \(FrontMatterValue.tomlString(description))") }
        if !copyright.isEmpty { lines.append("  copyright = \(FrontMatterValue.tomlString(copyright))") }
        lines.append("")
        lines.append("[markup]")
        lines.append("  [markup.goldmark.renderer]")
        lines.append("    unsafe = true")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
