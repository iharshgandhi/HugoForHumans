// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

// MARK: - Front matter

/// These cover the part most likely to silently corrupt someone's site:
/// front matter round-tripping and the paths the app derives. Every fixture uses
/// the exact shapes real Hugo writes.
func frontMatterSuite() -> TestSuite {
    var s = TestSuite("Front matter")

    s.test("parses TOML front matter") {
        let raw = """
        +++
        date = '2026-01-31T09:30:00+05:30'
        draft = true
        title = 'My First Post'
        +++

        Body text here.
        """
        let fm = FrontMatter.parse(raw)
        expectEqual(fm.format, .toml, "format")
        expectEqual(fm.title, "My First Post", "title")
        expect(fm.isDraft, "draft flag")
        expectEqual(fm.body, "Body text here.", "body")
    }

    s.test("parses YAML front matter") {
        let raw = """
        ---
        title: "Hello"
        date: 2026-01-31T09:30:00Z
        draft: false
        tags: ["one", "two"]
        ---

        Some words.
        """
        let fm = FrontMatter.parse(raw)
        expectEqual(fm.format, .yaml, "format")
        expectEqual(fm.title, "Hello", "title")
        expect(!fm.isDraft, "draft flag")
        expectEqual(fm.tags, ["one", "two"], "tags")
    }

    s.test("a save round trip keeps unknown keys") {
        let raw = """
        +++
        date = '2026-01-31T09:30:00+05:30'
        draft = true
        title = 'Round Trip'
        customField = 'kept'
        +++

        Body.
        """
        let reparsed = FrontMatter.parse(FrontMatter.parse(raw).serialized())
        expectEqual(reparsed.title, "Round Trip", "title")
        expect(reparsed.isDraft, "draft flag")
        expectEqual(reparsed["customField"]?.stringValue ?? "", "kept",
                    "unknown keys must survive a save")
        expectEqual(reparsed.body, "Body.", "body")
    }

    s.test("quotes in values do not corrupt the file") {
        var fm = FrontMatter.parse("+++\ntitle = 'It is fine'\n+++\n\nBody.\n")
        fm["title"] = .string("It's a \"test\"")
        expectEqual(FrontMatter.parse(fm.serialized()).title, "It's a \"test\"", "title")
    }

    s.test("apostrophes in titles round trip") {
        var fm = FrontMatter.parse("+++\ntitle = 'Plain'\n+++\n\nBody.\n")
        fm["title"] = .string("Harsh's Site")
        expectEqual(FrontMatter.parse(fm.serialized()).title, "Harsh's Site", "title")
    }

    s.test("a file with no front matter is all body") {
        let fm = FrontMatter.parse("Just a body, no front matter at all.")
        expectEqual(fm.body, "Just a body, no front matter at all.", "body")
        expect(fm.title.isEmpty, "title should be empty")
    }

    s.test("empty bodies are allowed") {
        let fm = FrontMatter.parse("+++\ntitle = 'Empty'\n+++\n\n")
        expectEqual(fm.title, "Empty", "title")
        expectEqual(fm.body, "", "body")
    }

    for stamp in ["2026-01-31T09:30:00+05:30", "2026-01-31T09:30:00Z", "2026-01-31"] {
        s.test("date \(stamp) survives parsing") {
            let fm = FrontMatter.parse("+++\ndate = '\(stamp)'\n+++\n\nBody.\n")
            expectEqual(fm.dateString, stamp, "date")
        }
    }

    s.test("setting a field to nil removes it") {
        var fm = FrontMatter.parse("+++\ntitle = 'T'\ntags = ['a']\n+++\n\nBody.\n")
        fm["tags"] = nil
        expect(fm["tags"] == nil, "tags should be gone")
        expect(!fm.serialized().contains("tags"), "removed key should not reappear")
    }

    s.test("word count and reading time are computed") {
        let body = String(repeating: "word ", count: 440)
        let fm = FrontMatter(format: .toml, values: [], body: body)
        expectEqual(fm.wordCount, 440, "word count")
        expectEqual(fm.readingMinutes, 2, "reading time at 220 wpm")
    }

    return s
}

// MARK: - Content items

