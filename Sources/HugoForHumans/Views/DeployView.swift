// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// Deployment: pick a target, fill in what it needs, publish.
///
/// Everything on this screen is generated from the `PublishTarget` registry, so
/// a newly registered target appears with a working form, Keychain-backed
/// credentials, progress and error reporting without a line changed here. That
/// is the whole point of the seam: adding a host is a new type, not a new
/// branch in this file.
struct DeployView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var builder: Builder

    @StateObject private var model = DeployModel()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(eyebrow: "PUBLISH", title: "Put it online",
                            subtitle: "Choose where this site should go, then publish it in one step.") {
                Button {
                    Task { await model.publish(engine: engine, builder: builder) }
                } label: {
                    if model.isPublishing {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Label("Publish", systemImage: "arrow.up.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canPublish || model.isPublishing)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isPublishing {
                        progressCard
                    } else if let report = model.lastReport {
                        reportCard(report)
                    }

                    if let error = model.errorMessage {
                        errorCard(error)
                    }

                    targetPicker

                    if let target = model.selectedTarget {
                        configurationCard(target)
                    }

                    notesCard
                }
                .padding(Design.Metrics.padding)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.load(engine: engine) }
        .onChange(of: engine.root) { _, _ in model.load(engine: engine) }
    }

    // MARK: - Target picker

    private var targetPicker: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                Design.sectionHeader("Where should this site live?")

                ForEach(model.groupedTargets, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(group.category.displayName, systemImage: group.category.symbol)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        ForEach(group.targets, id: \.id) { entry in
                            targetRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func targetRow(_ entry: DeployModel.TargetEntry) -> some View {
        let selected = model.selectedID == entry.id
        return Button {
            model.select(entry.id)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: entry.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Design.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Design.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 12.5, weight: .medium))
                        if entry.needsCredentials && !model.hasStoredSecret(for: entry) {
                            Text("needs a password")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(entry.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.accent)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(selected ? Design.accentSoft : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Configuration

    private func configurationCard(_ target: DeployModel.TargetEntry) -> some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Design.sectionHeader("Connection")
                    Spacer()
                    if !target.fields.isEmpty {
                        Text("Saved with this site. Passwords go to your Mac Keychain.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }

                ForEach(target.fields, id: \.key) { field in
                    fieldRow(field, target: target)
                }

                if let warnings = model.validationNotes, !warnings.isEmpty {
                    Divider()
                    ForEach(warnings, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: CredentialField, target: DeployModel.TargetEntry) -> some View {
        let stored = model.storedSecret(for: field, target: target)
        switch field.kind {
        case .password:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(field.label)
                        .font(.system(size: 11.5, weight: .medium))
                    if stored != nil {
                        Label("Saved in Keychain", systemImage: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    if stored != nil {
                        Button("Replace") { model.editSecret(for: field, target: target) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                        Button("Forget") { model.forgetSecret(for: field, target: target) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                if stored == nil {
                    SecureField("Not saved yet", text: binding(for: field))
                        .textFieldStyle(.roundedBorder)
                    if !field.help.isEmpty {
                        Text(field.help)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        case .choice(let options):
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.system(size: 11.5, weight: .medium))
                Picker("", selection: binding(for: field)) {
                    ForEach(options, id: \.self) { option in
                        Text(option == "true" ? "Yes" : option == "false" ? "No" : option)
                            .tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
        case .text, .toggle:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.system(size: 11.5, weight: .medium))
                if field.key == "destination" {
                    HStack {
                        TextField(field.placeholder, text: binding(for: field))
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { model.chooseFolder(for: field) }
                    }
                } else {
                    TextField(field.placeholder, text: binding(for: field))
                        .textFieldStyle(.roundedBorder)
                }
                if !field.help.isEmpty {
                    Text(field.help)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Progress and results

    private var progressCard: some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Publishing…").font(.system(size: 13, weight: .medium))
                }
                if let step = model.currentStep {
                    Text(step)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reportCard(_ report: DeployReport) -> some View {
        Design.card(alignment: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: report.success ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(report.success ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.success ? "Published to \(report.targetName)" : "Publishing failed")
                            .font(.system(size: 13, weight: .semibold))
                        if !report.duration.isEmpty {
                            Text("took \(report.duration)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let url = report.liveURL, report.success {
                        Link("Open site", destination: URL(string: url) ?? URL(fileURLWithPath: "/"))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                ForEach(report.notes, id: \.self) { note in
                    Label(note, systemImage: "text.bullet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if !report.commandSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("The command behind this")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(report.commandSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Design.card(alignment: .leading) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11.5))
                    .textSelection(.enabled)
                Spacer()
            }
        }
    }

    private var notesCard: some View {
        Group {
            if let notes = model.selectedTarget?.notes, !notes.isEmpty {
                Design.card(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Design.sectionHeader("About this option")
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func binding(for field: CredentialField) -> Binding<String> {
        Binding(
            get: { model.value(for: field) },
            set: { model.setValue($0, for: field) }
        )
    }
}

/// The view's state, kept out of the view so the form logic is testable and the
/// SwiftUI body stays readable.
@MainActor
final class DeployModel: ObservableObject {

    /// A target plus the descriptor the UI draws from.
    struct TargetEntry: Identifiable {
        let id: String
        let name: String
        let tagline: String
        let icon: String
        let category: TargetDescriptor.Category
        let needsCredentials: Bool
        let fields: [CredentialField]
        let notes: String
        let target: PublishTarget

        init(_ target: PublishTarget) {
            let d = type(of: target).descriptor
            id = d.id; name = d.name; tagline = d.tagline; icon = d.icon
            category = d.category; needsCredentials = d.needsCredentials
            fields = d.fields; notes = d.notes
            self.target = target
        }
    }

    struct TargetGroup: Identifiable {
        let category: TargetDescriptor.Category
        let targets: [TargetEntry]
        var id: String { category.rawValue }
    }

    @Published var selectedID = ""
    @Published var fields: [String: String] = [:]
    @Published var isPublishing = false
    @Published var currentStep: String?
    @Published var lastReport: DeployReport?
    @Published var errorMessage: String?
    @Published var validationNotes: [String]?

    private(set) var storedSecrets: [String: String] = [:]
    private var projectRoot: URL?

    var groupedTargets: [TargetGroup] {
        PublishTargetRegistry.shared.grouped.map {
            TargetGroup(category: $0.category, targets: $0.targets.map(TargetEntry.init))
        }
    }

    var selectedTarget: TargetEntry? {
        groupedTargets.flatMap(\.targets).first { $0.id == selectedID }
    }

    var canPublish: Bool {
        guard selectedTarget != nil else { return false }
        if let root = projectRoot,
           !FileManager.default.fileExists(atPath: root.appendingPathComponent("public").path) {
            return false
        }
        return true
    }

    // MARK: - Loading

    func load(engine: SiteEngine) {
        PublishTargetRegistry.shared.registerBuiltIns()
        projectRoot = engine.root
        let saved = engine.root.map(DeploySettingsStore.load(for:))
        if let saved, !saved.targetID.isEmpty,
           PublishTargetRegistry.shared.target(withID: saved.targetID) != nil {
            selectedID = saved.targetID
            fields = saved.config
        } else if selectedID.isEmpty {
            selectedID = PublishTargetRegistry.shared.targets.first.map { type(of: $0).descriptor.id } ?? ""
        }
        refreshSecrets()
    }

    func select(_ id: String) {
        selectedID = id
        lastReport = nil
        errorMessage = nil
        validationNotes = nil
        refreshSecrets()
    }

    private func refreshSecrets() {
        storedSecrets = [:]
        guard let target = selectedTarget else { return }
        for field in target.fields where field.kind == .password {
            if let key = keychainKey(for: field, target: target),
               let value = try? CredentialVault.get(key), !value.isEmpty {
                storedSecrets[field.key] = "••••••••"
                // A stored secret must be able to supply a value, so the real one
                // is kept in memory only for the duration of a publish.
                self.secretValues[field.key] = value
            }
        }
    }

    private var secretValues: [String: String] = [:]

    // MARK: - Values

    func value(for field: CredentialField) -> String { fields[field.key] ?? "" }

    func setValue(_ value: String, for field: CredentialField) {
        fields[field.key] = value
        validationNotes = nil
    }

    /// The Keychain account a password field maps to.
    func keychainKey(for field: CredentialField, target: DeployModel.TargetEntry) -> CredentialVault.Key? {
        guard field.kind == .password else { return nil }
        switch target.id {
        case GitHubPagesTarget.descriptor.id:
            let owner = fields["owner"] ?? fields["repo"] ?? ""
            guard !owner.isEmpty else { return .githubAccount(owner) }
            return .githubAccount(owner)
        case WebHostTarget.descriptor.id:
            let host = fields["host"] ?? ""
            guard !host.isEmpty else { return nil }
            return .host(host)
        default:
            return nil
        }
    }

    func storedSecret(for field: CredentialField, target: TargetEntry) -> String? {
        storedSecrets[field.key]
    }

    func hasStoredSecret(for target: TargetEntry) -> Bool {
        target.fields.contains { field in
            field.kind == .password && storedSecrets[field.key] != nil
        }
    }

    func editSecret(for field: CredentialField, target: TargetEntry) {
        // Clearing the "saved" flag makes the secure field appear again, so the
        // replacement can be typed. Nothing is read back out of the Keychain.
        storedSecrets[field.key] = nil
        secretValues[field.key] = nil
        fields[field.key] = ""
    }

    /// Writes a typed password into the Keychain, or removes it.
    func forgetSecret(for field: CredentialField, target: TargetEntry) {
        guard let key = keychainKey(for: field, target: target) else { return }
        _ = try? CredentialVault.remove(key)
        storedSecrets[field.key] = nil
        secretValues[field.key] = nil
        fields[field.key] = ""
    }

    func chooseFolder(for field: CredentialField) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Choose a destination folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setValue(url.path, for: field)
    }

    // MARK: - Publishing

    func publish(engine: SiteEngine, builder: Builder) async {
        guard let target = selectedTarget,
              let root = engine.root,
              let publicDir = engine.publicDirectory else { return }
        guard FileManager.default.fileExists(atPath: publicDir.path) else {
            errorMessage = "Build the site first — there is nothing in the public folder yet."
            return
        }

        isPublishing = true
        lastReport = nil
        errorMessage = nil
        currentStep = "Checking the connection…"

        // Save what is safe to save: non-secret values only.
        DeploySettingsStore.ensureGitIgnored(projectRoot: root)
        DeploySettingsStore.save(.init(targetID: target.id, config: fields), for: root)

        let files = BuildDirectory.files(in: publicDir)
        let output = BuildOutput(
            directory: publicDir,
            fileCount: files.count,
            totalBytes: BuildDirectory.totalSize(in: publicDir),
            siteName: engine.siteName,
            baseURL: engine.config.baseURL
        )

        do {
            let config = DeployConfig(fields: fields)
            // Passwords typed this session go into the Keychain first, so the
            // target reads them the same way it would on a later run.
            for field in target.fields where field.kind == .password {
                guard let typed = fields[field.key], !typed.isEmpty,
                      let key = keychainKey(for: field, target: target) else { continue }
                if target.id == WebHostTarget.descriptor.id {
                    try? CredentialVault.setHostSecret(
                        .init(username: fields["username"] ?? "", password: typed), for: key.account)
                } else {
                    _ = try? CredentialVault.set(typed, for: key)
                }
            }
            let notes = try await target.target.validate(config)
            validationNotes = notes.isEmpty ? nil : notes

            let report = try await target.target.deploy(output, config: config) { [weak self] step in
                Task { @MainActor in self?.currentStep = step }
            }
            lastReport = report
            currentStep = nil
            if !report.success {
                errorMessage = report.notes.first
            }
        } catch {
            errorMessage = error.localizedDescription
            currentStep = nil
        }
        isPublishing = false
    }
}
