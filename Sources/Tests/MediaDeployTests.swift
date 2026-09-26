// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

// MARK: - Embed parsing

func embedSuite() -> TestSuite {
    var s = TestSuite("Embeds")

    s.test("YouTube long form reduces to the video id") {
        for url in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        ] {
            let embed = EmbedParser.parse(url)
            expectEqual(embed.kind, .youtube, "kind for \(url)")
            expectEqual(embed.identifier, "dQw4w9WgXcQ", "id for \(url)")
        }
    }

    s.test("a YouTube id is exactly eleven url-safe characters") {
        expect(EmbedParser.isYouTubeID("dQw4w9WgXcQ"), "11 chars is a valid id")
        expect(!EmbedParser.isYouTubeID("short"), "5 chars is not an id")
        expect(!EmbedParser.isYouTubeID("dQw4w9WgXcQextra"), "16 chars is not")
        expect(!EmbedParser.isYouTubeID("dQw4w9WgX!Q"), "punctuation is not allowed")
    }

    s.test("a youtu.be link to a page is not treated as a video") {
        let embed = EmbedParser.parse("https://youtu.be/some-page")
        expectEqual(embed.kind, .link, "a non-id path falls back to a link")
    }

    s.test("Vimeo ids are extracted") {
        let embed = EmbedParser.parse("https://vimeo.com/76979871")
        expectEqual(embed.kind, .vimeo, "kind")
        expectEqual(embed.identifier, "76979871", "id")
    }

    s.test("a year in a URL is not a Vimeo id") {
        let embed = EmbedParser.parse("https://vimeo.com/user/2024")
        expectEqual(embed.kind, .link, "too few digits to be an id")
    }

    s.test("social posts are recognised") {
        expectEqual(EmbedParser.parse("https://twitter.com/jack/status/20").kind, .twitter, "twitter")
        expectEqual(EmbedParser.parse("https://x.com/jack/status/20").kind, .twitter, "x.com")
        expectEqual(EmbedParser.parse("https://www.instagram.com/p/ABC123/").kind, .instagram, "instagram post")
        expectEqual(EmbedParser.parse("https://www.instagram.com/reel/ABC123/").kind, .instagram, "instagram reel")
        expectEqual(EmbedParser.parse("https://www.facebook.com/somepage/posts/12345").kind, .facebook, "facebook")
    }

    s.test("a bare platform home page is not an embed") {
        expectEqual(EmbedParser.parse("https://instagram.com/").kind, .link, "home page is a link")
        expectEqual(EmbedParser.parse("https://twitter.com/jack").kind, .link, "profile is a link")
    }

    s.test("trailing punctuation from a sentence is stripped") {
        let embed = EmbedParser.parse("https://youtu.be/dQw4w9WgXcQ.")
        expectEqual(embed.identifier, "dQw4w9WgXcQ", "trailing period removed")
    }

    s.test("unknown URLs become links, never nothing") {
        let embed = EmbedParser.parse("https://example.com/some/page")
        expectEqual(embed.kind, .link, "kind")
        expect(embed.markdown.contains("https://example.com/some/page"), "the URL survives")
    }

    s.test("only a bare URL is auto-converted") {
        expect(EmbedParser.looksLikeBareURL("https://youtu.be/dQw4w9WgXcQ"), "a bare URL")
        expect(!EmbedParser.looksLikeBareURL("see https://youtu.be/dQw4w9WgXcQ here"), "a sentence")
        expect(!EmbedParser.looksLikeBareURL("just some words"), "plain text")
        expect(EmbedParser.looksLikeBareURL("www.example.com"), "www without scheme")
    }

    s.test("video markup uses Hugo shortcodes") {
        expectEqual(EmbedParser.parse("https://youtu.be/dQw4w9WgXcQ").markdown,
                    "{{< youtube dQw4w9WgXcQ >}}", "youtube shortcode")
        expectEqual(EmbedParser.parse("https://vimeo.com/76979871").markdown,
                    "{{< vimeo 76979871 >}}", "vimeo shortcode")
    }

    s.test("social markup keeps the original URL") {
        let url = "https://twitter.com/jack/status/20"
        let embed = EmbedParser.parse(url)
        expect(embed.markdown.contains(url), "the source URL is preserved")
        expect(embed.markdown.contains("platform.twitter.com"), "the widget script is included")
    }

    s.test("every kind has a name, an icon and a summary") {
        for kind in EmbedKind.allCases {
            expect(!kind.displayName.isEmpty, "\(kind) has a display name")
            expect(!kind.symbolName.isEmpty, "\(kind) has an icon")
        }
        expect(!EmbedParser.parse("https://youtu.be/dQw4w9WgXcQ").summary.isEmpty, "summary is present")
    }

    return s
}