func contentItemSuite() -> TestSuite {
    var s = TestSuite("Content items")

    func scratch() -> (root: URL, content: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hfh-item-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("content"))
    }

    s.test("_index.md is recognised as a section") {
        let dirs = scratch()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let dir = dirs.content.appendingPathComponent("posts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "+++\ntitle = 'Posts'\n+++\n\n"
            .write(to: dir.appendingPathComponent("_index.md"), atomically: true, encoding: .utf8)

        let item = ContentItem.load(from: dir.appendingPathComponent("_index.md"), projectRoot: dirs.root)
        expectEqual(item?.kind, .section, "kind")
        expectEqual(item?.section ?? "", "posts", "section name")
    }

    s.test("index.md inside a folder is a page bundle") {
        let dirs = scratch()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let dir = dirs.content.appendingPathComponent("posts/my-post")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "+++\ntitle = 'P'\n+++\n\n"
            .write(to: dir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let item = ContentItem.load(from: dir.appendingPathComponent("index.md"), projectRoot: dirs.root)
        expectEqual(item?.kind, .bundle, "kind")
    }

    s.test("a top-level page has no section") {
        let dirs = scratch()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        try? FileManager.default.createDirectory(at: dirs.content, withIntermediateDirectories: true)
        try? "+++\ntitle = 'About'\n+++\n\nHi.\n"
            .write(to: dirs.content.appendingPathComponent("about.md"), atomically: true, encoding: .utf8)

        let item = ContentItem.load(from: dirs.content.appendingPathComponent("about.md"),
                                    projectRoot: dirs.root)
        expectEqual(item?.section ?? "x", "", "section name")
        expectEqual(item?.kind, .page, "kind")
        expectEqual(item?.title, "About", "title")
    }

    s.test("images are assets, not pages") {
        let dirs = scratch()
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        try? FileManager.default.createDirectory(at: dirs.content, withIntermediateDirectories: true)
        let image = dirs.content.appendingPathComponent("photo.jpg")
        try? Data([0xFF, 0xD8, 0xFF]).write(to: image)

        let item = ContentItem.load(from: image, projectRoot: dirs.root)
        expectEqual(item?.kind, .asset, "kind")
        expectEqual(item?.title, "photo", "title")
    }

    s.test("titles fall back to the file name") {
        let fm = FrontMatter(format: .toml, values: [], body: "")
        let item = ContentItem(relativePath: "posts/my-first-post.md",
                               url: URL(fileURLWithPath: "/tmp/my-first-post.md"),
                               kind: .page, frontMatter: fm)
        expectEqual(item.title, "My First Post", "derived title")
    }

    let slugCases: [(String, String)] = [
        ("Hello, World!", "hello-world"),
        ("  Multiple   spaces  ", "multiple-spaces"),
        ("C++ & Rust", "c-rust"),
        ("Posts", "posts"),
        ("", ""),
    ]
    for (input, expected) in slugCases {
        s.test("slugify(\"\(input)\")") {
            expectEqual(SiteEngine.slugify(input), expected, "slug")
        }
    }

    return s
}

// MARK: - Site configuration

func siteConfigSuite() -> TestSuite {
    var s = TestSuite("Site configuration")

    func scratch() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hfh-config-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    s.test("settings survive a write and reload") {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        var config = SiteConfig()
        config.title = "My Test Site"
        config.baseURL = "https://example.com/"
        config.theme = "PaperMod"
        config.author = "Test Author"
        try? config.write(to: root)

        let reloaded = SiteConfig.load(root: root)
        expectEqual(reloaded.title, "My Test Site", "title")
        expectEqual(reloaded.baseURL, "https://example.com/", "baseURL")
        expectEqual(reloaded.theme, "PaperMod", "theme")
    }

    s.test("generated config is well formed") {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        var config = SiteConfig()
        config.title = "Valid TOML"
        config.theme = "PaperMod"
        try? config.write(to: root)

        guard let text = try? String(contentsOf: root.appendingPathComponent("hugo.toml"), encoding: .utf8) else {
            expect(false, "could not read back hugo.toml")
            return
        }
        expect(text.contains("title = 'Valid TOML'"), "title line")
        expect(text.contains("theme = 'PaperMod'"), "theme line")
        expect(text.contains("[params]"), "params table")
        expect(text.contains("[markup]"), "markup table")

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("="), !trimmed.hasPrefix("#") else { continue }
            let after = trimmed.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            let quotes = after.filter { $0 == "'" }.count
            expect(quotes % 2 == 0, "unbalanced quotes in: \(trimmed)")
        }
    }

    s.test("an existing YAML config is detected and read") {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try? "title: 'YAML site'".write(to: root.appendingPathComponent("hugo.yaml"),
                                        atomically: true, encoding: .utf8)
        expectEqual(SiteConfig.configFileName(in: root), "hugo.yaml", "detected filename")
        expectEqual(SiteConfig.load(root: root).title, "YAML site", "title")
    }

    s.test("a site with no config file loads defaults") {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        expect(SiteConfig.load(root: root).title.isEmpty, "title should default to empty")
    }

    s.test("completeness rises as settings are filled in") {
        var config = SiteConfig()
        let empty = config.completeness
        config.title = "A"
        config.theme = "PaperMod"
        config.baseURL = "https://real.example/"
        let filled = config.completeness
        expect(filled > empty, "completeness should increase when settings are filled in")
        expect(filled <= 1.0, "completeness should stay within 0...1")
    }

    return s
}

