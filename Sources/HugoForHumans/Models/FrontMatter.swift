// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// A parsed front matter value. Deliberately small: enough to round-trip the
/// fields people actually edit in a GUI, without pretending to be a TOML parser.
enum FrontMatterValue: Equatable, Hashable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case date(String)
    case list([String])

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .date(let s): return s
        case .list(let items): return items.joined(separator: ", ")
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        if case .string(let s) = self { return ["true", "yes", "1"].contains(s.lowercased()) }
        return nil
    }

    var listValue: [String] {
        switch self {
        case .list(let items): return items
        case .string(let s): return s.isEmpty ? [] : [s]
        default: return []
        }
    }

    /// Rendered back into the source format.
    func serialized(for format: FrontMatterFormat) -> String {
        switch format {
        case .toml:
            switch self {
            case .string(let s): return Self.tomlString(s)
            case .date(let s): return s
            case .bool(let b): return b ? "true" : "false"
            case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
            case .list(let items): return "[" + items.map(Self.tomlString).joined(separator: ", ") + "]"
            }
        case .yaml:
            switch self {
            case .string(let s): return Self.yamlString(s)
            case .list(let items): return "[" + items.map(Self.yamlString).joined(separator: ", ") + "]"
            default: return stringValue
            }
        case .json:
            switch self {
            case .string(let s): return Self.jsonString(s)
            case .list(let items): return "[" + items.map(Self.jsonString).joined(separator: ",") + "]"
            default: return stringValue
            }
        }
    }

    /// TOML quoting.
    ///
    /// Single quotes make a TOML *literal* string, where backslash is not an
    /// escape character. That has two consequences, and both were live bugs:
    /// an apostrophe cannot be written at all, and a backslash survives as two
    /// characters instead of one. Apostrophes are common in titles ("Doesn't Add
    /// Up") and Windows paths contain backslashes, so any string containing
    /// either falls back to a basic string, which does process escapes.
    static func tomlString(_ s: String) -> String {
        guard !s.contains("'"), !s.contains("\\") else { return basicString(s) }
        return "'\(s)'"
    }

    /// A TOML basic string: backslash escapes apply, so both quote styles are safe.
    private static func basicString(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(out)\""
    }

    /// YAML quoting. YAML only needs quotes when the value would otherwise be
    /// ambiguous — a bare apostrophe is perfectly legal.
    private static func yamlString(_ s: String) -> String {
        guard !s.isEmpty else { return "\"\"" }
        let ambiguous = s.contains(": ") || s.contains(" #")
            || s.hasPrefix("-") || s.hasPrefix("[") || s.hasPrefix("{")
            || ["true", "false", "null", "yes", "no", "~"].contains(s.lowercased())
        return ambiguous ? basicString(s) : s
    }

    private static func jsonString(_ s: String) -> String { basicString(s) }
}

enum FrontMatterFormat: String, Equatable {
    case toml, yaml, json
}

/// A content file split into its front matter and its Markdown body.
struct FrontMatter: Equatable, Hashable {
    var format: FrontMatterFormat
    /// Key order is preserved so saving does not reshuffle someone's file.
    var values: [(key: String, value: FrontMatterValue)]
    var body: String

