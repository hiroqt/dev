import SwiftUI

struct WorkspaceView: View {
    @State private var store = WorkspaceStore()
    @State private var selection: Destination? = .allProjects
    @State private var isSidebarVisible = true
    @State private var showingRepositorySearch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .accessibilityLabel(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .accessibilityIdentifier("sidebar-toggle")
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .frame(width: isSidebarVisible ? 240 : 52, height: 44)
                HStack {
                    Text(openedDestinationTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(openedDestinationTitle)
                .accessibilityIdentifier("workspace-header-title")
            }
            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: isSidebarVisible ? 240 : 52)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1)
                    }

                VStack(spacing: 0) {
                    destinationView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.snappy(duration: 0.2), value: selection)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isSidebarVisible)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingRepositorySearch) {
            RepositorySearchSheet(store: store) { repository in
                selection = .project(repository.id, .overview)
                showingRepositorySearch = false
            }
        }
        .task {
            await store.restoreSession()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if isSidebarVisible {
            expandedSidebar.transition(.opacity)
        } else {
            compactSidebar.transition(.opacity)
        }
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("dev")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    showRepositorySearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search repositories")
                .accessibilityLabel("Search repositories")
                .accessibilityIdentifier("sidebar-search")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List(selection: $selection) {
                Section {
                    Label("All Projects", systemImage: "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .tag(Destination.allProjects)
                        .accessibilityIdentifier("nav-all-projects")
                    Label("Activity", systemImage: "waveform.path")
                        .font(.system(size: 15, weight: .medium))
                        .tag(Destination.activity)
                        .accessibilityIdentifier("nav-activity")
                } header: {
                    Text("Workspace")
                        .font(.system(size: 13, weight: .semibold))
                }

                Section {
                    ForEach(store.filteredRepositories) { repository in
                        Label(repository.name, systemImage: "shippingbox")
                            .font(.system(size: 15, weight: .medium))
                            .tag(Destination.project(repository.id, .overview))
                    }
                } header: {
                    Text("Projects")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub account")
                            .font(.system(size: 15, weight: .semibold))
                        Text(store.sidebarAccountStatus)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                Button {
                    selection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .accessibilityIdentifier("nav-settings")
            }
            .padding(8)
        }
    }

    private var compactSidebar: some View {
        VStack(spacing: 0) {
            Button(action: showRepositorySearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help("Search repositories")
            .accessibilityLabel("Search repositories")
            .accessibilityIdentifier("compact-sidebar-search")
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 6) {
                    compactButton("All Projects", icon: "square.grid.2x2", selected: selection == .allProjects || selection == nil, id: "compact-nav-all-projects") {
                        selection = .allProjects
                    }
                    compactButton("Activity", icon: "waveform.path", selected: selection == .activity, id: "compact-nav-activity") {
                        selection = .activity
                    }
                    ForEach(store.filteredRepositories) { repository in
                        compactButton(repository.name, icon: "shippingbox", selected: isProjectSelected(repository.id), id: "compact-project-\(repository.id)") {
                            selection = .project(repository.id, .overview)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }

            Spacer(minLength: 8)
            Divider()
            VStack(spacing: 6) {
                compactButton("GitHub account: \(store.sidebarAccountStatus)", icon: "person.crop.circle.fill", selected: false, id: "compact-account") {
                    selection = .settings
                }
                compactButton("Settings", icon: "gearshape", selected: selection == .settings, id: "compact-nav-settings") {
                    selection = .settings
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func compactButton(_ title: String, icon: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 36, height: 36)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.primary.opacity(0.12))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func showRepositorySearch() {
        store.searchText = ""
        showingRepositorySearch = true
    }

    private func isProjectSelected(_ id: Int64) -> Bool {
        guard case let .project(selectedID, _) = selection else { return false }
        return selectedID == id
    }

    private var openedDestinationTitle: String {
        switch selection {
        case .allProjects, nil: "All Projects"
        case .activity: "Activity"
        case .settings: "Settings"
        case let .project(id, _): store.repository(id: id)?.fullName ?? "Project"
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection {
        case .allProjects, nil:
            AllProjectsView(store: store) { repository in
                selection = .project(repository.id, .overview)
            }
        case .activity:
            ContentUnavailableView("No activity yet", systemImage: "waveform.path", description: Text("Activity will appear here after repositories are connected."))
        case .settings:
            SettingsView(store: store)
        case let .project(id, page):
            if let repository = store.repository(id: id) {
                ProjectWorkspaceView(repository: repository, page: page, openAllProjects: {
                    selection = .allProjects
                }) { nextPage in
                    selection = .project(id, nextPage)
                }
            } else {
                ContentUnavailableView("Repository unavailable", systemImage: "shippingbox")
            }
        }
    }
}

private struct RepositorySearchSheet: View {
    @Bindable var store: WorkspaceStore
    let selectRepository: (GitHubRepository) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var queryIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search repositories", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .focused($queryIsFocused)
                    .accessibilityIdentifier("repository-search-field")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            if store.repositories.isEmpty {
                ContentUnavailableView(
                    "No repositories yet",
                    systemImage: "shippingbox",
                    description: Text("Sign in to GitHub to search your accessible repositories.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.filteredRepositories.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredRepositories) { repository in
                            Button {
                                selectRepository(repository)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(repository.fullName).font(.callout.weight(.medium))
                                        Text(repository.summary ?? "No description")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search-repository-\(repository.id)")
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 540, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { queryIsFocused = true }
    }
}

private struct AllProjectsView: View {
    @Bindable var store: WorkspaceStore
    let openRepository: (GitHubRepository) -> Void

    var body: some View {
        GeometryReader { geometry in
            Group {
                if store.repositories.isEmpty {
                    ConnectionView(store: store)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Your repositories").font(.largeTitle.bold())
                                    Text("Repositories accessible to your GitHub account and installed apps.")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await store.refresh() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Refresh repositories")
                                .disabled(store.connectionState == .loading)
                                .help("Refresh repositories from GitHub")
                                .accessibilityIdentifier("all-projects-refresh")
                            }
                            .padding(.top, 28)

                            Label("\(store.filteredRepositories.count) repositories", systemImage: "shippingbox")
                                .foregroundStyle(.secondary)
                            if case let .stale(message) = store.connectionState {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(.orange)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Repositories").font(.title2.bold())
                                VStack(spacing: 0) {
                                    ForEach(store.filteredRepositories) { repository in
                                        RepositoryRow(repository: repository) { openRepository(repository) }
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(height: 1)
                                    }
                                }
                                if store.filteredRepositories.isEmpty {
                                    ContentUnavailableView.search(text: store.searchText)
                                }
                            }
                            .padding(.bottom, 28)
                        }
                        .padding(.horizontal, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ConnectionView: View {
    @Bindable var store: WorkspaceStore
    @State private var showingConfigurationHelp = false

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Image("GitHubMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .accessibilityLabel("GitHub")
            switch store.connectionState {
            case .checking, .loading:
                ProgressView("Checking GitHub connection…")
            case .needsConfiguration:
                Text("Your GitHub workspace starts here").font(.title2.bold())
                Text("Sign in to see repositories you can access. dev only reads GitHub data.")
                    .foregroundStyle(.secondary)
                Button {
                    store.startSignIn()
                    showingConfigurationHelp = true
                } label: {
                    Label {
                        Text("Sign in with GitHub")
                    } icon: {
                        Image("GitHubMark").renderingMode(.template)
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("github-sign-in")
                if showingConfigurationHelp {
                    Text("Add your GitHub App client ID to Config/GitHub.xcconfig and enable Device Flow in the app settings, then rebuild.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("github-configuration-help")
                }
            case .signedOut:
                Text("Connect your GitHub account").font(.title2.bold())
                Text("Sign in to load repositories you can access. dev only reads GitHub data.")
                    .foregroundStyle(.secondary)
                Button { store.startSignIn() } label: {
                    Label {
                        Text("Sign in with GitHub")
                    } icon: {
                        Image("GitHubMark").renderingMode(.template)
                    }
                }
                .buttonStyle(.borderedProminent)
            case .authorizing:
                ProgressView("Requesting a sign-in code…")
                Button("Cancel") { store.cancelSignIn() }
            case .awaitingAuthorization:
                if let authorization = store.authorization {
                    Text("Enter this code on GitHub").font(.headline)
                    Text(authorization.userCode)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("device-user-code")
                    Link("Open GitHub verification", destination: authorization.verificationURL)
                    ProgressView("Waiting for authorization…")
                    Button("Cancel") { store.cancelSignIn() }
                }
            case let .failed(message):
                Label("GitHub connection failed", systemImage: "exclamationmark.triangle")
                    .font(.title2.bold())
                Text(message).foregroundStyle(.secondary)
                Button("Try Again") { store.startSignIn() }
                    .buttonStyle(.borderedProminent)
            case let .stale(message):
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { Task { await store.refresh() } }
            case .connected:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 230)
    }
}

private struct RepositoryRow: View {
    let repository: GitHubRepository
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                Image(systemName: "shippingbox.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(repository.fullName).font(.headline)
                    Text(repository.summary ?? "No description")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(repository.visibilityDescription).font(.callout)
                    if let branch = repository.defaultBranch {
                        Label(branch, systemImage: "arrow.branch")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repository-\(repository.id)")
    }
}

private struct ProjectWorkspaceView: View {
    let repository: GitHubRepository
    let page: ProjectPage
    let openAllProjects: () -> Void
    let navigate: (ProjectPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 7) {
                Button("All Projects", action: openAllProjects)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("breadcrumb-all-projects")
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                ForEach(repository.fullName.split(separator: "/").map(String.init), id: \.self) { component in
                    Text(component).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(page.rawValue).fontWeight(.medium)
                    .accessibilityIdentifier("breadcrumb-current-page")
                Spacer()
            }
            .font(.callout)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(repository.fullName).font(.largeTitle.bold())
                    Text("GitHub · \(repository.visibilityDescription) · \(repository.cloneStateDescription)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = repository.safeGitHubURL {
                    Link("View on GitHub", destination: url)
                }
            }

            HStack(spacing: 8) {
                ForEach(ProjectPage.allCases) { destination in
                    Button {
                        navigate(destination)
                    } label: {
                        Label(destination.rawValue, systemImage: destination.symbol)
                    }
                    .buttonStyle(.bordered)
                    .tint(page == destination ? Color.accentColor : Color.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(page.rawValue, systemImage: page.symbol).font(.title2.bold())
                    Text(page == .overview
                         ? (repository.summary ?? "This repository has no description.")
                         : "Live \(page.rawValue.lowercased()) data is the next backend slice.")
                        .foregroundStyle(.secondary)
                    Label("Remote GitHub metadata", systemImage: "globe")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                .padding(8)
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        Form {
            Section("GitHub") {
                Text("Connection: \(store.connectionState.label)")
                if !store.repositories.isEmpty {
                    Button("Sign Out", role: .destructive) { store.signOut() }
                } else if case .needsConfiguration = store.connectionState {
                    Text("Client ID is read from the app’s GitHubClientID configuration key.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Access") {
                Text("GitHub access is read-only. Sign out removes the stored token and leaves any future local repository clones untouched.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 700, alignment: .leading)
        .padding(24)
    }
}

private extension GitHubConnectionState {
    var label: String {
        switch self {
        case .checking: "Checking"
        case .needsConfiguration: "Needs app configuration"
        case .signedOut: "Signed out"
        case .authorizing, .awaitingAuthorization: "Signing in"
        case .loading: "Loading repositories"
        case .connected: "Connected"
        case .stale: "Showing previous results"
        case .failed: "Connection failed"
        }
    }
}

private extension WorkspaceStore {
    var sidebarAccountStatus: String {
        switch connectionState {
        case .connected: "Connected"
        case .loading: "Updating"
        case .authorizing, .awaitingAuthorization: "Signing in"
        case .stale: "Showing saved data"
        case .failed: "Connection issue"
        case .checking, .needsConfiguration, .signedOut: "Not connected"
        }
    }
}