// MARK: - Build output parsing

func builderSuite() -> TestSuite {
    var s = TestSuite("Build output parsing")

    let sample = """
    Start building sites …

                          │ EN
    ─────────────────────┼─────────
     Pages                │  8
     Paginator pages      │  0
     Static files         │  3

    Total in 32 ms
    """

    s.test("page count is read from Hugo's build table") {
        expectEqual(Builder.parsePages(sample), 8, "pages")
    }

    s.test("build duration is read from the summary line") {
        expectEqual(Builder.parseDuration(sample), "32 ms", "duration")
    }

    s.test("CSV rows are counted excluding the header") {
        expectEqual(Builder.countRows("path,slug,title\ncontent/a.md,,A\ncontent/b.md,,B"), 2, "rows")
    }

    s.test("empty output counts as zero") {
        expectEqual(Builder.countRows(""), 0, "rows")
    }

    s.test("the first Hugo error is surfaced") {
        let output = "Start building sites …\nERROR error building site: something broke"
        expectEqual(Builder.firstError(in: output) ?? "", "ERROR error building site: something broke", "error")
        expect(Builder.firstError(in: "all good") == nil, "no error expected")
    }

    s.test("output with no summary is handled") {
        expectEqual(Builder.parsePages("nothing here"), 0, "pages")
        expectEqual(Builder.parseDuration("nothing here"), "—", "duration")
    }

    return s
}

// MARK: - Theme catalog

func themeCatalogSuite() -> TestSuite {
    var s = TestSuite("Theme catalog")

    s.test("every theme has the fields the gallery needs") {
        for theme in ThemeCatalog.all {
            expect(!theme.name.isEmpty, "\(theme.name) has no name")
            expect(!theme.repo.isEmpty, "\(theme.name) has no repo")
            expect(theme.repoURL != nil, "\(theme.name) has an invalid repo URL")
            expect(theme.repo.contains("/"), "\(theme.name) repo looks malformed")
        }
    }

    s.test("theme names are unique") {
        let names = ThemeCatalog.all.map(\.name)
        expectEqual(Set(names).count, names.count, "unique names")
    }

    s.test("accent colors are valid hex") {
        for theme in ThemeCatalog.all {
            expect(theme.accent.hasPrefix("#"), "\(theme.name) accent must be hex")
            expectEqual(theme.accent.count, 7, "\(theme.name) accent length")
        }
    }

    s.test("lookup by name is case insensitive") {
        expect(ThemeCatalog.theme(named: "papermod") != nil, "lowercase lookup")
        expect(ThemeCatalog.theme(named: "PAPERMOD") != nil, "uppercase lookup")
        expect(ThemeCatalog.theme(named: "not-a-real-theme") == nil, "unknown theme returns nil")
    }

    s.test("category filtering narrows the gallery") {
        let docs = ThemeCatalog.themes(in: .docs)
        expect(!docs.isEmpty, "docs category should not be empty")
        expect(docs.allSatisfy { $0.category == .docs }, "filter should only return docs")
    }

    return s
}

func hugoBinarySuite() -> TestSuite {
    var s = TestSuite("Hugo engine discovery")

    s.test("the version number is readable, not the whole version line") {
        // `hugo version` returns a long line with a git hash. Showing that in the
        // UI is noise, so the app parses out just the number.
        let line = "hugo v0.166.0-78400b4de8adc99273d3e674ed6c4d14c3bdf669+extended darwin/arm64 BuildDate=2026-09-09T14:45:02Z VendorInfo=gohugoio"
        let token = line.split(separator: " ").dropFirst().first.map(String.init) ?? line
        let cleaned = token.hasPrefix("v") ? String(token.dropFirst()) : token
        let number = cleaned.prefix { $0.isNumber || $0 == "." }
        expectEqual(String(number), "0.166.0", "version number")
    }

    s.test("a version with no build hash still parses") {
        let token = "0.147.9"
        let cleaned = token.hasPrefix("v") ? String(token.dropFirst()) : token
        expectEqual(String(cleaned.prefix { $0.isNumber || $0 == "." }), "0.147.9", "version number")
    }

    s.test("resolving a binary does not recurse") {
        // resolve() asks for a version, and asking for a version must not call
        // resolve() again — that mutual recursion crashed the app on launch.
        guard let url = HugoBinary.resolve() else { return }   // no Hugo: nothing to check
        let v = HugoBinary.version(of: url)
        expect(v != nil, "a resolved binary should report a version")
        expect(HugoBinary.shortVersion(of: url) != nil, "short version should parse")
        expect(v?.contains("hugo v") == true, "the raw line still starts with 'hugo v'")
    }

    return s
}

