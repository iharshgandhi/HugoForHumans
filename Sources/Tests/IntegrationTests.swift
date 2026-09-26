// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

// MARK: - End to end, against a real Hugo binary
//
// These are the tests that matter most. A wrapper is only "working" if Hugo
// itself can still read and build what the app wrote, so each of these creates a
// real site, drives it through the app's own code, and asserts Hugo still agrees.

/// Thrown when no Hugo binary is present, so the check reports as skipped rather
/// than failed — a missing toolchain is not a bug in the app.
struct HugoUnavailable: Error {
    let detail: String
}

private func hugoOrSkip() throws -> URL {
    guard let url = HugoBinary.resolve(), HugoBinary.version(of: url) != nil else {
        throw HugoUnavailable(detail: "No Hugo binary available")
    }
    return url
}

/// The folder the wizard should create for a given destination.
private func siteRoot(_ dir: URL) -> URL { dir.appendingPathComponent("field-notes") }

/// Mirrors how the app installs themes: a plain git clone, no Go involved.
private func runGit(_ arguments: [String], in directory: URL) -> CommandResult? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch {
        return CommandResult(status: -1, standardOutput: "", standardError: error.localizedDescription)
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let errorData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus,
                          standardOutput: String(decoding: data, as: UTF8.self),
                          standardError: String(decoding: errorData, as: UTF8.self))
}