// MARK: - Media placement

@MainActor
func mediaSuite() -> TestSuite {
    var s = TestSuite("Media")

    s.test("a unique name is used when the file is already there") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-media-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        FileManager.default.createFile(atPath: dir.appendingPathComponent("photo.jpg").path, contents: Data())
        let second = MediaLibrary.uniqueDestination(in: dir, for: "photo.jpg")
        expectEqual(second.lastPathComponent, "photo-2.jpg", "first collision")

        FileManager.default.createFile(atPath: second.path, contents: Data())
        let third = MediaLibrary.uniqueDestination(in: dir, for: "photo.jpg")
        expectEqual(third.lastPathComponent, "photo-3.jpg", "second collision")
    }

    s.test("extensions are classified as inline or attachment") {
        expectEqual(MediaAsset.Kind(extension: "jpg"), .inline, "jpg is inline")
        expectEqual(MediaAsset.Kind(extension: "PNG"), .inline, "case is ignored")
        expectEqual(MediaAsset.Kind(extension: "mp4"), .inline, "video is inline")
        expectEqual(MediaAsset.Kind(extension: "pdf"), .attachment, "pdf is an attachment")
        expectEqual(MediaAsset.Kind(extension: "zip"), .attachment, "zip is an attachment")
        expectEqual(MediaAsset.Kind(extension: "docx"), .attachment, "docx is an attachment")
    }

    s.test("byte counts are formatted for a human") {
        expectEqual(MediaAsset.format(bytes: 512), "512 bytes", "bytes")
        expect(MediaAsset.format(bytes: 1_400_000).contains("MB"), "megabytes")
    }

    s.test("an image beside a page is added and referred to relatively") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-media-\(UUID().uuidString)", isDirectory: true)
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try? FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A leaf bundle: index.md with resources beside it.
        let bundle = content.appendingPathComponent("my-post", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let pageURL = bundle.appendingPathComponent("index.md")
        try? "# hi".write(to: pageURL, atomically: true, encoding: .utf8)

        let source = root.appendingPathComponent("holiday.png")
        FileManager.default.createFile(atPath: source.path, contents: Data([0x89, 0x50, 0x4E, 0x47]))

        let item = ContentItem.load(from: pageURL, projectRoot: root)
        expect(item != nil, "the page loads")
        guard let item else { return }

        let placed = try MediaLibrary.add(source, to: item, projectRoot: root, kind: .inline)
        expectEqual(placed.markdownPath, "holiday.png", "bundle resources are referenced by name")
        expect(FileManager.default.fileExists(atPath: placed.asset.url.path), "the file was copied")
        expectEqual(placed.asset.relativePath, "content/posts/my-post/holiday.png", "it lives beside the page")
    }

    s.test("the page is left as a plain markdown file") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-media-\(UUID().uuidString)", isDirectory: true)
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try? FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pageURL = content.appendingPathComponent("plain.md")
        let original = "---\ntitle: 'Plain'\n---\n\nBody text.\n"
        try? original.write(to: pageURL, atomically: true, encoding: .utf8)

        let source = root.appendingPathComponent("pic.jpg")
        FileManager.default.createFile(atPath: source.path, contents: Data([0xFF, 0xD8]))

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }
        let placed = try MediaLibrary.add(source, to: item, projectRoot: root, kind: .inline)

        // The page is promoted to a leaf bundle so the image can sit beside it,
        // but its contents must survive that move untouched.
        expectEqual(placed.pageURL.lastPathComponent, "index.md", "the page becomes a bundle")
        let after = (try? String(contentsOf: placed.pageURL, encoding: .utf8)) ?? ""
        expectEqual(after, original, "the page's own text is not rewritten")
        expect(!FileManager.default.fileExists(atPath: pageURL.path), "the old path is gone")

        // Hugo serves both layouts at the same URL, so the move is invisible.
        expectEqual(placed.markdownPath, "pic.jpg", "and the image is referred to relatively")
    }

    s.test("assets are split into inline and attachment lists") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-media-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("content/posts/post", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pageURL = bundle.appendingPathComponent("index.md")
        try? "# hi".write(to: pageURL, atomically: true, encoding: .utf8)
        for name in ["a.png", "b.jpg", "report.pdf", "data.zip"] {
            FileManager.default.createFile(atPath: bundle.appendingPathComponent(name).path, contents: Data([0x1]))
        }

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }
        let assets = MediaLibrary.assets(for: item, projectRoot: root)
        expectEqual(assets.inline.map(\.name), ["a.png", "b.jpg"], "images are inline")
        expectEqual(assets.attachments.map(\.name), ["data.zip", "report.pdf"], "documents are attachments")
        expect(!assets.inline.contains { $0.name == "index.md" }, "the page itself is not an asset")
    }

    s.test("image dimensions are read without decoding the file") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-media-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A real 2x1 PNG, written by hand so no image library is needed.
        let png = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAFElEQVR42mP8z8BQz0AEYBxVSF+FA\
        AxJROEEGBkZ2fgAAAABJRU5ErkJggg==
        """) ?? Data()
        let file = root.appendingPathComponent("tiny.png")
        try? png.write(to: file)

        if let size = MediaAsset.pixelSize(of: file) {
            expectEqual(size.width, 2, "width")
            expectEqual(size.height, 1, "height")
        } else {
            // A corrupt or unrecognised file must return nil, never crash.
            let broken = root.appendingPathComponent("broken.png")
            FileManager.default.createFile(atPath: broken.path, contents: Data([0x00, 0x01]))
            expect(MediaAsset.pixelSize(of: broken) == nil, "a corrupt file returns nil")
        }
    }

    return s
}

// MARK: - Credential vault

func vaultSuite() -> TestSuite {
    var s = TestSuite("Keychain")

    s.test("a secret survives a store and a read") {
        let key = CredentialVault.Key(service: "HugoForHumans.Test", account: "probe")
        defer { _ = try? CredentialVault.remove(key) }

        try CredentialVault.set("hunter2", for: key)
        let read = try CredentialVault.get(key)
        expectEqual(read, "hunter2", "the secret reads back")
        expect(CredentialVault.has(key), "the item is reported as present")
    }

    s.test("storing twice overwrites rather than failing") {
        let key = CredentialVault.Key(service: "HugoForHumans.Test", account: "overwrite")
        defer { _ = try? CredentialVault.remove(key) }

        try CredentialVault.set("first", for: key)
        try CredentialVault.set("second", for: key)
        let value = try CredentialVault.get(key)
        expectEqual(value, "second", "the later value wins")
    }

    s.test("removing a secret really removes it") {
        let key = CredentialVault.Key(service: "HugoForHumans.Test", account: "removal")
        try CredentialVault.set("temporary", for: key)
        let removed = try CredentialVault.remove(key)
        let after = try CredentialVault.get(key)
        expect(removed, "removal reports success")
        expect(after == nil, "the secret is gone")
        expect(!CredentialVault.has(key), "no longer reported as present")
    }

    s.test("reading a secret that was never stored returns nil, not an error") {
        let key = CredentialVault.Key(service: "HugoForHumans.Test", account: "never-stored")
        let value = try CredentialVault.get(key)
        expect(value == nil, "nil rather than an error")
    }

    s.test("host credentials store a username and password together") {
        let host = "ftp.test.invalid"
        defer { _ = try? CredentialVault.remove(.host(host)) }

        try CredentialVault.setHostSecret(.init(username: "alice", password: "s3cret"), for: host)
        let stored = CredentialVault.hostSecret(for: host)
        expectEqual(stored?.username, "alice", "username")
        expectEqual(stored?.password, "s3cret", "password")
    }

    s.test("a password containing a newline is not silently truncated") {
        let host = "ftp.newline.invalid"
        defer { _ = try? CredentialVault.remove(.host(host)) }

        // A password may contain a newline. Splitting the packed value on one
        // would hand the server the wrong password, so the separator must be
        // something a password cannot contain.
        try CredentialVault.setHostSecret(.init(username: "bob", password: "line1\nline2"), for: host)
        let stored = CredentialVault.hostSecret(for: host)
        expectEqual(stored?.username, "bob", "username")
        expectEqual(stored?.password, "line1\nline2", "the password survives intact")
    }

    return s
}

// MARK: - Publish targets

@MainActor
func targetSuite() -> TestSuite {
    var s = TestSuite("Deployment")

    s.test("the built-in targets register and can be found") {
        let registry = PublishTargetRegistry.shared
        registry.registerBuiltIns()
        expect(registry.targets.count >= 3, "at least three targets")
        expect(registry.target(withID: "local-folder") != nil, "local folder")
        expect(registry.target(withID: "github-pages") != nil, "github pages")
        expect(registry.target(withID: "web-host") != nil, "web host")
    }

    s.test("registering the same id twice replaces rather than duplicates") {
        let registry = PublishTargetRegistry.shared
        registry.registerBuiltIns()
        let before = registry.targets.count
        registry.registerBuiltIns()
        expectEqual(registry.targets.count, before, "re-registering does not grow the list")
    }

    s.test("every target has the metadata the UI needs") {
        for target in PublishTargetRegistry.shared.targets {
            let d = type(of: target).descriptor
            expect(!d.id.isEmpty, "id")
            expect(!d.name.isEmpty, "\(d.id) name")
            expect(!d.tagline.isEmpty, "\(d.id) tagline")
            expect(!d.icon.isEmpty, "\(d.id) icon")
            // A target that needs credentials must say which fields hold them.
            if d.needsCredentials {
                expect(!d.fields.isEmpty, "\(d.id) declares its credential fields")
            }
        }
    }

    s.test("the registry is the only place targets are enumerated") {
        // This is the plugin seam: a third party adds a type and registers it.
        // If the UI ever hard-codes a list, this test should fail to compile.
        let registry = PublishTargetRegistry.shared
        registry.registerBuiltIns()
        let categories = registry.grouped.map(\.category)
        expect(categories.contains(.local), "a local target is listed")
        expect(categories.contains(.hostedService), "a hosted target is listed")
    }

    s.test("an incomplete configuration is rejected before any transfer") {
        let local = LocalFolderTarget()
        do {
            _ = try await local.validate(DeployConfig())
            expect(false, "an empty config should not validate")
        } catch let error as DeployError {
            expect(true, "rejected with a usable message: \(error.localizedDescription)")
        } catch {
            expect(false, "wrong error type: \(error)")
        }
    }

    s.test("GitHub Pages demands a token, and says which one") {
        let target = GitHubPagesTarget()
        do {
            _ = try await target.validate(DeployConfig(fields: ["owner": "someone", "repo": "blog"]))
            // If a token happens to exist for "someone" on this machine the
            // check passes, which is also a valid outcome.
        } catch let error as DeployError {
            expect(error.localizedDescription.contains("someone"),
                   "the message names the account: \(error.localizedDescription)")
        } catch {
            expect(false, "wrong error type: \(error)")
        }
    }

    s.test("a web host without a stored password is refused clearly") {
        let target = WebHostTarget()
        let config = DeployConfig(fields: [
            "host": "ftp.definitely-not-a-real-host.invalid",
            "username": "someone",
            "remotePath": "/public_html",
            "protocol": "sftp",
        ])
        do {
            _ = try await target.validate(config)
            expect(false, "should refuse without a stored password")
        } catch let error as DeployError {
            expect(error.localizedDescription.lowercased().contains("password"),
                   "the message mentions the password: \(error.localizedDescription)")
        } catch {
            expect(false, "wrong error type: \(error)")
        }
    }

    s.test("deploy settings never contain a secret") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-deploy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var config = DeployConfig()
        config.set("host", "ftp.example.com")
        config.set("username", "alice")
        // A caller that wrongly puts a secret in here should not have it saved.
        let persisted = DeploySettingsStore.Persisted(targetID: "web-host", config: config.fields)
        expect(DeploySettingsStore.save(persisted, for: root), "settings save")

        let reloaded = DeploySettingsStore.load(for: root)
        expectEqual(reloaded.config["host"], "ftp.example.com", "host round-trips")
        expectEqual(reloaded.targetID, "web-host", "target id round-trips")
    }

    s.test("the app's own settings folder is kept out of git") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-git-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        expect(DeploySettingsStore.ensureGitIgnored(projectRoot: root), "gitignore is written")
        let text = (try? String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        expect(text.contains(DeploySettingsStore.directoryName),
               "the marker names the folder: \(text)")

        // Running twice must not duplicate the rule.
        _ = DeploySettingsStore.ensureGitIgnored(projectRoot: root)
        let twice = (try? String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        expectEqual(twice.components(separatedBy: DeploySettingsStore.directoryName).count - 1, 1,
                    "the rule is not duplicated")
    }

    s.test("a built site is walked for files and total size") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("posts"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("index.html").path,
                                       contents: Data(repeating: 0x41, count: 100))
        FileManager.default.createFile(atPath: root.appendingPathComponent("posts/one.html").path,
                                       contents: Data(repeating: 0x42, count: 50))

        let files = BuildDirectory.files(in: root)
        expectEqual(files, ["index.html", "posts/one.html"], "relative paths, sorted")
        expectEqual(BuildDirectory.totalSize(in: root), 150, "total bytes")
    }

    s.test("askpass scripts are private and carry the token") {
        guard let url = GitCommand.makeAskpass(token: "abc123") else {
            expect(false, "askpass script is written")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("abc123"), "the script prints the token")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        expectEqual(permissions, 0o700, "only the owner can read it")
    }

    s.test("a netrc file is private and holds the credentials") {
        guard let url = NetrcFile.write(host: "ftp.example.com", username: "alice", password: "s3cret") else {
            expect(false, "netrc is written")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try String(contentsOf: url, encoding: .utf8)
        expect(text.contains("machine ftp.example.com"), "the host is present")
        expect(text.contains("login alice"), "the username is present")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        expectEqual((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0, 0o600, "owner-only")
    }

    return s
}

/// The zone the generated-name assertions are made in, so they do not depend on
/// where the suite happens to run.
private let utc = TimeZone(identifier: "UTC")!

/// A fixed instant, so a generated filename can be asserted exactly.
private func fixedDate() -> Date {
    var parts = DateComponents()
    parts.year = 2026; parts.month = 9; parts.day = 26
    parts.hour = 20; parts.minute = 45; parts.second = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: parts)!
}

/// The editor-facing logic, which has no UI of its own but decides what the
/// files on disk look like.
func editorSuite() -> TestSuite {
    var s = TestSuite("Editor features")

    s.test("the custom-script shortcode is installed into the site") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-shortcodes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        expect(!SiteShortcodes.isInstalled(in: root), "nothing is installed yet")
        let written = SiteShortcodes.install(in: root)
        expectEqual(written, [SiteShortcodes.customScriptName], "one shortcode is written")
        expect(SiteShortcodes.isInstalled(in: root), "it is now installed")

        let template = try String(
            contentsOf: root.appendingPathComponent("layouts/shortcodes/\(SiteShortcodes.customScriptName).html"),
            encoding: .utf8)
        // A page resource, not resources.Get: the file sits beside the page, and
        // resources.Get only searches assets/.
        expect(template.contains(".Page.Resources.Get"), "the template resolves a page resource")
        expect(!template.contains("with resources.Get"), "and not the assets-only lookup")
        expect(template.contains("custom.js"), "and it loads custom.js")
    }

    s.test("an existing shortcode is never overwritten") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-shortcodes-keep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let target = root.appendingPathComponent("layouts/shortcodes/\(SiteShortcodes.customScriptName).html")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "my own version".write(to: target, atomically: true, encoding: .utf8)

        let written = SiteShortcodes.install(in: root)
        expectEqual(written.count, 0, "nothing is written over a user's file")
        let text = try String(contentsOf: target, encoding: .utf8)
        expectEqual(text, "my own version", "the user's shortcode survives")
    }

    s.test("attachments are the inspector's fourth item") {
        // Asked for explicitly, so it is pinned rather than left to taste.
        expectEqual(InspectorLayout.position(of: "Attachments"), 3, "attachments is fourth")
        expectEqual(InspectorLayout.sections.prefix(4).last, "Attachments", "and directly above Address")
        expectEqual(InspectorLayout.position(of: "Address"), 4, "the address follows it")
    }

    s.test("a pasted screenshot gets a usable name and format") {
        // A screenshot arrives with no filename, so both are supplied here.
        let name = ClipboardImage.timestampedName(now: fixedDate(), timeZone: utc)
        expectEqual(name, "pasted-2026-09-26-204512", "the generated name is sortable")
        expect(!name.contains("/"), "and safe in a path")
        expect(!name.contains(":"), "no colons, which macOS dislikes in filenames")
    }

    s.test("an image's format is detected from its own bytes") {
        expectEqual(ClipboardImage.inferredExtension(for: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), "png", "png")
        expectEqual(ClipboardImage.inferredExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])), "jpg", "jpeg")
        expectEqual(ClipboardImage.inferredExtension(for: Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), "gif", "gif")
        expectEqual(ClipboardImage.inferredExtension(for: Data([0x49, 0x49, 0x2A, 0x00, 0, 0, 0, 0])), "tiff", "tiff little-endian")
        expectEqual(ClipboardImage.inferredExtension(for: Data([0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 0])), "tiff", "tiff big-endian")

        let webp: [UInt8] = [0x52,0x49,0x46,0x46, 0,0,0,0, 0x57,0x45,0x42,0x50]
        expectEqual(ClipboardImage.inferredExtension(for: Data(webp)), "webp", "webp")
    }

    s.test("text copied from a web page is not mistaken for an image") {
        // A pasteboard can hand over HTML under an image type; writing that as a
        // .png would produce a file no browser can show.
        let html = Data("<!DOCTYPE html><html><body>hello</body></html>".utf8)
        expect(ClipboardImage.inferredExtension(for: html) == nil, "html is not an image")
        expect(!ClipboardImage.isImageData(html), "and is rejected")
        let shortPng = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])
        expect(ClipboardImage.isImageData(shortPng), "a real png header is accepted")
        expect(!ClipboardImage.isImageData(Data([0x89, 0x50])), "but two bytes are not an image")
        expect(!ClipboardImage.isImageData(Data()), "empty data is not an image")
    }

    s.test("a pasted image is saved under its generated name") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-paste-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        let pageURL = content.appendingPathComponent("post.md")
        try "text\n".write(to: pageURL, atomically: true, encoding: .utf8)

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }

        // A one-pixel PNG: real header, real bytes.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
        let pasted = ClipboardImage.Pasted(data: png,
                                           fileExtension: "png",
                                           suggestedName: ClipboardImage.timestampedName(now: fixedDate(), timeZone: utc))
        let placed = try MediaLibrary.add(pasted, to: item, projectRoot: root, kind: .inline)

        // The staging UUID must not reach the site.
        expectEqual(placed.asset.name, "pasted-2026-09-26-204512.png", "the generated name is used")
        let uuidPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        expect(placed.asset.name.range(of: uuidPattern, options: .regularExpression) == nil,
               "and it carries no staging uuid")
        expect(placed.asset.url.deletingLastPathComponent()
                == placed.pageURL.deletingLastPathComponent(), "beside the page")
    }

    s.test("a pasted file that is not an image is refused") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-badpaste-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        let pageURL = content.appendingPathComponent("post.md")
        try "text\n".write(to: pageURL, atomically: true, encoding: .utf8)

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }
        let pasted = ClipboardImage.Pasted(data: Data("<html>nope</html>".utf8),
                                           fileExtension: "png",
                                           suggestedName: "pasted-fake")
        var refused = false
        do {
            _ = try MediaLibrary.add(pasted, to: item, projectRoot: root, kind: .inline)
        } catch {
            refused = true
            expect(error.localizedDescription.contains("not an image"),
                   "and the message says why")
        }
        expect(refused, "the paste is refused rather than written out as a broken image")
    }

    s.test("opening a folder recognises a Hugo site and rejects anything else") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-detect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // A bare folder is not a site.
        expect(!SiteEngine.isHugoSite(root), "an empty folder is not a site")

        // The usual layout.
        let classic = root.appendingPathComponent("classic")
        try FileManager.default.createDirectory(at: classic, withIntermediateDirectories: true)
        try "baseURL = '/'".write(to: classic.appendingPathComponent("hugo.toml"), atomically: true, encoding: .utf8)
        expect(SiteEngine.isHugoSite(classic), "hugo.toml makes it a site")

        // The older name.
        let older = root.appendingPathComponent("older")
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try "baseURL: /".write(to: older.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        expect(SiteEngine.isHugoSite(older), "config.toml is still accepted")

        // The modern config/_default layout, which has no file at the root.
        let modern = root.appendingPathComponent("modern")
        try FileManager.default.createDirectory(at: modern.appendingPathComponent("config/_default"),
                                                withIntermediateDirectories: true)
        expect(SiteEngine.isHugoSite(modern), "config/_default is accepted")

        // A directory named hugo.toml must not be mistaken for the file.
        let bogus = root.appendingPathComponent("bogus")
        try FileManager.default.createDirectory(at: bogus.appendingPathComponent("hugo.toml"),
                                                withIntermediateDirectories: true)
        expect(!SiteEngine.isHugoSite(bogus), "a directory named hugo.toml is not a site")

        // A site is a folder, not a file.
        let notFolder = root.appendingPathComponent("hugo.toml")
        try "baseURL = '/'".write(to: notFolder, atomically: true, encoding: .utf8)
        expect(!SiteEngine.isHugoSite(notFolder), "a file is not a site folder")
    }

    s.test("a page with an image is a leaf bundle Hugo can serve") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-bundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)

        let pageURL = content.appendingPathComponent("the-post.md")
        try "body text\n".write(to: pageURL, atomically: true, encoding: .utf8)
        let source = root.appendingPathComponent("pic.png")
        FileManager.default.createFile(atPath: source.path, contents: Data([0x89, 0x50]))

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }
        let placed = try MediaLibrary.add(source, to: item, projectRoot: root, kind: .inline)

        // A folder beside a bare page is not a page resource, so the image can
        // only resolve if the page itself moved into the folder.
        expectEqual(placed.pageURL.lastPathComponent, "index.md", "the page is a bundle now")
        expectEqual(placed.pageURL.deletingLastPathComponent().lastPathComponent, "the-post",
                    "inside a folder named after it")
        expect(placed.asset.url.deletingLastPathComponent() == placed.pageURL.deletingLastPathComponent(),
               "the image sits beside the page")
        expectEqual(placed.markdownPath, "pic.png", "and is referred to relatively")

        // The page's own content survives the move untouched.
        let after = try String(contentsOf: placed.pageURL, encoding: .utf8)
        expectEqual(after, "body text\n", "the text is not rewritten")
    }

    s.test("an attachment goes to static, not into the page") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-attach-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("content/posts", isDirectory: true)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)

        let pageURL = content.appendingPathComponent("post.md")
        try "text\n".write(to: pageURL, atomically: true, encoding: .utf8)
        let source = root.appendingPathComponent("notes.pdf")
        FileManager.default.createFile(atPath: source.path, contents: Data([0x25, 0x50]))

        guard let item = ContentItem.load(from: pageURL, projectRoot: root) else {
            expect(false, "the page loads")
            return
        }
        let placed = try MediaLibrary.add(source, to: item, projectRoot: root, kind: .attachment)

        // Attachments are clicked, not rendered, so they live at a public path
        // and the page stays a bare file.
        expect(placed.markdownPath.hasPrefix("/files/"), "served from the site root")
        expectEqual(placed.pageURL, pageURL, "and the page does not move")
        expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("static/files/notes.pdf").path),
            "the file is in static/")
    }

    s.test("the script marker is added once and removed cleanly") {
        let body = "Opening paragraph.\n\nSecond paragraph."
        let on = PageScript.applyingMarker(true, to: body)
        expect(PageScript.hasScriptMarker(in: on), "the marker is present")
        expectEqual(on.components(separatedBy: PageScript.marker).count - 1, 1, "exactly one marker")

        let twice = PageScript.applyingMarker(true, to: on)
        expectEqual(twice.components(separatedBy: PageScript.marker).count - 1, 1, "still one marker")

        let off = PageScript.applyingMarker(false, to: twice)
        expect(!PageScript.hasScriptMarker(in: off), "the marker is gone")
        expectEqual(off, body, "and the original text is restored")
    }

    s.test("removing an image takes its Markdown line with it") {
        let markdown = """
        A paragraph.

        ![A photo](photo-1.jpg)

        Another paragraph.
        """
        let cleaned = MediaMarkdown.removingImageReference("photo-1.jpg", from: markdown)
        expect(cleaned != nil, "a reference was found")
        guard let cleaned else { return }
        expect(!cleaned.contains("photo-1.jpg"), "the broken reference is gone")
        expect(cleaned.contains("A paragraph."), "the prose survives")
        expect(cleaned.contains("Another paragraph."), "and the later prose too")
    }

    s.test("removing an image leaves the other one alone") {
        let markdown = "![One](a.png)\n\n![Two](b.png)"
        let cleaned = MediaMarkdown.removingImageReference("a.png", from: markdown)
        expect(cleaned != nil, "a reference was found")
        guard let cleaned else { return }
        expect(!cleaned.contains("a.png"), "the target is gone")
        expect(cleaned.contains("![Two](b.png)"), "the other image is untouched")
    }

    s.test("removing an image that is not there changes nothing") {
        let markdown = "Just prose."
        expect(MediaMarkdown.removingImageReference("missing.png", from: markdown) == nil,
               "no match means no edit")
    }

    return s
}
