// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import Foundation

/// Uploads the built site to a traditional web host over FTP, FTPS or SFTP.
///
/// The three protocols are handled by two different tools on macOS, and that is
/// not a stylistic choice:
/// * `/usr/bin/curl` handles ftp/ftps, including recursive upload.
/// * `/usr/bin/sftp` handles sftp, because Apple's curl is built without
///   libssh2 and simply does not list the protocol.
///
/// Both read the password from the Keychain. For SFTP the transport is SSH, so
/// the password is passed through an askpass script rather than a command-line
/// argument, for the same reason as in the GitHub target: `ps` is world-readable.
struct WebHostTarget: PublishTarget {

    enum Transport: String, CaseIterable, Hashable, Sendable {
        case ftp, ftps, sftp

        var displayName: String {
            switch self {
            case .ftp: return "FTP"
            case .ftps: return "FTPS (encrypted FTP)"
            case .sftp: return "SFTP (recommended)"
            }
        }

        var urlScheme: String {
            switch self {
            case .ftp: return "ftp"
            case .ftps: return "ftps"
            case .sftp: return "sftp"
            }
        }

        var defaultPort: Int {
            switch self {
            case .ftp: return 21
            case .ftps: return 21
            case .sftp: return 22
            }
        }
    }

    static let descriptor = TargetDescriptor(
        id: "web-host",
        name: "FTP or SFTP host",
        tagline: "Upload to the web host you already pay for",
        icon: "server.rack",
        category: .webHost,
        needsCredentials: true,
        fields: [
            .choice("protocol", "Protocol", options: Transport.allCases.map(\.rawValue)),
            .text("host", "Host", placeholder: "ftp.yourhost.com",
                  help: "The server name from your hosting control panel."),
            .text("port", "Port", placeholder: "21", help: "Leave blank for the usual port."),
            .text("username", "Username", placeholder: "your-account",
                  help: "Often the same as your control panel login."),
            .secret("password", "Password", service: "host",
                    help: "Stored in your Mac Keychain."),
            .text("remotePath", "Remote folder", placeholder: "/public_html",
                  help: "Where the site files should go. Most hosts call this public_html or www."),
        ],
        notes: """
        Your password is saved in the Mac Keychain, not in the project folder. \
        If your host gave you an SSH key instead of a password, use an SSH-based \
        target rather than typing a password here.
        """
    )

    // MARK: - Validate

    func validate(_ config: DeployConfig) async throws -> [String] {
        let host = config.value("host").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw DeployError.notConfigured("a host name") }

        let remote = config.value("remotePath").trimmingCharacters(in: .whitespaces)
        guard !remote.isEmpty else { throw DeployError.notConfigured("a remote folder") }

        let username = config.value("username").trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty else { throw DeployError.notConfigured("a username") }

        let hostKey = CredentialVault.Key.host(host)
        guard let stored = try? CredentialVault.get(hostKey), !stored.isEmpty else {
            throw DeployError.missingCredential("the password for \(host)")
        }