func streamedOutputSuite() -> TestSuite {
    var s = TestSuite("Streamed command output")

    s.test("a build result carries the output, not just the live feed") {
        // Builder decides success by looking for Hugo's build table. An earlier
        // version of the async runner returned an empty result, so every build in
        // the app reported failure even though Hugo exited 0.
        let collector = OutputCollector()
        collector.append("  Pages            │  12 ", isError: false)
        collector.append("Total in 145 ms", isError: false)
        collector.append("WARN  deprecated: something", isError: true)

        let result = CommandResult(status: 0,
                                   standardOutput: collector.standardOutput,
                                   standardError: collector.standardError)
        expect(result.succeeded, "exit 0 is success")
        expect(result.looksLikeSuccessfulBuild, "the build table should be visible in the result")
        expect(result.combined.contains("deprecated"), "stderr should be captured too")
        expectEqual(Builder.parsePages(result.combined), 12, "pages are parsed from the captured output")
    }

    s.test("output with no build table is not reported as a build") {
        let result = CommandResult(status: 0, standardOutput: "nothing here", standardError: "")
        expect(!result.looksLikeSuccessfulBuild, "no table means no build")
    }

    return s
}

func quotingSuite() -> TestSuite {
    var s = TestSuite("Front matter quoting")

    s.test("an apostrophe does not break a TOML file") {
        // Regression: single quotes make a TOML *literal* string, where backslash
        // is not an escape. Writing \' inside one produced a file Hugo refused to
        // parse, so any title with an apostrophe produced an unbuildable site.
        expectEqual(FrontMatterValue.tomlString("The Tape That Doesn't Add Up"),
                    "\"The Tape That Doesn't Add Up\"", "apostrophe forces a basic string")
        expectEqual(FrontMatterValue.tomlString("Plain Title"), "'Plain Title'",
                    "a plain value keeps the tidier literal form")
    }

    s.test("quotes and backslashes survive a round trip") {
        let awkward = "He said \"go\" and then \\ left"
        // A backslash rules out the literal form, so this becomes a basic string
        // with real escapes rather than a literal where \\ would stay doubled.
        expectEqual(FrontMatterValue.tomlString(awkward),
                    "\"He said \\\"go\\\" and then \\\\ left\"",
                    "double quotes and backslashes are escaped in a basic string")

        var fm = FrontMatter(format: .toml, values: [], body: "")
        fm["title"] = .string(awkward)
        let text = fm.serialized()
        let parsed = FrontMatter.parse(text)
        expectEqual(parsed["title"]?.stringValue, awkward, "the value survives the round trip")
    }

    s.test("a title with an apostrophe survives the full round trip") {
        var fm = FrontMatter(format: .toml, values: [], body: "Body text.")
        fm["title"] = .string("Chemtrails: I've Been Counting")
        let text = fm.serialized()
        expect(!text.contains("\\'"), "no backslash-escaped quote should be emitted")
        let parsed = FrontMatter.parse(text)
        expectEqual(parsed["title"]?.stringValue, "Chemtrails: I've Been Counting", "title")
        expectEqual(parsed.body, "Body text.", "body")
    }

    s.test("a site title with an apostrophe produces a valid config") {
        // The config serializer interpolated raw values before, so a site called
        // "Gerald's Blog" would have written a broken hugo.toml.
        var config = SiteConfig()
        config.title = "Gerald's Blog"
        config.description = "He said \"hi\""
        let text = config.serialize()
        expect(!text.contains("\\'"), "config should not emit a backslash-escaped quote")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-config-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? config.write(to: root)

        let reloaded = SiteConfig.load(root: root)
        expectEqual(reloaded.title, "Gerald's Blog", "the title round trips through the file")
    }

    return s
}
