// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Everything the new-site wizard collects before touching the disk.
struct NewSiteRequest {
    var title: String = ""
    var folderName: String = "my-site"
    var destinationFolder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites")
    var theme: Theme = ThemeCatalog.all[0]
    var installTheme: Bool = true
    var initGit: Bool = true
    var createFirstPost: Bool = true
    var createAboutPage: Bool = true
    var createContactPage: Bool = false
    var baseURL: String = "https://example.org/"
    var languageCode: String = "en-us"
    var author: String = ""
    var description: String = ""
    var sectionName: String = "posts"
    var copyright: String = ""

    // MARK: Hosting
    //
    // Asked during setup rather than at publish time, because the choice changes
    // the site's baseURL and that is far easier to get right once than to
    // unpick later — a wrong baseURL produces wrong absolute URLs on every page.

    /// Where the finished site will be published.
    enum HostingChoice: String, CaseIterable, Identifiable {
        case decideLater = "Decide later"
        case githubPages = "GitHub Pages"
        case webHost = "My web host (FTP/SFTP)"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .decideLater: return "clock"
            case .githubPages: return "chevron.left.forwardslash.chevron.right"
            case .webHost: return "server.rack"
            }
        }

        var blurb: String {
            switch self {
            case .decideLater:
                return "Build the site now; choose a host whenever you are ready to publish."
            case .githubPages:
                return "Free hosting from a GitHub repository. We will set the address to yourusername.github.io."
            case .webHost:
                return "Upload over SFTP or FTP to the host you already pay for."
            }
        }

        /// The target id this maps to in the publish registry.
        var targetID: String {
            switch self {
            case .decideLater: return LocalFolderTarget.descriptor.id
            case .githubPages: return GitHubPagesTarget.descriptor.id
            case .webHost: return WebHostTarget.descriptor.id
            }
        }
    }

    var hosting: HostingChoice = .decideLater
    var githubUser: String = ""
    var githubRepo: String = ""
    var hostName: String = ""
    var hostUser: String = ""
    var hostRemotePath: String = "/public_html"

    var destination: URL { destinationFolder.appendingPathComponent(folderName) }

    /// The base URL implied by the hosting choice. A site pointed at the wrong
    /// host gets an absolute URL in every built page, so this is derived rather
    /// than typed twice.
    func resolvedBaseURL() -> String {
        switch hosting {
        case .githubPages:
            let owner = githubUser.isEmpty ? "yourname" : githubUser
            let repo = githubRepo.isEmpty ? slugOfFolderName : githubRepo
            return "https://\(owner.lowercased()).github.io/\(repo)/"
        case .webHost, .decideLater:
            return baseURL
        }
    }

    var slugOfFolderName: String { SiteEngine.slugify(folderName) }

    /// Whether the setup is complete enough to build without surprises.
    var hostingIsComplete: Bool {
        switch hosting {
        case .decideLater: return true
        case .githubPages: return !githubUser.isEmpty && !githubRepo.isEmpty
        case .webHost: return !hostName.isEmpty && !hostUser.isEmpty
        }
    }
}

/// Runs the whole site setup as one observable sequence of steps,
/// so the wizard can show real progress instead of a spinner.
@MainActor
final class SiteCreator: ObservableObject {

    init() {}

    struct Step: Identifiable {
        var id = UUID()
        var title: String
        var detail: String
        var state: State = .pending
        enum State { case pending, running, done, failed }
    }