        var notes: [String] = ["Password found in your Keychain."]
        if host.hasPrefix("ftp://") || host.hasPrefix("http://") {
            notes.append("The host looks like a full URL — try just the server name, like ftp.example.com.")
        }
        return notes
    }

    // MARK: - Deploy

    func deploy(_ build: BuildOutput, config: DeployConfig,
                report: @escaping @Sendable (String) -> Void) async throws -> DeployReport {
        let started = Date()
        let host = config.value("host").trimmingCharacters(in: .whitespaces)
        let username = config.value("username").trimmingCharacters(in: .whitespaces)
        let remotePath = config.value("remotePath").trimmingCharacters(in: .whitespaces)
        let proto = Transport(rawValue: config.value("protocol")) ?? .ftp
        let portText = config.value("port").trimmingCharacters(in: .whitespaces)
        let port = Int(portText).flatMap { $0 > 0 ? $0 : nil } ?? proto.defaultPort

        guard let secret = try? CredentialVault.get(.host(host)), !secret.isEmpty else {
            throw DeployError.missingCredential("the password for \(host)")
        }
        let password = secret

        report("Uploading \(build.fileCount) files (\(build.sizeDescription)) to \(host) over \(proto.rawValue.uppercased())")

        let result: GitCommand.Result
        switch proto {
        case .ftp, .ftps:
            result = await uploadWithCurl(build: build, host: host, port: port, username: username,
                                         password: password, proto: proto, remotePath: remotePath,
                                         report: report)
        case .sftp:
            result = await uploadWithSFTP(build: build, host: host, port: port, username: username,
                                          password: password, remotePath: remotePath, report: report)
        }

        guard result.succeeded else {
            let lower = result.output.lowercased()
            if lower.contains("530") || lower.contains("login incorrect")
                || lower.contains("permission denied") || lower.contains("authentication failed") {
                throw DeployError.authenticationFailed("Check the username and password for \(host).")
            }
            if lower.contains("could not resolve") || lower.contains("name or service not known") {
                throw DeployError.transferFailed("The host name \(host) could not be resolved.")
            }
            throw DeployError.transferFailed(
                GitHubPagesTarget.lastLine(result.output))
        }

        return DeployReport(
            targetName: "\(proto.displayName) · \(host)",
            success: true,
            liveURL: nil,
            notes: [
                "Uploaded \(build.fileCount) files to \(remotePath).",
                "Your host's control panel is the place to check the site is live."
            ],
            commandSummary: result.output.split(separator: "\n").first.map(String.init)
                ?? "\(proto.rawValue) upload",
            duration: LocalFolderTarget.format(Date().timeIntervalSince(started))
        )
    }

    // MARK: - FTP / FTPS via curl

    private func uploadWithCurl(build: BuildOutput, host: String, port: Int, username: String,
                                password: String, proto: Transport, remotePath: String,
                                report: @escaping @Sendable (String) -> Void) async -> GitCommand.Result {
        // curl can read credentials from a netrc-style file, which keeps the
        // password out of the argument vector — `ps` is readable by every
        // process on the machine, so a password on the command line is a
        // password that leaks.
        let netrc = NetrcFile.write(host: host, username: username, password: password)
        defer { if let netrc { try? FileManager.default.removeItem(at: netrc) } }

        var args: [String] = ["--silent", "--show-error", "--fail"]
        args += ["--url", "\(proto.urlScheme)://\(host):\(port)/"]
        if let netrc {
            args += ["--netrc-file", netrc.path]
        } else {
            // Only fall back to the argument form if the private file could not
            // be written, which should not happen.
            args += ["--user", "\(username):\(password)"]
        }
        if proto == .ftps { args += ["--ssl-reqd"] }
        args += ["--ftp-create-dirs"]
        args += ["--quote", "cd \(remotePath)"]
        args += ["--globoff", "--ftp-method", "nocwd"]
        // `-T -` with the build directory as cwd uploads everything in it.
        args += ["-T", "-"]

        report("  transferring over \(proto.displayName)")
        return await runCurl(args, inputDirectory: build.directory)
    }

    private func runCurl(_ arguments: [String], inputDirectory: URL) async -> GitCommand.Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = arguments
            process.currentDirectoryURL = inputDirectory

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: GitCommand.Result(
                    status: proc.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: GitCommand.Result(status: -1, output: error.localizedDescription))
            }
        }
    }

    // MARK: - SFTP via /usr/bin/sftp

    private func uploadWithSFTP(build: BuildOutput, host: String, port: Int, username: String,
                                password: String, remotePath: String,
                                report: @escaping @Sendable (String) -> Void) async -> GitCommand.Result {
        let askpass = NetrcFile.writeSSHAskpass(password: password)
        defer { if let askpass { try? FileManager.default.removeItem(at: askpass) } }

        // sftp is driven by a command script on stdin. `put -r` uploads the
        // directory contents; mkdir guards against a missing remote folder.
        var script = "mkdir \(remotePath)\n"
        script += "put -r \(build.directory.path) \(remotePath)\n"
        script += "ls -l \(remotePath)\n"
        script += "bye\n"

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-sftp-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        guard (try? script.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil else {
            return GitCommand.Result(status: -1, output: "Could not write the sftp command script.")
        }

        let args = ["-o", "BatchMode=no", "-P", String(port), "-b", scriptURL.path,
                    "\(username)@\(host)"]
        var env: [String: String] = [:]
        if let askpass {
            env["SSH_ASKPASS"] = askpass.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            // Without a controlling terminal, openssh only consults askpass when
            // this is set. A GUI app has no tty, so it is required, not optional.
            env["SSH_ASKPASS_ALWAYS"] = "1"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        }

        report("  transferring over SFTP")
        return await GitCommand.runRaw(
            executable: "/usr/bin/sftp", arguments: args,
            environment: env, workingDirectory: build.directory)
    }
}

/// Short-lived private files that carry a secret to an external tool.
enum NetrcFile {
    /// Writes a `.netrc` file holding one machine's credentials.
    static func write(host: String, username: String, password: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-netrc-\(UUID().uuidString)")
        // netrc requires strict permissions and no comments.
        let contents = "machine \(host)\n  login \(username)\n  password \(password)\n"
        guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Writes a script that prints an SSH password, for `SSH_ASKPASS`.
    static func writeSSHAskpass(password: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfh-askpass-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nprintf '%s\\n' '\(password)'\n"
        guard (try? script.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

extension GitCommand {
    /// Runs any executable, not just git. Same askpass discipline.
    static func runRaw(executable: String, arguments: [String],
                       environment: [String: String], workingDirectory: URL?) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let workingDirectory { process.currentDirectoryURL = workingDirectory }
            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(
                    status: proc.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }
}
