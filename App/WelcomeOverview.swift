import AppKit
import SwiftUI

struct WelcomeOverviewView: View {
    @Bindable var store: WorkspaceStore
    let openProject: (Destination) -> Void
    @AppStorage("workspaceBackgroundTheme") private var backgroundThemeRawValue = WorkspaceBackgroundTheme.pixelMosaic.rawValue
    @AppStorage("workspacePixelMosaicPalette") private var pixelMosaicPaletteRawValue = WorkspaceThemePalette.aqua.rawValue
    @AppStorage("workspaceTerminalStreamPalette") private var terminalStreamPaletteRawValue = WorkspaceThemePalette.emerald.rawValue
    @AppStorage("workspaceAuroraGridPalette") private var auroraGridPaletteRawValue = WorkspaceThemePalette.aqua.rawValue
    @State private var presentedSheet: WelcomeSheet?
    private var repositoryKey: String { store.repositories.map { String($0.id) }.joined(separator: ",") }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    if geometry.size.width >= 850 {
                        HStack(alignment: .top, spacing: 22) {
                            leftColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                            themeConfigurationPanel.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            leftColumn
                            themeConfigurationPanel
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1400, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.clear)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newProject:
                NewProjectSheet(store: store) { id in
                    presentedSheet = nil
                    openProject(.localProject(id, .overview))
                }
            case .cloneProject:
                CloneProjectPicker(store: store, clone: clone, open: { repository in
                    presentedSheet = nil
                    openProject(.project(repository.id, .overview))
                })
            case .recentProjects:
                RecentProjectsPicker(store: store, openProject: { destination in
                    presentedSheet = nil
                    openProject(destination)
                })
            case .recentPullRequests:
                MoreRecentPullRequestsSheet(store: store, openProject: openProject)
            }
        }
        .task(id: repositoryKey) { await store.loadOverviewPullRequests() }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to dev")
                    .workspaceFont(.largeTitle, weight: .bold)
                Text("Your projects, together in one workspace.")
                    .workspaceFont(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.repositories.isEmpty {
                Button {
                    Task {
                        await store.refresh()
                        await store.loadOverviewPullRequests()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .help("Refresh GitHub projects")
                .accessibilityLabel("Refresh GitHub projects")
            }
        }
        .padding(.top, 8)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            startSection
            recentProjectsSection
            recentPullRequestsSection
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start")
                .workspaceFont(.title2, weight: .bold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                startAction("New project", detail: "Create a folder", icon: "folder.badge.plus", id: "welcome-new-project") {
                    presentedSheet = .newProject
                }
                startAction("Open project", detail: "Choose a local folder", icon: "folder", id: "welcome-open-project") {
                    openLocalProject()
                }
                startAction("Clone project", detail: "From GitHub", icon: "arrow.down.to.line", id: "welcome-clone-project") {
                    presentedSheet = .cloneProject
                }
            }
            if let error = store.localProjectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .workspaceFont(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("welcome-local-project-error")
            }
        }
    }

    private func startAction(_ title: String, detail: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .workspaceFont(size: 21, weight: .medium)
                    .foregroundStyle(Color.accentColor)
                Text(title).workspaceFont(.headline)
                Text(detail).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
        .accessibilityIdentifier(id)
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent projects").workspaceFont(.title2, weight: .bold)
                Spacer()
                Button("More…") { presentedSheet = .recentProjects }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("welcome-recent-projects-more")
            }
            let projects = recentProjectRows
            if projects.isEmpty {
                Text("Projects you open will appear here.")
                    .workspaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 2) {
                    ForEach(projects.prefix(5)) { project in
                        Button { openProject(project.destination) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: project.icon)
                                    .workspaceFont(size: 16)
                                    .foregroundStyle(project.isLocal ? .teal : Color.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(project.title).workspaceFont(.body, weight: .medium).lineLimit(1)
                                    Text(project.subtitle).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.left")
                                    .workspaceFont(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("welcome-recent-project-\(project.id)")
                    }
                }
                .padding(6)
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var recentPullRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Recent pull requests").workspaceFont(.title2, weight: .bold)
                Spacer()
                if store.overviewPullRequests.count > 5 {
                    Button("More…") { presentedSheet = .recentPullRequests }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("welcome-recent-pull-requests-more")
                }
                if store.overviewPullRequestsLoading { ProgressView().controlSize(.small) }
            }
            if let error = store.overviewPullRequestsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .workspaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.overviewPullRequests.isEmpty {
                Text(store.repositories.isEmpty ? "Connect GitHub to see recent pull requests." : "No pull requests to show yet.")
                    .workspaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(store.overviewPullRequests.prefix(5)) { item in
                        Button {
                            if store.isCloned(item.repository) {
                                openProject(.project(item.repository.id, .pullRequests))
                            } else {
                                NSWorkspace.shared.open(item.request.htmlURL)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "arrow.triangle.pull")
                                    .workspaceFont(size: 16)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.request.title).workspaceFont(.body, weight: .medium).lineLimit(2)
                                    Text("\(item.repository.fullName) · #\(item.request.number)")
                                        .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(displayGitHubTimestamp(item.request.updatedAt))
                                        .workspaceFont(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 4)
                                Text(pullRequestState(item.request))
                                    .workspaceFont(.caption2, weight: .semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .workspaceSurfaceBackground(pullRequestStateColor(item.request).opacity(0.15), in: Capsule())
                                    .foregroundStyle(pullRequestStateColor(item.request))
                            }
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .padding(12)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("welcome-recent-pr-\(item.id)")
                    }
                }
            }
        }
    }

    private var themeConfigurationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Theme configuration", systemImage: "paintpalette")
                .workspaceFont(.title2, weight: .bold)
            Text("Choose a subtle animated background for your workspace.")
                .workspaceFont(.callout).foregroundStyle(.secondary)
            ForEach(WorkspaceBackgroundTheme.allCases) { theme in
                ThemePresetButton(
                    theme: theme,
                    selected: backgroundThemeRawValue == theme.rawValue,
                    palette: palette(for: theme),
                    action: { backgroundThemeRawValue = theme.rawValue },
                    choosePalette: { setPalette($0, for: theme) }
                )
            }
            Label("Animation pauses when Reduce Motion is on.", systemImage: "figure.walk.motion")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)))
    }

    private func palette(for theme: WorkspaceBackgroundTheme) -> WorkspaceThemePalette {
        let rawValue: String
        switch theme {
        case .pixelMosaic: rawValue = pixelMosaicPaletteRawValue
        case .terminalStream: rawValue = terminalStreamPaletteRawValue
        case .auroraGrid: rawValue = auroraGridPaletteRawValue
        }
        return WorkspaceThemePalette(rawValue: rawValue) ?? .aqua
    }

    private func setPalette(_ palette: WorkspaceThemePalette, for theme: WorkspaceBackgroundTheme) {
        switch theme {
        case .pixelMosaic: pixelMosaicPaletteRawValue = palette.rawValue
        case .terminalStream: terminalStreamPaletteRawValue = palette.rawValue
        case .auroraGrid: auroraGridPaletteRawValue = palette.rawValue
        }
    }

    private var recentProjectRows: [WelcomeRecentProject] {
        store.recentProjects.compactMap { reference in
            switch reference {
            case let .local(id):
                guard let project = store.localProjects.first(where: { $0.id == id }), let url = project.url else { return nil }
                return WelcomeRecentProject(id: reference.id, title: project.name, subtitle: abbreviatedPath(url.path), icon: "folder.fill", isLocal: true, destination: .localProject(id, .overview))
            case let .github(id):
                guard let repository = store.repository(id: id) else { return nil }
                let path = store.clonedRepositoryPaths[id].map(abbreviatedPath) ?? "GitHub · \(repository.defaultBranch ?? "default branch")"
                return WelcomeRecentProject(id: reference.id, title: repository.name, subtitle: path, icon: "shippingbox.fill", isLocal: false, destination: .project(id, .overview))
            }
        }
    }

    private func openLocalProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Project"
        panel.message = "Choose a local project folder."
        guard panel.runModal() == .OK, let url = panel.url,
              let id = store.addLocalProject(at: url) else { return }
        openProject(.localProject(id, .overview))
    }

    private func clone(_ repository: GitHubRepository) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Here"
        panel.message = "Choose a parent folder for \(repository.name)."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        Task {
            await store.clone(repository, into: parent)
            if store.isCloned(repository) {
                presentedSheet = nil
                openProject(.project(repository.id, .overview))
            }
        }
    }

}