    enum SiteKind: String, CaseIterable, Identifiable {
        case blog = "Blog"
        case docs = "Documentation"
        case portfolio = "Portfolio"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .blog: return "text.bubble.fill"
            case .docs: return "book.closed.fill"
            case .portfolio: return "person.crop.rectangle.stack.fill"
            }
        }

        var blurb: String {
            switch self {
            case .blog: return "Posts, tags and an archive."
            case .docs: return "A searchable reference with a sidebar."
            case .portfolio: return "Projects, writing and contact."
            }
        }

        var defaultSection: String {
            switch self {
            case .blog: return "posts"
            case .docs: return "docs"
            case .portfolio: return "projects"
            }
        }
    }

    @Published public var steps: [Step] = []
    @Published private(set) var isRunning = false
    @Published private(set) var finishedRoot: URL?
    @Published public var error: String?
    /// Set when the wizard was opened from the File menu rather than cold launch.
    @Published public var startedFromMenu = false

    private var currentRoot: URL?

    func begin(with request: NewSiteRequest, kind: SiteKind) async -> URL? {
        isRunning = true
        error = nil
        finishedRoot = nil
        steps = [
            Step(title: "Create the project", detail: "Running hugo new site"),
            Step(title: "Write your settings", detail: "Title, language, base URL"),
            Step(title: kind == .docs ? "Install the documentation theme" : "Install your theme",
                 detail: request.installTheme ? "Fetching \(request.theme.repo)" : "Skipped"),
            Step(title: "Add a Git repository", detail: request.initGit ? "git init + first commit" : "Skipped"),
            Step(title: "Add the app's shortcodes", detail: "So embeds and scripts work"),
            Step(title: "Create your first pages", detail: "So the site is never empty"),
            Step(title: "Build it once", detail: "Proving it works before you see it")
        ]

        do {
            try await createProject(request)
            try await writeConfig(request, kind: kind)
            if request.installTheme {
                try await installTheme(request.theme, request: request)
            }
            if request.initGit {
                await initGit(request)
            }
            try await installShortcodes()
            saveHostingChoice(request)
            try await seedContent(request, kind: kind)
            try await firstBuild(request)
            isRunning = false
            finishedRoot = currentRoot
            return currentRoot
        } catch {
            isRunning = false
            self.error = error.localizedDescription
            failCurrentStep()
            return nil
        }
    }

    // MARK: - Steps

    private func createProject(_ request: NewSiteRequest) async throws {
        mark(0, .running)
        do {
            try FileManager.default.createDirectory(at: request.destinationFolder, withIntermediateDirectories: true)
        } catch {
            throw SiteCreationError.cannotCreateFolder(request.destinationFolder, error)
        }
        guard !FileManager.default.fileExists(atPath: request.destination.path) else {
            throw SiteCreationError.folderExists(request.destination)
        }

        // `hugo new site` takes the target path directly.
        let result = await HFH.run(["new", "site", request.destination.path], workingDirectory: nil) { _ in }
        guard result?.succeeded == true, FileManager.default.fileExists(atPath: request.destination.path) else {
            throw SiteCreationError.hugoFailed("hugo new site")
        }
        currentRoot = request.destination
        mark(0, .done)
    }

    private func writeConfig(_ request: NewSiteRequest, kind: SiteKind) async throws {
        mark(1, .running)
        guard let root = currentRoot else { throw SiteCreationError.noProject }
        var config = SiteConfig()
        config.title = request.title.isEmpty ? request.folderName.capitalized : request.title
        // The hosting choice decides the address; a typed baseURL is only used
        // when the target is undecided or a plain web host.
        config.baseURL = request.resolvedBaseURL()
        config.languageCode = request.languageCode
        config.author = request.author
        config.description = request.description.isEmpty ? "A site made with Hugo for Humans." : request.description
        config.copyright = request.copyright.isEmpty
            ? "© \(currentYear)"
            : request.copyright
        config.theme = request.installTheme ? request.theme.name : ""
        config.taxonomies = kind == .docs ? ["tags"] : ["tags", "categories"]
        try config.write(to: root)
        mark(1, .done)
    }

    private func installTheme(_ theme: Theme, request: NewSiteRequest) async throws {
        mark(2, .running)
        guard let root = currentRoot else { throw SiteCreationError.noProject }
        let themesDir = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        let target = themesDir.appendingPathComponent(theme.name)

        // `hugo mod get` would be the idiomatic route, but it shells out to Go,
        // which most people do not have. A shallow git clone is the documented
        // fallback and needs nothing but git.
        let result = await HFH.run(["mod", "init"], workingDirectory: root) { _ in }
        _ = result

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--depth", "1", theme.repoURL!.absoluteString, target.path]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            throw SiteCreationError.themeInstallFailed(theme.name, error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: target.appendingPathComponent("hugo.toml").path)
                || FileManager.default.fileExists(atPath: target.appendingPathComponent("theme.toml").path)
                || FileManager.default.fileExists(atPath: target.appendingPathComponent("config.toml").path) else {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw SiteCreationError.themeInstallFailed(theme.name, output.isEmpty ? "The repository has no theme configuration." : output)
        }

        // A git repo inside the site would nest repos; Hugo does not need it.
        let gitDir = target.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            try? FileManager.default.removeItem(at: gitDir)
        }
        mark(2, .done)
    }

    private func initGit(_ request: NewSiteRequest) async {
        mark(3, .running)
        guard let root = currentRoot else { return }
        await runGit(["init", "-q"], in: root)
        await runGit(["add", "-A"], in: root)
        await runGit(["-c", "user.name=Hugo for Humans",
                      "-c", "user.email=you@example.com",
                      "commit", "-qm", "Initial site"], in: root)
        mark(3, .done)
    }

    private func runGit(_ args: [String], in cwd: URL) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }

    /// Writes the shortcodes the editor's features depend on.
    ///
    /// Done at creation time so a site made in the wizard can use the custom
    /// script box immediately, rather than failing later with an unknown
    /// shortcode error in the middle of writing.
    private func installShortcodes() async throws {
        mark(4, .running)
        guard let root = currentRoot else { throw SiteCreationError.noProject }
        _ = SiteShortcodes.install(in: root)
        mark(4, .done)
    }

    /// Records the chosen target as the site's default, so the publish screen
    /// opens on the one the user already picked rather than the first in the list.
    private func saveHostingChoice(_ request: NewSiteRequest) {
        guard let root = currentRoot else { return }
        _ = DeploySettingsStore.ensureGitIgnored(projectRoot: root)
        var settings = DeploySettingsStore.load(for: root)

        var config = DeployConfig(fields: settings.config)
        switch request.hosting {
        case .githubPages:
            settings.targetID = GitHubPagesTarget.descriptor.id
            config.set("owner", request.githubUser)
            config.set("repo", request.githubRepo)
            config.set("branch", "gh-pages")
        case .webHost:
            settings.targetID = WebHostTarget.descriptor.id
            config.set("host", request.hostName)
            config.set("username", request.hostUser)
            config.set("remotePath", request.hostRemotePath)
            config.set("protocol", "sftp")
        case .decideLater:
            settings.targetID = LocalFolderTarget.descriptor.id
        }
        settings.config = config.fields
        _ = DeploySettingsStore.save(settings, for: root)
    }

    private func seedContent(_ request: NewSiteRequest, kind: SiteKind) async throws {
        mark(5, .running)
        guard let root = currentRoot else { throw SiteCreationError.noProject }
        let section = request.sectionName.isEmpty ? kind.defaultSection : SiteEngine.slugify(request.sectionName)

        if request.createFirstPost {
            _ = await createContent(relative: "\(section)/\(SiteEngine.slugify(request.title.isEmpty ? "hello-world" : request.title)).md",
                                    root: root, kind: nil, title: request.title.isEmpty ? "Hello World" : request.title)
        }
        if request.createAboutPage {
            _ = await createContent(relative: "about.md", root: root, kind: "page", title: "About")
        }
        if request.createContactPage {
            _ = await createContent(relative: "contact.md", root: root, kind: "page", title: "Contact")
        }
        mark(5, .done)
    }

    @discardableResult
    private func createContent(relative: String, root: URL, kind: String?, title: String) async -> Bool {
        var args = ["new", "content", relative]
        if let kind { args += ["--kind", kind] }
        let result = await HFH.run(args, workingDirectory: root) { _ in }
        guard result?.succeeded == true else { return false }
        // Give the page a real title instead of the slug Hugo derives.
        let url = root.appendingPathComponent("content/\(relative)")
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            var fm = FrontMatter.parse(raw)
            fm["title"] = .string(title)
            if fm.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fm.body = defaultBody(for: title)
            }
            try? fm.serialized().write(to: url, atomically: true, encoding: .utf8)
        }
        return true
    }

    private func defaultBody(for title: String) -> String {
        """
        Write here in plain language. Formatting is Markdown, so:

        - **Bold**, *italic*, and `code` all work
        - Lists, links and images are one keystroke away
        - Your preview updates as you type

        This is your first page. Everything you see in the app is a real file
        in a folder you own, and real Hugo doing the work.
        """
    }

    private func firstBuild(_ request: NewSiteRequest) async throws {
        mark(6, .running)
        guard let root = currentRoot else { throw SiteCreationError.noProject }
        let result = await HFH.run(["-D"], workingDirectory: root) { _ in }
        guard let result else { throw SiteCreationError.hugoFailed("hugo") }
        let text = result.combined
        // A first build that errors is not a failure worth hiding, but it should
        // not block the user from opening their site either.
        if !result.succeeded || text.contains("ERROR") {
            throw SiteCreationError.hugoFailed(text.contains("ERROR")
                ? (Builder.firstError(in: text) ?? "Hugo reported an error")
                : "Hugo exited with status \(result.status)")
        }
        mark(6, .done)
    }

    private var currentYear: String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return String(year)
    }

    // MARK: - Step state

    private func mark(_ index: Int, _ state: Step.State) {
        guard steps.indices.contains(index) else { return }
        steps[index].state = state
    }

    private func failCurrentStep() {
        if let index = steps.firstIndex(where: { $0.state == .running }) {
            steps[index].state = .failed
        }
    }
}

enum SiteCreationError: LocalizedError {
    case cannotCreateFolder(URL, Error)
    case folderExists(URL)
    case noProject
    case hugoFailed(String)
    case themeInstallFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFolder(let url, let error):
            return "Could not create \(url.path): \(error.localizedDescription)"
        case .folderExists(let url):
            return "\(url.lastPathComponent) already exists in that folder. Choose another name or remove it first."
        case .noProject:
            return "The project was not created."
        case .hugoFailed(let detail):
            return "Hugo reported a problem: \(detail)"
        case .themeInstallFailed(let theme, let detail):
            return "Could not install the \(theme) theme. \(detail)"
        }
    }
}