    // `values` is an array of tuples, which cannot synthesize Hashable, so the
    // conformances are written by hand. Identity is the ordered key/value list.
    static func == (lhs: FrontMatter, rhs: FrontMatter) -> Bool {
        guard lhs.format == rhs.format, lhs.body == rhs.body, lhs.values.count == rhs.values.count else {
            return false
        }
        for (a, b) in zip(lhs.values, rhs.values) where a.key != b.key || a.value != b.value {
            return false
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(format)
        hasher.combine(body)
        for entry in values {
            hasher.combine(entry.key)
            hasher.combine(entry.value)
        }
    }

    subscript(key: String) -> FrontMatterValue? {
        get { values.first(where: { $0.key == key })?.value }
        set {
            guard let newValue else {
                values.removeAll { $0.key == key }
                return
            }
            if let index = values.firstIndex(where: { $0.key == key }) {
                values[index].value = newValue
            } else {
                values.append((key, newValue))
            }
        }
    }

    var title: String { self["title"]?.stringValue ?? "" }
    var isDraft: Bool { self["draft"]?.boolValue ?? false }
    var dateString: String { self["date"]?.stringValue ?? self["publishDate"]?.stringValue ?? "" }
    var tags: [String] { self["tags"]?.listValue ?? [] }
    var categories: [String] { self["categories"]?.listValue ?? [] }
    var summary: String { self["description"]?.stringValue ?? self["summary"]?.stringValue ?? "" }

    var wordCount: Int {
        body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    var readingMinutes: Int { max(1, Int((Double(wordCount) / 220.0).rounded())) }

    // MARK: - Serialization

    func serialized() -> String {
        var head = ""
        switch format {
        case .toml:
            head = values.map { "\($0.key) = \($0.value.serialized(for: .toml))" }.joined(separator: "\n")
            return "+++\n\(head)\n+++\n\n\(body)"
        case .yaml:
            head = values.map { "\($0.key): \($0.value.serialized(for: .yaml))" }.joined(separator: "\n")
            return "---\n\(head)\n---\n\n\(body)"
        case .json:
            let dict = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value.serialized(for: .json)) })
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return "{\n}\n\(body)"
            }
            return json + "\n" + body
        }
    }

    // MARK: - Parsing

    static func parse(_ raw: String) -> FrontMatter {
        guard let split = split(raw) else {
            return FrontMatter(format: .yaml, values: [], body: raw)
        }
        let (format, header, body) = split
        return FrontMatter(format: format, values: parseValues(header, format: format), body: body)
    }

    private static func split(_ raw: String) -> (FrontMatterFormat, String, String)? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")

        // Delimited front matter: TOML uses +++, YAML uses ---.
        let delimiter: String
        let format: FrontMatterFormat
        if normalized.hasPrefix("+++") {
            delimiter = "+++"
            format = .toml
        } else if normalized.hasPrefix("---") {
            delimiter = "---"
            format = .yaml
        } else {
            return splitJSON(normalized)
        }

        let afterOpen = String(normalized.dropFirst(delimiter.count))
            .trimmingCharacters(in: .newlines)
        guard let range = afterOpen.range(of: "\n" + delimiter) else { return nil }
        let header = String(afterOpen[afterOpen.startIndex..<range.lowerBound])
        let body = String(afterOpen[range.upperBound...])
            .trimmingCharacters(in: .newlines)
        return (format, header, body)
    }

    /// JSON front matter is a bare object at the top of the file. Splitting it
    /// needs a JSON parse rather than a text delimiter.
    private static func splitJSON(_ text: String) -> (FrontMatterFormat, String, String)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let dict = object as? [String: Any],
              !dict.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let header = String(data: data, encoding: .utf8) else { return nil }
        return (.json, header, "")
    }

    private static func parseValues(_ header: String, format: FrontMatterFormat) -> [(key: String, value: FrontMatterValue)] {
        var results: [(key: String, value: FrontMatterValue)] = []
        for rawLine in header.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }

            let key: String
            let valueText: String
            switch format {
            case .toml:
                guard let eq = line.firstIndex(of: "=") else { continue }
                key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                valueText = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            case .yaml:
                guard let colon = line.firstIndex(of: ":") else { continue }
                key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                valueText = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            case .json:
                continue
            }

            guard !key.isEmpty else { continue }
            results.append((key, parseValue(valueText)))
        }

        if format == .json, let object = try? JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any] {
            // Preserve a stable order by sorting keys; JSON front matter is rare enough
            // that exact ordering fidelity is not worth the complexity.
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                results.append((key, FrontMatterValue.string(describe(value))))
            }
        }
        return results
    }

    private static func parseValue(_ text: String) -> FrontMatterValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            let items = inner.split(separator: ",").map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            return .list(items.filter { !$0.isEmpty })
        }
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        let unquoted = unquote(trimmed)
        if unquoted != trimmed { return .string(unquoted) }
        if let n = Double(trimmed) { return .number(n) }
        // Bare timestamps: 2026-01-31T09:30:00+05:30 or 2026-01-31
        if trimmed.first?.isNumber == true, trimmed.contains("-") {
            return .date(trimmed)
        }
        return .string(trimmed)
    }

    private static func unquote(_ s: String) -> String {
        var out = s
        if out.count >= 2, (out.hasPrefix("'") && out.hasSuffix("'")) || (out.hasPrefix("\"") && out.hasSuffix("\"")) {
            out = String(out.dropFirst().dropLast())
        }
        return out.replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func describe(_ any: Any) -> String {
        switch any {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        case let arr as [Any]: return arr.map(describe).joined(separator: ", ")
        default: return String(describing: any)
        }
    }
}
