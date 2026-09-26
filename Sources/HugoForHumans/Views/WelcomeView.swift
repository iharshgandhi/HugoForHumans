// Hugo for Humans
// Copyright (c) 2026 Harsh Gandhi (harshgandhi.com) and
//                  Buho Smart Tools (buho.co.in)
// Licensed under the GNU General Public License v3.0 or later.
import SwiftUI

/// The first window a new user sees: a short, confident path from nothing to a
/// working site. Three steps, no jargon, no manual folder creation.
struct WelcomeView: View {
    @EnvironmentObject private var engine: SiteEngine
    @EnvironmentObject private var creator: SiteCreator

    @State private var step: Step = .welcome
    @State private var request = NewSiteRequest()
    @State private var kind: SiteCreator.SiteKind = .blog
    @State private var showOpenPanel = false
    /// Shown when the chosen folder is not a Hugo site.
    @State private var openError: String? = nil
    @State private var showHostingHint = false

    enum Step: Int, CaseIterable {
        case welcome, details, hosting, design, progress
    }

    var body: some View {
        ZStack {
            background

            switch step {
            case .welcome: welcomeStep.transition(.opacity)
            case .details: detailsStep.transition(.opacity)
            case .hosting: hostingStep.transition(.opacity)
            case .design: designStep.transition(.opacity)
            case .progress: progressStep.transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .hfhShowWelcome)) { _ in
            withAnimation(.smooth(duration: 0.3)) { step = .details }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Design.accent.opacity(0.16), .clear],
                           center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 520)
                .blendMode(.normal)
        }
        .ignoresSafeArea()
    }

    // MARK: - Step 1: welcome

    private var welcomeStep: some View {
        VStack(spacing: 30) {
            // One centred block rather than hero-then-buttons: splitting them with
            // a flexible spacer left a conspicuous void in the middle of the window.
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                AppMark(size: 88)
                VStack(spacing: 10) {
                    Text("Hugo for Humans")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("Build a website the way you use an app.")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                Text("Hugo is the fastest website engine on earth. This app makes it\nsomething you can use without ever opening a terminal.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 14) {
                featureChip(icon: "wand.and.stars", title: "Answer a few questions", detail: "We set up every folder for you")
                featureChip(icon: "square.grid.2x2", title: "Add sections and pages", detail: "Buttons, not commands")
                featureChip(icon: "bolt.fill", title: "See it instantly", detail: "Live preview while you type")
            }
            .padding(.top, 12)

            VStack(spacing: 14) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { step = .details }
                } label: {
                    Text("Create a New Site")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if !RecentSites.all().isEmpty {
                    Menu {
                        ForEach(RecentSites.all(), id: \.self) { url in
                            Button(url.lastPathComponent) {
                                engine.openSite(at: url)
                            }
                        }
                        Divider()
                        Button("Choose Another Folder…") { showOpenPanel = true }
                    } label: {
                        Label("Open a Recent Site", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: 260)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.large)
                } else {
                    Button("Open an Existing Site…") { showOpenPanel = true }
                        .controlSize(.large)
                }

                if let openError {
                    Label(openError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.secondary)
                    Text(hugoStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear(perform: prefill)
        .onChange(of: showOpenPanel) { _, newValue in
            if newValue { chooseSiteFolder() }
        }
    }

    /// Opens a folder the user picks and loads it if it really is a Hugo site.
    ///
    /// This used to be an empty handler, so the button set a flag and nothing
    /// happened. Choosing a folder that is not a site is common enough — a
    /// parent directory, `Documents`, the wrong drive — so the check is done
    /// here and explained, rather than opening an empty window.
    private func chooseSiteFolder() {
        defer { showOpenPanel = false }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose the folder that contains hugo.toml"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard SiteEngine.isHugoSite(url) else {
            openError = "\(url.lastPathComponent) is not a Hugo site — look for a folder containing hugo.toml."
            return
        }
        openError = nil
        engine.openSite(at: url)
    }

    private var hugoStatusText: String {
        guard HugoBinary.displayVersion() != nil else {
            return "Hugo engine not found — the bundled copy will be installed on first run"
        }
        return "Hugo \(HugoBinary.displayVersion() ?? "") is ready"
    }

    private func featureChip(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Design.accent)
                .frame(height: 22)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 190)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Step 2: details

    private var detailsStep: some View {
        VStack(spacing: 0) {
            WizardHeader(step: 2, total: 3, title: "What are you making?",
                         subtitle: "This shapes the theme we suggest and the pages we create.",
                         onBack: { withAnimation(.smooth(duration: 0.3)) { step = .welcome } })

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    sectionLabel("Kind of site")
                    HStack(spacing: 12) {
                        ForEach(SiteCreator.SiteKind.allCases) { option in
                            kindCard(option)
                        }
                    }

                    Divider()

                    sectionLabel("Your site")
                    Form {
                        TextField("Site title", text: $request.title)
                            .onChange(of: request.title) { _, newValue in
                                if request.folderName == "my-site" || request.folderName.isEmpty {
                                    request.folderName = SiteEngine.slugify(newValue)
                                }
                            }
                        TextField("Folder name", text: $request.folderName)
                        TextField("Your name", text: $request.author)
                        TextField("Web address", text: $request.baseURL)
                        TextField("One-line description", text: $request.description)
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)

                    Divider()

                    sectionLabel("Where should it live?")
                    HStack {
                        Text(request.destination.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose…") { chooseDestination() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor)))

                    Toggle("Also create pages for About and Contact", isOn: $request.createAboutPage)
                    Toggle("Start a Git repository for version history", isOn: $request.initGit)
                }
                .frame(maxWidth: 640)
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            WizardFooter(primaryTitle: "Continue") {
                guard !request.folderName.isEmpty else { return }
                request.sectionName = kind.defaultSection
                // Preselect a theme that matches the site kind.
                if let suggested = ThemeCatalog.all.first(where: { $0.category == suggestedCategory }) {
                    request.theme = suggested
                }
                withAnimation(.smooth(duration: 0.3)) { step = .hosting }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var suggestedCategory: Theme.Category {
        switch kind {
        case .blog: return .blog
        case .docs: return .docs
        case .portfolio: return .portfolio
        }
    }

    private func kindCard(_ option: SiteCreator.SiteKind) -> some View {
        let isSelected = kind == option
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { kind = option }
            request.sectionName = option.defaultSection
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: option.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : Design.accent)
                Text(option.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(option.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Design.accent : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? .clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

/// The hosting question from the wizard, as a view of its own.
///
/// Split out from the wizard so it can be rendered and reviewed on its own, and
/// so the same question can be asked again later without duplicating the form.

    // MARK: - Step 3: hosting

    /// The wizard's hosting step: the shared question, plus this wizard's chrome.
    private var hostingStep: some View {
        VStack(spacing: 0) {
            WizardHeader(step: 3, total: 4,
                         title: "Where will this site live?",
                         subtitle: "This sets your site's web address. You can change it later.",
                         onBack: { withAnimation(.smooth(duration: 0.3)) { step = .details } })

            HostingQuestion(request: $request, showHint: $showHostingHint)

            WizardFooter(primaryTitle: "Continue", primaryAction: {
                // A greyed-out Continue says nothing; pressing it explains the gap.
                if request.hostingIsComplete {
                    withAnimation(.smooth(duration: 0.3)) { step = .design }
                } else {
                    showHostingHint = true
                }
            })
        }
    }

    // MARK: - Step 3: design

    private var designStep: some View {
        VStack(spacing: 0) {
            WizardHeader(step: 3, total: 3, title: "Choose a look",
                         subtitle: "Every theme here was tested against Hugo \(hugoShortVersion). Change it any time.",
                         onBack: { withAnimation(.smooth(duration: 0.3)) { step = .hosting } })

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                        ForEach(ThemeCatalog.all) { theme in
                            themeCard(theme)
                        }
                    }

                    Toggle("Install this theme for me", isOn: $request.installTheme)

                    if !ThemeCatalog.notes(for: request.theme).isEmpty {
                        ForEach(ThemeCatalog.notes(for: request.theme), id: \.self) { note in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text(note)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.08)))
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }

            WizardFooter(primaryTitle: "Create My Site", isBusy: creator.isRunning) {
                Task { await runCreation() }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hugoShortVersion: String {
        HugoBinary.shortVersion() ?? "extended"
    }

    private func themeCard(_ theme: Theme) -> some View {
        let isSelected = request.theme == theme
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { request.theme = theme }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // A miniature abstract preview: each theme gets a deterministic
                // layout derived from its name, so the grid reads as a gallery.
                ThemeThumbnail(theme: theme, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(theme.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    Text(theme.category.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    if !theme.starsLabel.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 7))
                            Text(theme.starsLabel).font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.accent)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Design.accent : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: progress

    private var progressStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if creator.isRunning {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: creator.error == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(creator.error == nil ? .green : .orange)
                }
                Text(creator.error == nil ? (creator.isRunning ? "Setting everything up" : "Your site is ready") : "Something needs attention")
                    .font(.system(size: 22, weight: .semibold))
                Text(progressSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(creator.steps) { step in
                    HStack(spacing: 12) {
                        stepIndicator(step.state)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title)
                                .font(.system(size: 13, weight: step.state == .pending ? .regular : .medium))
                                .foregroundStyle(step.state == .pending ? .secondary : .primary)
                            Text(step.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                }
            }
            .padding(18)
            .frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.top, 30)

            Spacer()

            if let error = creator.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 12) {
                if !creator.isRunning {
                    Button("Try Again") {
                        Task { await runCreation() }
                    }
                    .controlSize(.large)

                    if let root = creator.finishedRoot {
                        Button("Open My Site") {
                            engine.openSite(at: root)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Text("This takes a few seconds — the theme is downloading.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressSubtitle: String {
        if let error = creator.error { return error }
        if creator.isRunning { return "Hang tight. We are doing the folder work now." }
        return "A complete Hugo site, built and verified."
    }

    private func stepIndicator(_ state: SiteCreator.Step.State) -> some View {
        Group {
            switch state {
            case .pending:
                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5).frame(width: 14, height: 14)
            case .running:
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 15))
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.system(size: 15))
            }
        }
        .frame(height: 18)
    }

    // MARK: - Actions

    private func prefill() {
        request.destinationFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites")
        if request.title.isEmpty {
            request.title = NSFullUserName().isEmpty ? "My Site" : "\(NSFullUserName())'s Site"
            request.folderName = SiteEngine.slugify(request.title)
        }
        if request.author.isEmpty { request.author = NSFullUserName() }
    }

    private func runCreation() async {
        if request.title.isEmpty { request.title = "My Site" }
        if request.folderName.isEmpty { request.folderName = "my-site" }
        if request.description.isEmpty {
            request.description = "\(request.title) — built with Hugo for Humans."
        }
        _ = await creator.begin(with: request, kind: kind)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose where your site folder will be created"
        if panel.runModal() == .OK, let url = panel.url {
            request.destinationFolder = url
        }
    }
}

// MARK: - Wizard chrome

struct WizardHeader: View {
    var step: Int
    var total: Int
    var title: String
    var subtitle: String
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Design.accent : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: 160)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }
}

struct WizardFooter: View {
    var primaryTitle: String
    var isBusy: Bool = false
    /// A plain action rather than a view builder: these closures do work, not layout.
    var primaryAction: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button {
                primaryAction()
            } label: {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The app's icon: a stylised "H" built from the accent, drawn rather than shipped
/// as an asset so it scales cleanly and needs no resource bundle.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(colors: [Design.accent, Design.accent.opacity(0.72)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("H")
                .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Design.accent.opacity(0.3), radius: 12, y: 5)
    }
}

struct HostingQuestion: View {
    @Binding var request: NewSiteRequest
    /// Shown when Continue is pressed with a required field still empty.
    @Binding var showHint: Bool

    var body: some View {
        VStack(spacing: 14) {
            ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 8) {
                ForEach(NewSiteRequest.HostingChoice.allCases) { option in
                    hostingCard(option)
                }
            }

            Divider()

            switch request.hosting {
            case .githubPages:
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Your GitHub account")
                    Form {
                        TextField("GitHub username", text: $request.githubUser)
                            .onChange(of: request.githubUser) { _, _ in
                                if request.githubRepo.isEmpty { request.githubRepo = request.slugOfFolderName }
                            }
                        TextField("Repository name", text: $request.githubRepo)
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)

                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(request.resolvedBaseURL())
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("We will ask for a GitHub token when you first publish, and keep it in your Mac Keychain.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)

            case .webHost:
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Your web host")
                    Form {
                        TextField("Host, e.g. ftp.yourhost.com", text: $request.hostName)
                        TextField("Username", text: $request.hostUser)
                        TextField("Remote folder", text: $request.hostRemotePath)
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)

                    Text("Your password is asked for when you publish, and saved in the Mac Keychain rather than in this folder.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 560)

            case .decideLater:
                Text("No problem. Build the site now, and choose a host whenever you are ready — the Publish screen has every option.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .padding(28)
        .frame(maxWidth: 640)
    }
    .scrollBounceBehavior(.basedOnSize)

    // Continuing is blocked until the required fields are filled, but
    // rather than a dead button, the Continue click explains what is
    // missing — a greyed-out control gives no reason.
        }
    }
}

/// The helpers `HostingQuestion` needs now that it is its own type.
extension HostingQuestion {
    /// One hosting option, as a selectable card.
    func hostingCard(_ option: NewSiteRequest.HostingChoice) -> some View {
        let selected = request.hosting == option
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { request.hosting = option }
            showHint = false
        } label: {
            HStack(spacing: 11) {
                Image(systemName: option.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Design.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Design.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(option.blurb)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.accent)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(selected ? Design.accentSoft : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A small heading above a group of fields.
    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.4)
    }
}

/// Why Continue is refusing to move on, in words rather than a grey button.
extension HostingQuestion {
    var hint: String {
        switch request.hosting {
        case .githubPages:
            return "Enter your GitHub username and a repository name to continue."
        case .webHost:
            return "Enter your host and username to continue."
        case .decideLater:
            return ""
        }
    }
}

/// A generated, deterministic preview of a theme's layout.
struct ThemeThumbnail: View {
    var theme: Theme
    var isSelected: Bool

    var body: some View {
        let seed = abs(theme.name.hashValue)
        let bars = 3 + (seed % 3)
        let sidebar = theme.category == .docs

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: theme.accent).opacity(0.10))

            HStack(spacing: 5) {
                if sidebar {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(hex: theme.accent).opacity(index == 0 ? 0.85 : 0.28))
                                .frame(height: 3)
                        }
                    }
                    .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: theme.accent).opacity(0.8))
                        .frame(width: 44, height: 4)
                    ForEach(0..<bars, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.primary.opacity(0.22))
                                .frame(height: 2.5)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.primary.opacity(0.12))
                                .frame(height: 2.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(9)
        }
        .frame(height: 92)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}