private enum WelcomeSheet: String, Identifiable {
    case newProject, cloneProject, recentProjects, recentPullRequests
    var id: String { rawValue }
}

private struct WelcomeRecentProject: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let isLocal: Bool
    let destination: Destination
}

private struct NewProjectSheet: View {
    @Bindable var store: WorkspaceStore
    let created: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New project").workspaceFont(.title2, weight: .bold)
            Text("Create an empty project folder on this Mac.").foregroundStyle(.secondary)
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("new-project-name")
            HStack {
                Button("Choose parent folder…", action: chooseParent)
                Text(parent.map { abbreviatedPath($0.path) } ?? "No location selected")
                    .workspaceFont(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            if let error = store.localProjectError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .workspaceFont(.callout).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create project", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parent == nil)
                    .accessibilityIdentifier("create-project-confirm")
            }
        }
        .padding(24)
        .frame(width: 480)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Parent"
        panel.message = "The new project folder will be created inside this location."
        if panel.runModal() == .OK { parent = panel.url }
    }

    private func create() {
        guard let parent, let id = store.createLocalProject(named: name, in: parent) else { return }
        created(id)
    }
}

private struct CloneProjectPicker: View {
    @Bindable var store: WorkspaceStore
    let clone: (GitHubRepository) -> Void
    let open: (GitHubRepository) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var repositories: [GitHubRepository] {
        guard !query.isEmpty else { return store.repositories }
        return store.repositories.filter { $0.fullName.localizedCaseInsensitiveContains(query) || ($0.summary?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clone a GitHub project").workspaceFont(.title2, weight: .bold)
                    Text("Choose a repository you can access.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search repositories", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("clone-project-search")
            if let error = store.cloneError {
                Label(error, systemImage: "exclamationmark.triangle").workspaceFont(.callout).foregroundStyle(.orange)
            }
            if store.repositories.isEmpty {
                if store.connectionState == .connected {
                    ContentUnavailableView("No repositories available", systemImage: "shippingbox", description: Text("This GitHub account has not exposed any repositories to dev."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ConnectionView(store: store)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if repositories.isEmpty {
                ContentUnavailableView.search(text: query).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(repositories) { repository in
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox.fill").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(repository.fullName).workspaceFont(.body, weight: .medium)
                                    Text(repository.summary ?? repository.defaultBranch ?? "GitHub repository")
                                        .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                if store.cloningRepositoryIDs.contains(repository.id) {
                                    ProgressView().controlSize(.small)
                                } else if store.isCloned(repository) {
                                    Button("Open") { open(repository) }.buttonStyle(.bordered)
                                } else {
                                    Button("Clone") { clone(repository) }
                                        .buttonStyle(.borderedProminent)
                                        .accessibilityIdentifier("clone-github-project-\(repository.id)")
                                }
                            }
                            .padding(12)
                            .workspaceSurfaceBackground(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 520)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RecentProjectsPicker: View {
    @Bindable var store: WorkspaceStore
    let openProject: (Destination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var projects: [WelcomeRecentProject] {
        store.recentProjects.compactMap { reference in
            switch reference {
            case let .local(id):
                guard let project = store.localProjects.first(where: { $0.id == id }), let url = project.url else { return nil }
                return WelcomeRecentProject(id: reference.id, title: project.name, subtitle: abbreviatedPath(url.path), icon: "folder.fill", isLocal: true, destination: .localProject(id, .overview))
            case let .github(id):
                guard let repository = store.repository(id: id) else { return nil }
                let path = store.clonedRepositoryPaths[id].map(abbreviatedPath) ?? "GitHub · \(repository.defaultBranch ?? "default branch")"
                return WelcomeRecentProject(id: reference.id, title: repository.name, subtitle: path, icon: "shippingbox.fill", isLocal: false, destination: .project(id, .overview))
            }
        }.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent projects").workspaceFont(.title2, weight: .bold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Filter recent projects", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("recent-project-picker-search")
            if projects.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No recent projects" : "No matching projects", systemImage: "clock", description: Text("Open or clone a project to add it here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(projects) { project in
                            Button {
                                openProject(project.destination)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: project.icon)
                                        .foregroundStyle(project.isLocal ? .teal : Color.accentColor)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(project.title).workspaceFont(.body, weight: .medium)
                                        Text(project.subtitle).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left").workspaceFont(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 500)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MoreRecentPullRequestsSheet: View {
    @Bindable var store: WorkspaceStore
    let openProject: (Destination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [OverviewPullRequest] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent pull requests").workspaceFont(.title2, weight: .bold)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .workspaceFont(.callout).foregroundStyle(.secondary)
            }
            if requests.isEmpty && !isLoading {
                ContentUnavailableView("No pull requests found", systemImage: "arrow.triangle.pull")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(requests) { item in
                            Button {
                                dismiss()
                                if store.isCloned(item.repository) {
                                    openProject(.project(item.repository.id, .pullRequests))
                                } else {
                                    NSWorkspace.shared.open(item.request.htmlURL)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.triangle.pull")
                                        .foregroundStyle(Color.accentColor).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.request.title).workspaceFont(.body, weight: .medium).lineLimit(2)
                                        Text("\(item.repository.fullName) · #\(item.request.number) · \(displayGitHubTimestamp(item.request.updatedAt))")
                                            .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(pullRequestState(item.request))
                                        .workspaceFont(.caption2, weight: .semibold)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .foregroundStyle(pullRequestStateColor(item.request))
                                        .workspaceSurfaceBackground(pullRequestStateColor(item.request).opacity(0.15), in: Capsule())
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
        .task {
            let result = await store.loadAllOverviewPullRequests()
            requests = result.requests
            error = result.error
            isLoading = false
        }
    }
}

private func pullRequestState(_ request: GitHubPullRequest) -> String {
    if request.mergedAt != nil { return "Merged" }
    return request.state.capitalized
}

private func pullRequestStateColor(_ request: GitHubPullRequest) -> Color {
    if request.mergedAt != nil { return .purple }
    return request.state == "open" ? .green : .secondary
}

private func abbreviatedPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + String(path.dropFirst(home.count))
}