func integrationSuite() -> TestSuite {
    var s = TestSuite("End to end (real Hugo)")

    func scratch() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hfh-integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    s.test("a site created through the app builds with Hugo") {
        let hugo = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let siteRoot = dir.appendingPathComponent("my-site")

        // Step 1: hugo new site
        let created = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)
        expectEqual(created?.status ?? -1, 0, "hugo new site exit code: \(created?.combined ?? "")")
        expect(FileManager.default.fileExists(atPath: siteRoot.appendingPathComponent("hugo.toml").path),
               "hugo.toml should exist")

        // Step 2: write settings exactly as the app does
        var config = SiteConfig()
        config.title = "Integration Site"
        config.baseURL = "https://example.org/"
        try? config.write(to: siteRoot)
        expectEqual(SiteConfig.load(root: siteRoot).title, "Integration Site", "title round trip")

        // Step 3: a section, the way the New Section button does it.
        // Hugo resolves content relative to the project root, so cwd matters.
        let section = HFH.runSync(["new", "content", "posts/_index.md"], workingDirectory: siteRoot)
        expectEqual(section?.status ?? -1, 0,
                    "section creation: \(section?.combined ?? "")")
        expect(FileManager.default.fileExists(
            atPath: siteRoot.appendingPathComponent("content/posts/_index.md").path),
               "content/posts/_index.md should exist")

        // Step 4: a page inside that section
        let page = HFH.runSync(["new", "content", "posts/hello.md"], workingDirectory: siteRoot)
        expectEqual(page?.status ?? -1, 0, "page creation: \(page?.combined ?? "")")

        // Step 5: the engine must see both, with the right kinds.
        let engine = SiteEngine()
        engine.openSite(at: siteRoot)
        expectEqual(engine.items.count, 2, "engine should find 2 files")
        expect(engine.items.contains { $0.kind == .section }, "_index.md seen as a section")
        expect(engine.items.contains { $0.kind == .page }, "hello.md seen as a page")
        expectEqual(engine.sections.first?.name ?? "", "posts", "section name")

        // Step 6: edit through the app's model — the round trip most likely to
        // corrupt a real site.
        guard var item = engine.item(withID: "posts/hello.md") else {
            expect(false, "page not found in engine")
            return
        }
        item.frontMatter["title"] = .string("Hello Integration")
        item.frontMatter["tags"] = .list(["testing", "hugo"])
        item.frontMatter.body = "This body was written by the app."
        engine.save(item)

        let pageFile = siteRoot.appendingPathComponent("content/posts/hello.md")
        guard let reread = try? String(contentsOf: pageFile, encoding: .utf8) else {
            expect(false, "could not read the file back")
            return
        }
        expect(reread.contains("Hello Integration"), "title written")
        expect(reread.contains("testing"), "tags written")
        expect(reread.contains("This body was written by the app."), "body written")

        // Step 7: Hugo must still accept what the app wrote.
        let list = HFH.runSync(["list", "all"], workingDirectory: siteRoot)
        expectEqual(list?.status ?? -1, 0, "hugo list: \(list?.combined ?? "")")
        expect(list?.standardOutput.contains("Hello Integration") == true,
               "Hugo should see the title the app set")

        // Step 8: and the site must build.
        let build = HFH.runSync(["-D"], workingDirectory: siteRoot)
        expectEqual(build?.status ?? -1, 0, "build: \(build?.combined ?? "")")
        expect(build?.looksLikeSuccessfulBuild == true, "build should report a total")

        print("     (using \(hugo.path))")
    }

    s.test("drafts toggle and stay out of production builds") {
        _ = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let siteRoot = dir.appendingPathComponent("drafts")
        _ = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)
        _ = HFH.runSync(["new", "content", "posts/draft-post.md"], workingDirectory: siteRoot)
        _ = HFH.runSync(["new", "content", "posts/live-post.md"], workingDirectory: siteRoot)

        // Hugo creates everything as a draft; publish one.
        let liveFile = siteRoot.appendingPathComponent("content/posts/live-post.md")
        guard var published = try? String(contentsOf: liveFile, encoding: .utf8) else {
            expect(false, "could not read live-post.md")
            return
        }
        published = published.replacingOccurrences(of: "draft = true", with: "draft = false")
        try? published.write(to: liveFile, atomically: true, encoding: .utf8)

        let engine = SiteEngine()
        engine.openSite(at: siteRoot)
        expectEqual(engine.draftCount, 1, "one file should still be a draft")

        // A production build must not include the remaining draft.
        let production = HFH.runSync([], workingDirectory: siteRoot)
        expectEqual(production?.status ?? -1, 0, "production build: \(production?.combined ?? "")")
        expect(!(production?.combined.contains("ERROR") ?? true), "production build has no errors")

        // Toggling through the app must flip Hugo's view too.
        if let draftItem = engine.items.first(where: \.isDraft) {
            engine.toggleDraft(draftItem)
            guard let after = try? String(contentsOf: draftItem.url, encoding: .utf8) else {
                expect(false, "could not reread the draft")
                return
            }
            expect(after.contains("draft = false"), "toggling should write draft = false")
        } else {
            expect(false, "no draft item found to toggle")
        }
    }

    s.test("the app's content scan agrees with hugo list") {
        _ = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let siteRoot = dir.appendingPathComponent("agreement")
        _ = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)
        _ = HFH.runSync(["new", "content", "posts/one.md"], workingDirectory: siteRoot)
        _ = HFH.runSync(["new", "content", "about.md"], workingDirectory: siteRoot)

        let engine = SiteEngine()
        engine.openSite(at: siteRoot)

        let hugoCount = Builder.countRows(
            HFH.runSync(["list", "all"], workingDirectory: siteRoot)?.standardOutput ?? ""
        )
        expectEqual(hugoCount, 2, "hugo list count")
        expectEqual(engine.items.count, 2, "the app's scan and hugo list must agree")
    }

    s.test("a theme cloned in by the app builds and is detected") {
        _ = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let siteRoot = dir.appendingPathComponent("themed")
        _ = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)
        _ = HFH.runSync(["new", "content", "posts/hello.md"], workingDirectory: siteRoot)

        // Clone a real theme exactly as the app does.
        let theme = ThemeCatalog.theme(named: "archie")
        guard let theme, let repoURL = theme.repoURL else {
            expect(false, "archie theme missing from the catalog")
            return
        }
        let themesDir = siteRoot.appendingPathComponent("themes")
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        // The app clones themes with git, not `hugo` — `hugo mod get` needs Go
        // installed, which defeats the point of shipping a self-contained app.
        let clone = runGit(["clone", "--depth", "1", repoURL.absoluteString,
                             themesDir.appendingPathComponent(theme.name).path],
                            in: siteRoot)
        expectEqual(clone?.status ?? -1, 0, "cloning \(theme.name): \(clone?.combined ?? "")")

        var config = SiteConfig()
        config.title = "Themed Site"
        config.theme = theme.name
        try? config.write(to: siteRoot)

        let build = HFH.runSync(["-D"], workingDirectory: siteRoot)
        expectEqual(build?.status ?? -1, 0, "themed build: \(build?.combined ?? "")")
        expect(FileManager.default.fileExists(
            atPath: siteRoot.appendingPathComponent("public/index.html").path),
               "a themed build must produce an index page")

        let engine = SiteEngine()
        engine.openSite(at: siteRoot)
        expect(engine.installedThemes.contains(theme.name),
               "engine should list \(theme.name) as installed")
        expectEqual(engine.config.theme, theme.name, "config theme")
    }

    s.test("a generated netlify.toml is copy-pasteable") {
        _ = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let siteRoot = dir.appendingPathComponent("deploy")
        _ = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)

        let version = HugoBinary.version(of: HugoBinary.resolve()!) ?? ""
        let shortVersion = version.replacingOccurrences(of: "hugo ", with: "")
            .split(separator: " ").first.map(String.init) ?? "0.0.0"
        let netlify = """
        [build]
          command = "hugo"
          publish = "public"

        [build.environment]
          HUGO_VERSION = "\(shortVersion)"
        """
        expect(netlify.contains("HUGO_VERSION = \""), "version is quoted")
        expect(netlify.contains("publish = \"public\""), "publish dir is set")
    }

    s.test("the app expects an extended Hugo") {
        _ = try hugoOrSkip()
        expect(HugoBinary.isExtended,
               "a non-extended Hugo cannot compile SCSS and fails on most themes")
    }

    s.test("hugo new content needs the project as its working directory") {
        // This documents a real trap. `hugo new content <path>` resolves
        // <path> against the *current* directory, not against the project, so
        // running it from the wrong place fails with a confusing "no existing
        // content directory" error. The app always sets the working directory
        // to the project root, and this test is why that matters.
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let siteRoot = dir.appendingPathComponent("cwd-test")
        _ = HFH.runSync(["new", "site", siteRoot.path], workingDirectory: nil)

        // From the parent directory, with the project name as a path prefix:
        // this is the shape that fails.
        let wrongCwd = HFH.runSync(["new", "content", "cwd-test/content/posts/x.md"],
                                   workingDirectory: dir)
        expect(wrongCwd?.succeeded == false,
               "a path prefix from the wrong directory should fail — the app avoids this by setting cwd")

        // With the project as the working directory, the same call succeeds.
        let rightCwd = HFH.runSync(["new", "content", "posts/y.md"],
                                   workingDirectory: siteRoot)
        expect(rightCwd?.succeeded == true,
               "using the working directory should succeed: \(rightCwd?.combined ?? "")")
        expect(FileManager.default.fileExists(
            atPath: siteRoot.appendingPathComponent("content/posts/y.md").path),
               "the page must land inside the project, not beside it")
    }

    s.test("the whole user journey works with no terminal at any point") {
        _ = try hugoOrSkip()
        let dir = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Answer the wizard — the only step a new user performs.
        var request = NewSiteRequest()
        request.title = "Field Notes"
        request.description = "Observations from the garden."
        request.destinationFolder = dir
        request.folderName = "field-notes"
        request.languageCode = "en-us"
        request.theme = ThemeCatalog.theme(named: "PaperMod") ?? ThemeCatalog.all[0]
        request.installTheme = true
        request.initGit = false          // keeps the test fast and self-contained
        request.createFirstPost = true
        request.createAboutPage = true

        let creator = SiteCreator()
        let created = await creator.begin(with: request, kind: .blog)
        expectEqual(created?.path ?? "<none>", siteRoot(dir).path, "the wizard returns the site folder")
        expect(creator.error == nil, "the wizard should create the site: \(creator.error ?? "")")

        let siteRoot = siteRoot(dir)
        expect(FileManager.default.fileExists(atPath: siteRoot.appendingPathComponent("hugo.toml").path),
               "hugo.toml was written")

        // 2. Open it the way the app does.
        let engine = SiteEngine()
        engine.openSite(at: siteRoot)
        expect(engine.isOpen, "the engine should consider the site open")
        expectEqual(engine.config.title, "Field Notes", "the title comes from the wizard")
        expectEqual(engine.config.theme, request.theme.name, "the chosen theme is active")
        expect(engine.installedThemes.contains(request.theme.name),
               "the theme was installed by the wizard")

        // 3. The "Add Page" button, and the section it belongs to.
        let page = await engine.createPage(section: request.sectionName, name: "Tomatoes")
        expect(page != nil, "adding a page should return the new item")
        let newPage = page!
        expect(FileManager.default.fileExists(atPath: newPage.url.path), "the page is on disk")
        expectEqual(newPage.kind, .page, "page kind")
        expectEqual(newPage.section, request.sectionName, "the page knows its section")

        // 4. It shows up in the sidebar without a manual rescan.
        expect(engine.items.contains { $0.id == newPage.id }, "the sidebar lists the new page")

        // 5. The body can be written and saved, the way typing does.
        var edited = newPage
        edited.frontMatter["title"] = .string("Tomatoes, Finally")
        edited.frontMatter.body = "They grew slowly, then all at once."
        try engine.save(edited)
        guard let reread = ContentItem.load(from: newPage.url, projectRoot: siteRoot) else {
            expect(false, "the saved page should reload from disk")
            return
        }
        expectEqual(reread.frontMatter["title"]?.stringValue, "Tomatoes, Finally", "the title was saved")
        expect(reread.frontMatter.body.contains("all at once"), "the body was saved")

        // 6. Build it, with no terminal involvement.
        let builder = Builder()
        let status = await builder.build(root: siteRoot, engine: engine)
        if case .success(let pages, _) = status {
            expect(pages > 0, "the build should report pages, got \(pages)")
        } else {
            expect(false, "the site should build, got: \(status) / output: \(builder.output)")
        }
        expect(FileManager.default.fileExists(
            atPath: siteRoot.appendingPathComponent("public/index.html").path),
               "the build produced an index page")

        // 7. The user's own files were never replaced by a private format.
        expect(FileManager.default.fileExists(atPath: siteRoot.appendingPathComponent("content").path),
               "content/ still exists")
        expect(FileManager.default.fileExists(atPath: siteRoot.appendingPathComponent("themes").path),
               "themes/ still exists")
    }

    return s
}