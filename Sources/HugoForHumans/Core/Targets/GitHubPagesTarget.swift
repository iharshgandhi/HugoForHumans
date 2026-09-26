// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Publishes to GitHub Pages by pushing the built site to the `gh-pages` branch.
///
/// `gh` is not installed and cannot be assumed, so this drives `git` directly.
/// The token comes from the Keychain, never from a file in the project, and is
/// passed to git through a temporary askpass script rather than on the command
/// line — command lines are visible in `ps` to every process on the machine,
/// and a token there leaks.
struct GitHubPagesTarget: PublishTarget {

    static let descriptor = TargetDescriptor(
        id: "github-pages",
        name: "GitHub Pages",
        tagline: "Free hosting from a GitHub repository",
        icon: "chevron.left.forwardslash.chevron.right",
        category: .hostedService,
        needsCredentials: true,
        fields: [
            .text("owner", "GitHub username", placeholder: "iharshgandhi",
                  help: "The account that owns the repository."),
            .text("repo", "Repository name", placeholder: "my-blog",
                  help: "Will be created if it does not exist."),
            .text("branch", "Pages branch", placeholder: "gh-pages",
                  help: "GitHub Pages serves this branch. gh-pages is the convention."),
            .text("customDomain", "Custom domain (optional)", placeholder: "example.com",
                  help: "Leave blank to use yourusername.github.io."),
            .choice("includeCNAME", "Create a CNAME file", options: ["true", "false"]),
        ],
        notes: """
        You need a GitHub personal access token with the `repo` scope. \
        Create one at github.com/settings/tokens. It is stored in your Mac Keychain, \
        never in the project folder.
        """
    )

    // MARK: - Validate

    func validate(_ config: DeployConfig) async throws -> [String] {
        let owner = config.value("owner").trimmingCharacters(in: .whitespaces)
        let repo = config.value("repo").trimmingCharacters(in: .whitespaces)
        guard !owner.isEmpty else { throw DeployError.notConfigured("your GitHub username") }
        guard !repo.isEmpty else { throw DeployError.notConfigured("a repository name") }

        var notes: [String] = []
        guard let token = try CredentialVault.get(.githubAccount(owner)), !token.isEmpty else {
            throw DeployError.missingCredential("a GitHub token for \(owner)")
        }
        notes.append("Token found in your Keychain.")

        // A live check, so a wrong token is caught before any files move.
        // `gh` is not assumed to exist, so this asks git, which always does.
        let probe = await GitCommand.run(["ls-remote", "--heads", "https://github.com/\(owner)/\(owner).git"],
                                         token: token)
        if !probe.succeeded {
            let detail = probe.output.lowercased()
            if detail.contains("authentication") || detail.contains("terminal prompts disabled")
                || detail.contains("could not read username") {
                throw DeployError.authenticationFailed(
                    "GitHub rejected the token. Check that it has the `repo` scope and has not expired.")
            }
            // A network failure is not a credential failure, so it should not be
            // reported as one.
            notes.append("Could not reach GitHub to verify the token; the deploy will try anyway.")
        }
        return notes
    }

    // MARK: - Deploy

    func deploy(_ build: BuildOutput, config: DeployConfig,
                report: @escaping @Sendable (String) -> Void) async throws -> DeployReport {
        let started = Date()
        let owner = config.value("owner").trimmingCharacters(in: .whitespaces)
        let repoName = config.value("repo").trimmingCharacters(in: .whitespaces)
        let branch = config.value("branch").trimmingCharacters(in: .whitespaces).isEmpty
            ? "gh-pages" : config.value("branch").trimmingCharacters(in: .whitespaces)
        let domain = config.value("customDomain").trimmingCharacters(in: .whitespaces)

        guard let token = try CredentialVault.get(.githubAccount(owner)), !token.isEmpty else {
            throw DeployError.missingCredential("a GitHub token for \(owner)")
        }

        let siteURL = domain.isEmpty
            ? "https://\(owner).github.io/\(repoName)/"
            : "https://\(domain)/"

        // The built output is pushed from a scratch clone, never from the source
        // project: the project's own history and branches must not be touched.
        let workdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-pages-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        } catch {
            throw DeployError.transferFailed("Could not make a working folder: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: workdir) }

        // 1. The repository. Create it if it is missing.
        report("Checking \(owner)/\(repoName)")
        let exists = await GitCommand.run(
            ["ls-remote", "--heads", "https://github.com/\(owner)/\(repoName).git"],
            token: token
        )
        var created = false
        if !exists.succeeded {
            report("Creating the repository")
            let create = await GitCommand.run(
                ["-c", "user.name=\(owner)",
                 "repo", "create", "\(owner)/\(repoName)",
                 "--public", "--description", "Published with Hugo for Humans"],
                token: token
            )
            guard create.succeeded else {
                throw DeployError.transferFailed(
                    "Could not create the repository: \(Self.lastLine(create.output))")
            }
            created = true
        }

        // 2. Clone the pages branch into scratch, or start it.
        let remote = "https://github.com/\(owner)/\(repoName).git"
        let hasBranch = await GitCommand.run(
            ["ls-remote", "--heads", remote, "refs/heads/\(branch)"], token: token)
        if hasBranch.succeeded, !hasBranch.output.isEmpty {
            report("Fetching the existing \(branch) branch")
            let clone = await GitCommand.run(["clone", "--depth", "1", "--branch", branch, remote, workdir.path],
                                             token: token)
            guard clone.succeeded else {
                throw DeployError.transferFailed("Could not clone: \(Self.lastLine(clone.output))")
            }
        } else {
            report("Starting a new \(branch) branch")
            _ = await GitCommand.run(["init", "-q", workdir.path], token: token)
            _ = await GitCommand.run(["remote", "add", "origin", remote], token: token, workingDirectory: workdir)
            _ = await GitCommand.run(["checkout", "-q", "-b", branch], token: token, workingDirectory: workdir)
        }

        // 3. Replace the branch contents with the fresh build.
        report("Copying \(build.fileCount) files into the branch")
        let staging = workdir.appendingPathComponent("__staging__", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [build.directory.path, staging.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw DeployError.transferFailed("Could not stage the build output.")
            }
        } catch let error as DeployError {
            throw error
        } catch {
            throw DeployError.transferFailed(error.localizedDescription)
        }

        // Clear whatever the branch had, then move the new build in. `.nojekyll`
        // is required or GitHub Pages will not serve files beginning with `_`.
        report("Replacing the previous build")
        _ = await GitCommand.run(["rm", "-rq", "--cached", "."], token: token, workingDirectory: workdir)
        if FileManager.default.fileExists(atPath: workdir.appendingPathComponent(".nojekyll").path) == false {
            FileManager.default.createFile(atPath: workdir.appendingPathComponent(".nojekyll").path, contents: Data())
        }
        if !domain.isEmpty, config.bool("includeCNAME", default: true) {
            try? domain.write(to: workdir.appendingPathComponent("CNAME"), atomically: true, encoding: .utf8)
        }
        _ = await GitCommand.run(["add", "-A", "."], token: token, workingDirectory: workdir)
        _ = await GitCommand.run(["rm", "-rq", "-f", "__staging__"],
                                  token: token, workingDirectory: workdir)

        // 4. Commit and push.
        report("Committing")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let commit = await GitCommand.run(
            ["-c", "user.name=\(owner)", "-c", "user.email=\(owner)@users.noreply.github.com",
             "commit", "-q", "-m", "Published \(stamp)"],
            token: token, workingDirectory: workdir
        )
        // An empty commit is not a failure — nothing changed since last publish.
        if !commit.succeeded, !commit.output.lowercased().contains("nothing to commit") {
            throw DeployError.transferFailed("Commit failed: \(Self.lastLine(commit.output))")
        }

        report("Pushing to \(owner)/\(repoName)")
        let push = await GitCommand.run(["push", "origin", "HEAD:\(branch)"],
                                        token: token, workingDirectory: workdir)
        guard push.succeeded else {
            let detail = push.output.lowercased()
            if detail.contains("authentication") || detail.contains("permission") {
                throw DeployError.authenticationFailed("The token was refused on push. Check the repo scope.")
            }
            if detail.contains("rejected") {
                throw DeployError.transferFailed(
                    "The remote refused the push. If someone else pushed to \(branch), pull it first.")
            }
            throw DeployError.transferFailed(Self.lastLine(push.output))
        }

        var notes: [String] = []
        if created { notes.append("Created the repository \(owner)/\(repoName).") }
        notes.append("Pushed \(build.fileCount) files (\(build.sizeDescription)) to \(branch).")
        notes.append("GitHub builds and serves this within a minute or two.")

        return DeployReport(
            targetName: Self.descriptor.name,
            success: true,
            liveURL: siteURL,
            notes: notes,
            commandSummary: "git push origin HEAD:\(branch)",
            duration: LocalFolderTarget.format(Date().timeIntervalSince(started))
        )
    }

    static func lastLine(_ text: String) -> String {
        text.split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "no output"
    }
}

/// A small, testable wrapper around `git` that keeps tokens out of the process
/// list.
///
/// The token is handed to git through `GIT_ASKPASS`, pointing at a private
/// temporary script that prints it. Nothing sensitive ever appears in `ps`
/// output, in a shell history, or in an error message.
enum GitCommand {

    struct Result {
        var status: Int32
        var output: String
        var succeeded: Bool { status == 0 }
    }

    /// Passes arguments to git, injecting a token via askpass when given.
    static func run(_ arguments: [String], token: String?,
                    environment: [String: String]? = nil,
                    workingDirectory: URL? = nil) async -> Result {
        let askpassURL: URL?
        if let token, !token.isEmpty {
            askpassURL = makeAskpass(token: token)
        } else {
            askpassURL = nil
        }
        defer { if let askpassURL { try? FileManager.default.removeItem(at: askpassURL) } }

        var env = environment ?? [:]
        if askpassURL != nil {
            env["GIT_ASKPASS"] = askpassURL!.path
            env["GIT_TERMINAL_PROMPT"] = "0"
            // A credential helper can still win over askpass; blank it out so the
            // token we were given is the one that is used.
            env["GIT_CONFIG_COUNT"] = "1"
            env["GIT_CONFIG_KEY_0"] = "credential.helper"
            env["GIT_CONFIG_VALUE_0"] = ""
            env["GIT_ASKPASS_REQUIRE"] = "force"
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }
            if !env.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // `Process.waitUntilExit` needs a running run loop, which an async
            // context on the main actor does not have — the same trap that
            // deadlocked the original process runner. Use the handler instead.
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: Result(status: proc.terminationStatus, output: text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }

    /// Writes a one-shot script that prints the token, readable only by us.
    static func makeAskpass(token: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-askpass-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nprintf '%s' '\(token)'\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }
}
