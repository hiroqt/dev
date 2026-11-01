import AppKit
import SwiftUI

struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    @State private var providerIntegrations: ProviderIntegrationsStore
    @State private var monitoring: MonitoringStore
    @State private var selection: Destination? = .allProjects
    @State private var isSidebarVisible = true
    @State private var showingRepositorySearch = false
    @State private var showingProviderUsage = false
    @State private var isToolPanelOpen = false
    @State private var isToolLauncherVisible = true
    @State private var isToolFullScreen = false
    @State private var toolTabs: [WorkspaceToolTab] = []
    @State private var selectedToolTabID: UUID?
    @AppStorage("workspaceToolPanelWidth") private var storedToolPanelWidth = 440.0
    @AppStorage("workspaceBackgroundTheme") private var backgroundThemeRawValue = WorkspaceBackgroundTheme.pixelMosaic.rawValue
    @AppStorage("workspacePixelMosaicPalette") private var pixelMosaicPaletteRawValue = WorkspaceThemePalette.aqua.rawValue
    @AppStorage("workspaceTerminalStreamPalette") private var terminalStreamPaletteRawValue = WorkspaceThemePalette.emerald.rawValue
    @AppStorage("workspaceAuroraGridPalette") private var auroraGridPaletteRawValue = WorkspaceThemePalette.aqua.rawValue
    @AppStorage("workspaceFontSize") private var workspaceFontSize = "medium"
    @AppStorage("workspaceAppearance") private var workspaceAppearance = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    init(store: WorkspaceStore = WorkspaceStore(), providerIntegrations: ProviderIntegrationsStore = ProviderIntegrationsStore(), monitoring: MonitoringStore = MonitoringStore()) {
        _monitoring = State(initialValue: monitoring)
        _store = State(initialValue: store)
        _providerIntegrations = State(initialValue: providerIntegrations)
    }

    private var selectedColorScheme: ColorScheme? {
        switch workspaceAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var workspaceBackgroundColor: Color {
        (selectedColorScheme ?? colorScheme) == .light
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .underPageBackgroundColor)
    }

    private var selectedDynamicTypeSize: DynamicTypeSize {
        switch workspaceFontSize {
        case "small": .small
        case "large": .large
        case "xl": .xxxLarge
        default: .medium
        }
    }

    private var selectedFontScale: CGFloat {
        switch workspaceFontSize {
        case "small": 0.85
        case "large": 1.15
        case "xl": 1.3
        default: 1
        }
    }

    private var backgroundTheme: WorkspaceBackgroundTheme {
        WorkspaceBackgroundTheme(rawValue: backgroundThemeRawValue) ?? .pixelMosaic
    }

    private var backgroundPalette: WorkspaceThemePalette {
        let rawValue: String
        switch backgroundTheme {
        case .pixelMosaic: rawValue = pixelMosaicPaletteRawValue
        case .terminalStream: rawValue = terminalStreamPaletteRawValue
        case .auroraGrid: rawValue = auroraGridPaletteRawValue
        }
        return WorkspaceThemePalette(rawValue: rawValue) ?? .aqua
    }

    var body: some View {
        ZStack {
            workspaceBackgroundColor
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
                            .workspaceFont(size: 14, weight: .semibold)
                            .lineLimit(1)
                            .accessibilityIdentifier("workspace-header-title")
                        Spacer(minLength: 0)
                        Button(action: openToolPanel) {
                            Image(systemName: "plus")
                                .frame(width: 30, height: 30)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(isToolPanelOpen ? "New tool tab" : "Open tools")
                        .accessibilityLabel(isToolPanelOpen ? "New tool tab" : "Open tools")
                        .accessibilityIdentifier("workspace-tools-open")
                        .padding(.trailing, 12)
                    }
                    .padding(.leading, 24)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("workspace-header")
                }
                .background(Color(nsColor: .windowBackgroundColor))
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

                    GeometryReader { geometry in
                        ZStack {
                            WorkspaceThemeBackdrop(theme: backgroundTheme, palette: backgroundPalette, reduceMotion: reduceMotion)
                            HStack(spacing: 0) {
                                let toolPanelUsesFullWidth = isToolPanelOpen && (isToolFullScreen || geometry.size.width < 568)
                                destinationView
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .dynamicTypeSize(selectedDynamicTypeSize)
                                    .environment(\.workspaceFontScale, selectedFontScale)
                                    .animation(.snappy(duration: 0.2), value: selection)
                                    .opacity(toolPanelUsesFullWidth ? 0 : 1)
                                    .accessibilityHidden(toolPanelUsesFullWidth)
                                    .frame(width: toolPanelUsesFullWidth ? 0 : nil)
                                    .clipped()

                                if isToolPanelOpen {
                                    if !toolPanelUsesFullWidth {
                                        ToolPanelResizeHandle(
                                            width: $storedToolPanelWidth,
                                            maximumWidth: geometry.size.width - 328
                                        )
                                    }
                                    WorkspaceToolsPanel(
                                        store: store,
                                        integrations: providerIntegrations,
                                        tabs: $toolTabs,
                                        selectedTabID: $selectedToolTabID,
                                        showingLauncher: $isToolLauncherVisible,
                                        isFullScreen: $isToolFullScreen,
                                        currentProjectFolder: selectedProjectFolder,
                                        currentProjectProviderID: selectedProjectProviderID,
                                        openProject: { selection = $0 },
                                        closePanel: closeToolPanel
                                    )
                                    .dynamicTypeSize(selectedDynamicTypeSize)
                                    .environment(\.workspaceFontScale, selectedFontScale)
                                    .frame(width: toolPanelUsesFullWidth ? geometry.size.width : toolPanelWidth(geometry.size.width))
                                    .frame(maxHeight: .infinity)
                                    .shadow(color: .black.opacity(isToolFullScreen ? 0 : 0.12), radius: 12, x: -3, y: 0)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .animation(.snappy(duration: 0.22), value: isToolPanelOpen)
                        .animation(.snappy(duration: 0.24), value: isToolFullScreen)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isSidebarVisible)
            }
        }
        .background(workspaceBackgroundColor)
        .preferredColorScheme(selectedColorScheme)
        .environment(\.dynamicTypeSize, selectedDynamicTypeSize)
        .environment(\.workspaceFontScale, selectedFontScale)
        .font(.system(size: WorkspaceTypography.scaledSize(13, scale: selectedFontScale)))
        .sheet(isPresented: $showingRepositorySearch) {
            RepositorySearchSheet(store: store) { repository in
                selection = store.isCloned(repository) ? .project(repository.id, .overview) : .allProjects
                showingRepositorySearch = false
            }
            .dismissOnOutsideClick()
        }
        .sheet(isPresented: $showingProviderUsage) {
            ProviderUsageSummary(integrations: providerIntegrations)
                .padding(20)
                .frame(width: 360)
                .dismissOnOutsideClick()
        }
        .onChange(of: selection) { _, destination in
            store.recordRecentProject(for: destination)
        }
        .onChange(of: store.requestedQuickAction) { _, action in
            guard let action else { return }
            switch action {
            case .workspace: selection = .allProjects
            case .skills: selection = .skills
            case .terminal, .codex:
                let tab = WorkspaceToolTab(
                    kind: .terminal,
                    workingDirectory: selectedProjectFolder ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                    initialCommand: action == .codex ? "codex" : nil
                )
                toolTabs.append(tab)
                selectedToolTabID = tab.id
                isToolPanelOpen = true
                isToolLauncherVisible = false
            }
            store.requestedQuickAction = nil
        }
        .onAppear { store.openWorkspaceWindow = { WorkspaceWindowActivation.show { openWindow(id: "workspace") } } }
        .onChange(of: store.authorization?.verificationURL) { _, url in
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    private var selectedProjectFolder: URL? {
        switch selection {
        case let .localProject(id, _): store.localProjects.first(where: { $0.id == id })?.url
        case let .project(id, _): store.clonedRepositoryPaths[id].map { URL(fileURLWithPath: $0, isDirectory: true) }
        default: nil
        }
    }

    private var selectedProjectProviderID: String? {
        switch selection {
        case let .project(id, _): "github-\(id)"
        case let .localProject(id, _): "local-\(id.uuidString)"
        default: nil
        }
    }

    private func toolPanelWidth(_ availableWidth: CGFloat) -> CGFloat {
        min(max(CGFloat(storedToolPanelWidth), 240), max(240, availableWidth - 328))
    }

    private func openToolPanel() {
        isToolPanelOpen = true
        isToolLauncherVisible = true
    }

    private func closeToolPanel() {
        isToolPanelOpen = false
        isToolFullScreen = false
        isToolLauncherVisible = true
        selectedToolTabID = nil
        toolTabs.removeAll()
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
                    .workspaceFont(size: 16, weight: .semibold)
                Spacer()
                Button {
                    showRepositorySearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .workspaceFont(size: 16)
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
                        .workspaceFont(size: 15, weight: .medium)
                        .tag(Destination.allProjects)
                        .accessibilityIdentifier("nav-all-projects")
                    Label("Activity", systemImage: "waveform.path")
                        .workspaceFont(size: 15, weight: .medium)
                        .tag(Destination.activity)
                        .accessibilityIdentifier("nav-activity")
                    Label("Monitoring", systemImage: "gauge.with.dots.needle.50percent")
                        .workspaceFont(size: 15, weight: .medium)
                        .tag(Destination.monitoring)
                        .accessibilityIdentifier("nav-monitoring")
                    Label("Skills", systemImage: "sparkles.rectangle.stack")
                        .workspaceFont(size: 15, weight: .medium)
                        .tag(Destination.skills)
                        .accessibilityIdentifier("nav-skills")
                } header: {
                    Text("Workspace")
                        .workspaceFont(size: 13, weight: .semibold)
                }

                Section {
                    ForEach(store.orderedSidebarProjects(store.clonedRepositories, key: { (repository: GitHubRepository) in "github:\(repository.id)" })) { repository in
                        let key = "github:\(repository.id)"
                        ProjectSidebarRow(
                            name: repository.name,
                            displayName: store.sidebarProjectNames[key] ?? repository.name,
                            key: key,
                            url: store.clonedRepositoryPaths[repository.id].map { URL(fileURLWithPath: $0) },
                            isPinned: store.pinnedSidebarProjects.contains(key),
                            color: store.sidebarProjectColors[key] ?? "default",
                            icon: store.sidebarProjectIcons[key] ?? "shippingbox",
                            badge: store.openPullRequestCounts[repository.id],
                            togglePin: { store.toggleSidebarPin(key) },
                            moveBefore: { store.moveSidebarProject($0, before: key) },
                            updateAppearance: { store.setSidebarProjectAppearance(key, name: $0, color: $1, icon: $2) },
                            remove: {
                                store.removeRepositoryFromSidebar(repository)
                                if isProjectSelected(repository.id) { selection = .allProjects }
                            }
                        )
                        .tag(Destination.project(repository.id, .overview))
                    }
                    if store.clonedRepositories.isEmpty {
                        Text("Clone a repository from All Projects")
                            .workspaceFont(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Projects")
                        .workspaceFont(size: 13, weight: .semibold)
                }

                Section {
                    ForEach(store.orderedSidebarProjects(store.localProjects, key: { (project: LocalProject) in "local:\(project.id.uuidString)" })) { project in
                        let key = "local:\(project.id.uuidString)"
                        ProjectSidebarRow(
                            name: project.name,
                            displayName: store.sidebarProjectNames[key] ?? project.name,
                            key: key,
                            url: project.url,
                            isPinned: store.pinnedSidebarProjects.contains(key),
                            color: store.sidebarProjectColors[key] ?? "default",
                            icon: store.sidebarProjectIcons[key] ?? "folder",
                            togglePin: { store.toggleSidebarPin(key) },
                            moveBefore: { store.moveSidebarProject($0, before: key) },
                            updateAppearance: { store.setSidebarProjectAppearance(key, name: $0, color: $1, icon: $2) },
                            remove: {
                                store.removeLocalProject(project)
                                if isLocalProjectSelected(project.id) { selection = .allProjects }
                            }
                        )
                        .tag(Destination.localProject(project.id, .overview))
                    }
                    if let error = store.localProjectError {
                        Text(error).workspaceFont(.caption).foregroundStyle(.orange)
                    }
                    Button(action: chooseLocalProject) {
                        Label("Add Folder…", systemImage: "plus")
                            .workspaceFont(size: 14, weight: .medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-local-project")
                } header: {
                    Text("Local Projects")
                        .workspaceFont(size: 13, weight: .semibold)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            ProviderUsageSummary(integrations: providerIntegrations)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .workspaceFont(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub account")
                            .workspaceFont(size: 15, weight: .semibold)
                        Text(store.signedInUsername.map { "@\($0)" } ?? store.sidebarAccountStatus)
                            .workspaceFont(size: 13).foregroundStyle(.secondary)
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
                        .workspaceFont(size: 15, weight: .medium)
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
                    .workspaceFont(size: 16)
                    .frame(width: 36, height: 36)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
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
                    compactButton("Monitoring", icon: "gauge.with.dots.needle.50percent", selected: selection == .monitoring, id: "compact-nav-monitoring") {
                        selection = .monitoring
                    }
                    compactButton("Skills", icon: "sparkles.rectangle.stack", selected: selection == .skills, id: "compact-nav-skills") {
                        selection = .skills
                    }
                    compactSidebarSeparator
                    ForEach(store.orderedSidebarProjects(store.clonedRepositories, key: { (repository: GitHubRepository) in "github:\(repository.id)" })) { repository in
                        let key = "github:\(repository.id)"
                        compactButton(store.sidebarProjectNames[key] ?? repository.name, icon: store.sidebarProjectIcons[key] ?? "shippingbox", selected: isProjectSelected(repository.id), id: "compact-project-\(repository.id)", badge: store.openPullRequestCounts[repository.id], tint: ProjectSidebarTint(rawValue: store.sidebarProjectColors[key] ?? "default")?.color ?? .secondary) {
                            selection = .project(repository.id, .overview)
                        }
                    }
                    compactSidebarSeparator
                    ForEach(store.orderedSidebarProjects(store.localProjects, key: { (project: LocalProject) in "local:\(project.id.uuidString)" })) { project in
                        let key = "local:\(project.id.uuidString)"
                        compactButton(store.sidebarProjectNames[key] ?? project.name, icon: store.sidebarProjectIcons[key] ?? "folder", selected: isLocalProjectSelected(project.id), id: "compact-local-project-\(project.id)", tint: ProjectSidebarTint(rawValue: store.sidebarProjectColors[key] ?? "default")?.color ?? .secondary) {
                            selection = .localProject(project.id, .overview)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            }

            Spacer(minLength: 8)
            Divider()
            VStack(spacing: 6) {
                compactButton("Provider usage", icon: "chart.bar.xaxis", selected: showingProviderUsage, id: "compact-provider-usage") {
                    showingProviderUsage = true
                }
                compactButton("GitHub account: \(store.signedInUsername.map { "@\($0)" } ?? store.sidebarAccountStatus)", icon: "person.crop.circle.fill", selected: false, id: "compact-account") {
                    selection = .settings
                }
                compactButton("Settings", icon: "gearshape", selected: selection == .settings, id: "compact-nav-settings") {
                    selection = .settings
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var compactSidebarSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 24, height: 1)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private func compactButton(_ title: String, icon: String, selected: Bool, id: String, badge: Int? = nil, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .workspaceFont(size: 16, weight: .medium)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.12))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                if let badge, badge > 0 {
                    pullRequestCountBadge(badge).offset(x: 5, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(title)
        .accessibilityLabel(badge.map { "\(title), \($0) open pull requests" } ?? title)
        .accessibilityIdentifier(id)
    }

    private func pullRequestCountBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : count.formatted())
            .workspaceFont(size: 10, weight: .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
    }

    private func showRepositorySearch() {
        store.searchText = ""
        showingRepositorySearch = true
    }

    private func chooseLocalProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.message = "Choose a local project folder. Its files stay on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addLocalProject(at: url)
    }

    private func isProjectSelected(_ id: Int64) -> Bool {
        guard case let .project(selectedID, _) = selection else { return false }
        return selectedID == id
    }

    private func isLocalProjectSelected(_ id: UUID) -> Bool {
        guard case let .localProject(selectedID, _) = selection else { return false }
        return selectedID == id
    }

    private var openedDestinationTitle: String {
        switch selection {
        case .allProjects, nil: "All Projects"
        case .activity: "Activity"
        case .monitoring: "Monitoring"
        case .skills: "Skills"
        case .settings: "Settings"
        case let .project(id, _): store.repository(id: id)?.fullName ?? "Project"
        case let .localProject(id, page): "\(store.localProjects.first(where: { $0.id == id })?.name ?? "Local Project") · \(page.rawValue)"
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection {
        case .allProjects, nil:
            AllProjectsView(store: store) { destination in
                selection = destination
            }
        case .monitoring:
            MonitoringView(store: monitoring, integrations: providerIntegrations)
        case .activity:
            ActivityView(store: store)
        case .skills:
            SkillsLibraryView(store: store)
        case .settings:
            SettingsView(store: store, providerIntegrations: providerIntegrations)
        case let .project(id, page):
            if let repository = store.repository(id: id), store.isCloned(repository) {
                ProjectWorkspaceView(store: store, repository: repository, page: page, openAllProjects: {
                    selection = .allProjects
                }) { nextPage in
                    selection = .project(id, nextPage)
                }
            } else {
                ContentUnavailableView("Repository unavailable", systemImage: "shippingbox")
            }
        case let .localProject(id, page):
            if let project = store.localProjects.first(where: { $0.id == id }) {
                LocalProjectWorkspaceView(project: project, page: page) { nextPage in
                    selection = .localProject(id, nextPage)
                }
            } else {
                ContentUnavailableView("Folder unavailable", systemImage: "folder", description: Text("Add this folder again to restore access."))
            }
        }
    }
}

private struct ToolPanelResizeHandle: View {
    @Binding var width: Double
    let maximumWidth: CGFloat
    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 3, height: 36)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let start = dragStartWidth ?? width
                        width = min(max(start - value.translation.width, 240), max(240, Double(maximumWidth)))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize tools panel")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(width + 40, Double(maximumWidth))
                case .decrement: width = max(width - 40, 240)
                @unknown default: break
                }
            }
    }
}

private struct LocalProjectWorkspaceView: View {
    let project: LocalProject
    let page: LocalProjectPage
    let navigate: (LocalProjectPage) -> Void
    @State private var folderComponents: [String] = []
    @State private var selectedFile: LocalProjectFilePreview?
    @State private var filePreviewError: String?

    private var rootURL: URL? { project.url }
    private var currentURL: URL? { folderComponents.reduce(rootURL) { $0?.appending(path: $1, directoryHint: .isDirectory) } }
    private var entries: [(url: URL, isDirectory: Bool, isSymbolicLink: Bool)]? {
        guard let rootURL, let url = currentURL else { return nil }
        let startedAccess = rootURL.startAccessingSecurityScopedResource()
        defer { if startedAccess { rootURL.stopAccessingSecurityScopedResource() } }
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return nil }
        return items
            .compactMap { item in
                guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return nil }
                return (item, values.isDirectory ?? false, values.isSymbolicLink ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .workspaceFont(size: 22)
                        .foregroundStyle(.teal)
                        .frame(width: 48, height: 48)
                        .workspaceSurfaceBackground(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOCAL FOLDER").workspaceFont(.caption, weight: .bold).tracking(1.1).foregroundStyle(.teal)
                        Text(project.name).workspaceFont(.largeTitle, weight: .bold)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach(LocalProjectPage.allCases) { destination in
                        LocalProjectNavigationButton(page: destination, selected: page == destination) {
                            navigate(destination)
                        }
                    }
                }

                if page == .overview {
                    VStack {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("On this Mac", systemImage: "desktopcomputer").workspaceFont(.title2, weight: .bold)
                            if let rootURL {
                                Text(rootURL.path).workspaceFont(.callout, design: .monospaced).textSelection(.enabled).foregroundStyle(.secondary)
                                Label("\((entries?.count ?? 0).formatted()) items in this folder", systemImage: "folder")
                                    .foregroundStyle(.secondary)
                            } else {
                                ContentUnavailableView("Folder access expired", systemImage: "folder.badge.questionmark", description: Text("Remove this entry and add the folder again."))
                            }
                            Text("Open text files read-only. Markdown files include Preview and Markdown views. The Terminal tool starts in this folder.")
                                .workspaceFont(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                        .padding(8)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                } else {
                    HStack(spacing: 7) {
                        Button(project.name) { folderComponents = [] }.buttonStyle(.plain)
                        ForEach(Array(folderComponents.enumerated()), id: \.offset) { index, component in
                            Image(systemName: "chevron.right").workspaceFont(.caption2).foregroundStyle(.tertiary)
                            Button(component) { folderComponents = Array(folderComponents.prefix(index + 1)) }.buttonStyle(.plain)
                        }
                    }
                    .workspaceFont(.callout)
                    VStack {
                        if currentURL == nil || entries == nil || entries?.isEmpty == true {
                            ContentUnavailableView(currentURL == nil || entries == nil ? "Folder unavailable" : "Folder is empty", systemImage: "folder", description: Text("Hidden files are not shown."))
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(entries ?? [], id: \.url) { entry in
                                    if entry.isDirectory && !entry.isSymbolicLink {
                                        Button {
                                            folderComponents.append(entry.url.lastPathComponent)
                                        } label: {
                                            localFileRow(entry)
                                        }
                                        .buttonStyle(.plain)
                                    } else if !entry.isDirectory && !entry.isSymbolicLink {
                                        Button {
                                            openFilePreview(entry.url)
                                        } label: {
                                            localFileRow(entry)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        localFileRow(entry)
                                    }
                                    if entry.url != entries?.last?.url { Divider() }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(item: $selectedFile) { preview in
            LocalProjectFilePreviewSheet(preview: preview)
                .dismissOnOutsideClick()
        }
        .alert("File preview unavailable", isPresented: Binding(
            get: { filePreviewError != nil },
            set: { if !$0 { filePreviewError = nil } }
        )) {
            Button("OK", role: .cancel) { filePreviewError = nil }
        } message: {
            Text(filePreviewError ?? "")
        }
    }

    private func localFileRow(_ entry: (url: URL, isDirectory: Bool, isSymbolicLink: Bool)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder.fill" : (entry.isSymbolicLink ? "link" : "doc.text"))
                .foregroundStyle(entry.isDirectory ? .teal : .secondary)
                .frame(width: 20)
            Text(entry.url.lastPathComponent).lineLimit(1)
            Spacer()
            if !entry.isSymbolicLink {
                Image(systemName: "chevron.right").workspaceFont(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func openFilePreview(_ url: URL) {
        guard let rootURL else { return }
        do {
            let file = try LocalProjectTextFile.read(url, inside: rootURL)
            selectedFile = LocalProjectFilePreview(name: url.lastPathComponent, file: file)
        } catch {
            filePreviewError = error.localizedDescription
        }
    }
}

private struct LocalProjectFilePreview: Identifiable {
    let id = UUID()
    let name: String
    let file: LocalProjectTextFile
}

private struct LocalProjectFilePreviewSheet: View {
    let preview: LocalProjectFilePreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if preview.file.isMarkdown {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Read-only Markdown preview", systemImage: "doc.richtext")
                                .workspaceFont(.caption, weight: .medium)
                                .foregroundStyle(.secondary)
                            MarkdownMessageView(markdown: preview.file.contents, id: "local-file-\(preview.id)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(preview.file.language, systemImage: "chevron.left.forwardslash.chevron.right")
                                .workspaceFont(.caption, weight: .medium)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Read only").workspaceFont(.caption).foregroundStyle(.tertiary)
                        }
                        ScrollView([.horizontal, .vertical]) {
                            Text(preview.file.contents)
                                .workspaceFont(.body, design: .monospaced)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(20)
                }
            }
            .frame(minWidth: 680, minHeight: 480)
            .navigationTitle(preview.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LocalProjectNavigationButton: View {
    let page: LocalProjectPage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: page.symbol)
                Text(page.rawValue)
            }
            .frame(minHeight: 36)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .teal : .secondary)
    }
}

private struct ProjectSidebarRow: View {
    let name: String
    let displayName: String
    let key: String
    let url: URL?
    let isPinned: Bool
    let color: String
    let icon: String
    var badge: Int?
    let togglePin: () -> Void
    let moveBefore: (String) -> Void
    let updateAppearance: (String, String, String) -> Void
    let remove: () -> Void
    @State private var isHovered = false
    @State private var showingEdit = false

    var body: some View {
        HStack(spacing: 8) {
            Label(displayName, systemImage: icon)
                .workspaceFont(size: 15, weight: .medium)
                .lineLimit(1)
                .foregroundStyle(ProjectSidebarTint(rawValue: color)?.color ?? .primary)
            Spacer(minLength: 4)
            if let badge, badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .workspaceFont(size: 10, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("sidebar-pr-count-\(key.dropFirst("github:".count))")
            }
            if isHovered || isPinned {
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                        .workspaceFont(size: 12, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit sidebar name, color, and icon")
                .accessibilityLabel("Edit \(displayName)")

                Button(action: togglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .workspaceFont(size: 12, weight: .medium)
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin project" : "Pin project")
                .accessibilityLabel(isPinned ? "Unpin \(name)" : "Pin \(name)")

                Menu {
                    ProjectSidebarActions(name: name, url: url, remove: remove)
                } label: {
                    Image(systemName: "ellipsis")
                        .workspaceFont(size: 12, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("Project settings")
                .accessibilityLabel("\(name) settings")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .draggable(key)
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first, source.split(separator: ":").first == key.split(separator: ":").first else { return false }
            moveBefore(source)
            return true
        }
        .contextMenu {
            Button("Edit Name & Color…", systemImage: "pencil") { showingEdit = true }
            ProjectSidebarActions(name: name, url: url, remove: remove)
        }
        .sheet(isPresented: $showingEdit) {
            ProjectSidebarEditSheet(name: displayName, color: color, icon: icon) { editedName, editedColor, editedIcon in
                updateAppearance(editedName, editedColor, editedIcon)
                showingEdit = false
            }
            .frame(width: 420, height: 480)
            .dismissOnOutsideClick()
        }
    }
}

private enum ProjectSidebarTint: String, CaseIterable, Identifiable {
    case `default`, red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .default: .primary
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}

private struct ProjectSidebarEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var icon: String
    let save: (String, String, String) -> Void

    init(name: String, color: String, icon: String, save: @escaping (String, String, String) -> Void) {
        _name = State(initialValue: name)
        _color = State(initialValue: ProjectSidebarTint(rawValue: color)?.rawValue ?? "default")
        _icon = State(initialValue: ProjectSidebarIcon.symbols.contains(icon) ? icon : "folder")
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Sidebar Project").workspaceFont(.title2, weight: .bold)
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Sidebar color").workspaceFont(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(ProjectSidebarTint.allCases) { tint in
                    Button { color = tint.rawValue } label: {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 24, height: 24)
                            .padding(4)
                            .overlay(Circle().strokeBorder(color == tint.rawValue ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(tint.title)
                    .accessibilityLabel(tint.title)
                }
            }
            Text("Sidebar icon").workspaceFont(.headline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                    ForEach(ProjectSidebarIcon.symbols, id: \.self) { symbol in
                        Button { icon = symbol } label: {
                            Image(systemName: symbol)
                                .workspaceFont(size: 16)
                                .foregroundStyle(ProjectSidebarTint(rawValue: color)?.color ?? .primary)
                                .frame(width: 32, height: 30)
                                .background(icon == symbol ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                    }
                }
            }
            .frame(height: 150)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(name, color, icon) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }
}

private enum ProjectSidebarIcon {
    static let symbols = [
        "shippingbox", "shippingbox.fill", "folder", "folder.fill", "folder.badge.gearshape", "doc.text", "doc.richtext", "tray.full",
        "curlybraces", "chevron.left.forwardslash.chevron.right", "terminal", "apple.terminal", "hammer", "wrench.and.screwdriver", "gearshape", "gearshape.2",
        "swift", "ladybug", "testtube.2", "checkmark.seal", "cube", "shippingbox.circle", "square.stack.3d.up", "point.3.connected.trianglepath.dotted",
        "server.rack", "externaldrive", "internaldrive", "desktopcomputer", "laptopcomputer", "iphone", "ipad", "display",
        "globe", "network", "cloud", "lock", "key.fill", "shield", "bolt", "flame",
        "leaf", "heart", "star", "bookmark", "book", "checklist", "list.bullet.rectangle", "chart.bar",
        "chart.xyaxis.line", "waveform.path", "paintpalette", "gamecontroller", "music.note", "camera", "photo", "play.rectangle",
        "person.2", "building.2", "creditcard", "cart", "bag", "map", "location", "airplane",
        "car", "sparkles", "puzzlepiece.extension", "atom", "brain", "graduationcap", "building.columns", "calendar"
    ]
}

private struct ProjectSidebarActions: View {
    let name: String
    let url: URL?
    let remove: () -> Void

    private var codingApplications: [(name: String, url: URL)] {
        guard let url else { return [] }
        let recognized = ["code", "xcode", "cursor", "zed", "windsurf", "fleet", "intellij", "android studio", "kiro", "antigravity"]
        let applications = NSWorkspace.shared.urlsForApplications(toOpen: url)
            + [NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode")].compactMap { $0 }
        return Set(applications).compactMap { appURL in
            guard let bundle = Bundle(url: appURL), let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                  recognized.contains(where: { name.localizedCaseInsensitiveContains($0) }) else { return nil }
            return (name, appURL)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if let url {
            Menu("Open With") {
                if codingApplications.isEmpty {
                    Text("No coding IDE available").disabled(true)
                } else {
                    ForEach(codingApplications, id: \.url) { application in
                        Button(application.name) { open(url, with: application.url) }
                    }
                }
            }
            Button("Show in Finder") { reveal(url) }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            } label: {
                Label {
                    Text(url.path).lineLimit(2)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
            Divider()
        } else {
            Text("Project path unavailable").disabled(true)
        }
        Button("Remove from Sidebar", role: .destructive, action: remove)
    }

    private func open(_ url: URL, with application: URL) {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    private func reveal(_ url: URL) {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct ActivityView: View {
    @Bindable var store: WorkspaceStore
    @State private var selectedYear = Self.currentYear

    private static var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: Date())
    }

    private var years: [Int] { (0..<5).map { Self.currentYear - $0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.contributionActivity.map { "\($0.calendar.totalContributions.formatted()) contributions in \(selectedYear == years[0] ? "the last year" : String(selectedYear))" } ?? "Contribution activity")
                            .workspaceFont(.title2, weight: .semibold)
                        if store.contributionActivityLoading {
                            Label("Loading GitHub activity…", systemImage: "arrow.clockwise")
                                .workspaceFont(.callout).foregroundStyle(.secondary)
                        } else if let error = store.contributionActivityError {
                            Text(error).workspaceFont(.callout).foregroundStyle(.secondary)
                        } else if let activity = store.contributionActivity, activity.restrictedContributionsCount > 0 {
                            Text("Includes \(activity.restrictedContributionsCount.formatted()) private contributions")
                                .workspaceFont(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Menu {
                        ForEach(years, id: \.self) { year in
                            Button(String(year)) { selectedYear = year }
                                .accessibilityIdentifier("activity-year-\(year)")
                        }
                    } label: {
                        Label(String(selectedYear), systemImage: "chevron.down")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .workspaceSurfaceBackground(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityIdentifier("activity-year-selector")
                    Button {
                        Task { await store.loadContributionActivity(year: selectedYear) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh contribution activity")
                    .accessibilityLabel("Refresh contribution activity")
                    .disabled(store.contributionActivityLoading)
                }

                VStack(spacing: 0) {
                    Group {
                        if store.contributionActivityLoading && store.contributionActivity == nil {
                            ProgressView("Loading GitHub contribution activity…")
                                .frame(maxWidth: .infinity, minHeight: 240)
                        } else if let error = store.contributionActivityError {
                            ContentUnavailableView {
                                Label("Contribution activity unavailable", systemImage: "exclamationmark.triangle")
                            } description: {
                                Text(error)
                            } actions: {
                                Button("Retry") { Task { await store.loadContributionActivity(year: selectedYear) } }
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else if let activity = store.contributionActivity {
                            contributionCalendar(activity.calendar)
                                .padding(24)
                            Divider()
                            activityOverview(activity)
                                .padding(26)
                        } else {
                            ProgressView("Loading GitHub contribution activity…")
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }
                    }
                }
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .accessibilityIdentifier("activity-view")
        .task(id: selectedYear) { await store.loadContributionActivity(year: selectedYear) }
    }

    private func contributionCalendar(_ calendar: GitHubContributionCalendar) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                ForEach(calendar.months) { month in
                    Text(String(month.name.prefix(3)))
                        .workspaceFont(.callout, weight: .medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GeometryReader { geometry in
                let cell = max(8, min(17, (geometry.size.width - 48 - 52 * 4) / CGFloat(max(calendar.weeks.count, 1))))
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        ForEach(Array(["", "Mon", "", "Wed", "", "Fri", ""].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .workspaceFont(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: cell, alignment: .leading)
                        }
                    }
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(calendar.weeks) { week in
                            VStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { row in
                                    if let day = week.contributionDays.first(where: { $0.weekday == row }) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(contributionColor(day.contributionLevel))
                                            .frame(width: cell, height: cell)
                                            .help("\(day.contributionCount) contributions on \(day.date)")
                                            .accessibilityLabel("\(day.contributionCount) contributions on \(day.date)")
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * 17 + 6 * 4)
            HStack {
                Text("\(calendar.totalContributions.formatted()) contributions")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Less")
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(contributionColor(for: level))
                        .frame(width: 17, height: 17)
                }
                Text("More")
                    .foregroundStyle(.secondary)
            }
            .workspaceFont(.callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contribution calendar for \(selectedYear), \(calendar.totalContributions) contributions.")
    }

    private func activityOverview(_ activity: GitHubContributionSummary) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Activity overview")
                    .workspaceFont(.title3, weight: .semibold)
                if activity.repositoryCount == 0 {
                    Label("No commit repositories reported by GitHub", systemImage: "shippingbox")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Committed to \(activity.repositoryCount) repositories")
                        .workspaceFont(.body)
                    ForEach(Array(activity.repositories.prefix(3))) { repository in
                        if let url = safeRepositoryURL(repository) {
                            Link(repository.nameWithOwner, destination: url)
                        }
                    }
                    if activity.repositoryCount > 3 {
                        Text("and \((activity.repositoryCount - 3).formatted()) other repositories")
                    }
                }
                if activity.restrictedContributionsCount > 0 {
                    Text("Private contribution details are hidden by GitHub.")
                        .workspaceFont(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
            .padding(.trailing, 30)

            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 1)
                .padding(.vertical, 4)

            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    var axes = Path()
                    axes.move(to: CGPoint(x: center.x, y: 0))
                    axes.addLine(to: CGPoint(x: center.x, y: size.height))
                    axes.move(to: CGPoint(x: 0, y: center.y))
                    axes.addLine(to: CGPoint(x: size.width, y: center.y))
                    context.stroke(axes, with: .color(.green.opacity(0.8)), lineWidth: 2)

                    var commits = Path()
                    commits.move(to: CGPoint(x: 0, y: center.y - 7))
                    commits.addLine(to: CGPoint(x: center.x, y: center.y - 4))
                    commits.addLine(to: CGPoint(x: center.x, y: center.y + 4))
                    commits.addLine(to: CGPoint(x: 0, y: center.y + 7))
                    commits.closeSubpath()
                    context.fill(commits, with: .color(.green.opacity(0.35)))
                    context.stroke(commits, with: .color(.green), lineWidth: 2)

                    for point in [CGPoint(x: 0, y: center.y), center] {
                        let marker = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
                        context.fill(marker, with: .color(Color(nsColor: .windowBackgroundColor)))
                        context.stroke(marker, with: .color(.green), lineWidth: 3)
                    }
                }
                VStack(spacing: 0) {
                    metricLabel("Code review", activity.reviews, percent: percentage(activity.reviews, in: activity))
                    Spacer()
                    HStack {
                        metricLabel("Commits", activity.commits, percent: percentage(activity.commits, in: activity))
                        Spacer()
                        metricLabel("Issues", activity.issues, percent: percentage(activity.issues, in: activity))
                    }
                    Spacer()
                    metricLabel("Pull requests", activity.pullRequests, percent: percentage(activity.pullRequests, in: activity))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .padding(.leading, 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Activity chart: \(percentage(activity.commits, in: activity)) percent commits, \(percentage(activity.reviews, in: activity)) percent code review, \(percentage(activity.issues, in: activity)) percent issues, \(percentage(activity.pullRequests, in: activity)) percent pull requests.")
        }
    }

    private func metricLabel(_ title: String, _ count: Int, percent: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(percent)% · \(count.formatted())")
                .fontWeight(.medium)
            Text(title)
        }
        .workspaceFont(.callout)
        .foregroundStyle(.secondary)
    }

    private func percentage(_ value: Int, in activity: GitHubContributionSummary) -> Int {
        let total = activity.commits + activity.issues + activity.pullRequests + activity.reviews
        return total == 0 ? 0 : Int((Double(value) / Double(total) * 100).rounded())
    }

    private func contributionColor(_ level: String) -> Color {
        switch level {
        case "FIRST_QUARTILE": .green.opacity(0.35)
        case "SECOND_QUARTILE": .green.opacity(0.55)
        case "THIRD_QUARTILE": .green.opacity(0.75)
        case "FOURTH_QUARTILE": .green
        default: Color(nsColor: .quaternaryLabelColor).opacity(0.24)
        }
    }

    private func contributionColor(for level: Int) -> Color {
        [contributionColor("NONE"), contributionColor("FIRST_QUARTILE"), contributionColor("SECOND_QUARTILE"), contributionColor("THIRD_QUARTILE"), contributionColor("FOURTH_QUARTILE")][level]
    }

    private func safeRepositoryURL(_ repository: GitHubContributionRepository) -> URL? {
        guard let components = URLComponents(url: repository.url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.path == "/\(repository.nameWithOwner)", components.query == nil,
              components.fragment == nil else { return nil }
        return repository.url
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
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

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
                                        Text(repository.fullName).workspaceFont(.callout, weight: .medium)
                                        Text(repository.summary ?? "No description")
                                            .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor))
        .onAppear { queryIsFocused = true }
    }
}

private struct AllProjectsView: View {
    @Bindable var store: WorkspaceStore
    let openProject: (Destination) -> Void

    var body: some View {
        WelcomeOverviewView(store: store, openProject: openProject)
    }
}

struct ConnectionView: View {
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
                Text("Your GitHub workspace starts here").workspaceFont(.title2, weight: .bold)
                Text("Sign in to see repositories you can access. dev can create, comment on, review, and merge pull requests.")
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
                        .workspaceFont(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("github-configuration-help")
                }
            case .signedOut:
                Text("Connect your GitHub account").workspaceFont(.title2, weight: .bold)
                Text("Sign in to load repositories you can access. dev can create, comment on, review, and merge pull requests.")
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
                    Text("Enter this code on GitHub").workspaceFont(.headline)
                    Text(authorization.userCode)
                        .workspaceFont(size: 30, weight: .semibold, design: .monospaced)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("device-user-code")
                    Link("Open GitHub verification", destination: authorization.verificationURL)
                    ProgressView("Waiting for authorization…")
                    Button("Cancel") { store.cancelSignIn() }
                }
            case let .failed(message):
                Label("GitHub connection failed", systemImage: "exclamationmark.triangle")
                    .workspaceFont(.title2, weight: .bold)
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
    let isCloned: Bool
    let isCloning: Bool
    let open: () -> Void
    let clone: () -> Void
    let addFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill")
                            .workspaceFont(.title3)
                            .foregroundStyle(.tint)
                        Text(repository.fullName).workspaceFont(.headline).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    Text(repository.summary ?? "No description")
                        .workspaceFont(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(repository.visibilityDescription).workspaceFont(.callout)
                        if let branch = repository.defaultBranch {
                            Label(branch, systemImage: "arrow.branch")
                                .workspaceFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isCloned)
            if isCloned {
                Label("Cloned", systemImage: "checkmark.circle.fill")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button(action: clone) {
                        if isCloning { ProgressView().controlSize(.small) }
                        else { Label("Clone", systemImage: "arrow.down.to.line") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCloning)
                    .accessibilityIdentifier("clone-repository-\(repository.id)")
                    Button(action: addFolder) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCloning)
                    .accessibilityIdentifier("add-existing-repository-\(repository.id)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
        .accessibilityIdentifier("repository-\(repository.id)")
    }
}

private struct ProjectWorkspaceView: View {
    @Bindable var store: WorkspaceStore
    let repository: GitHubRepository
    let page: ProjectPage
    let openAllProjects: () -> Void
    let navigate: (ProjectPage) -> Void
    @State private var showingCreatePullRequest = false
    @State private var createPullRequestHead: String?
    @State private var openedPullRequestNumber: Int?

    var body: some View {
        ScrollView {
        if page == .pullRequests,
           let request = store.projectPullRequests.first(where: { $0.number == openedPullRequestNumber }) {
            PullRequestDetailView(
                pullRequest: request,
                repository: repository,
                store: store,
                onBack: { openedPullRequestNumber = nil }
            )
            .padding(28)
            .frame(maxWidth: 1600, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 7) {
                Button("All Projects", action: openAllProjects)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("breadcrumb-all-projects")
                Image(systemName: "chevron.right").workspaceFont(.caption2).foregroundStyle(.tertiary)
                ForEach(repository.fullName.split(separator: "/").map(String.init), id: \.self) { component in
                    Text(component).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").workspaceFont(.caption2).foregroundStyle(.tertiary)
                }
                Text(page.rawValue).fontWeight(.medium)
                    .accessibilityIdentifier("breadcrumb-current-page")
                Spacer()
            }
            .workspaceFont(.callout)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(repository.fullName).workspaceFont(.largeTitle, weight: .bold)
                    Text("GitHub · \(repository.visibilityDescription) · Local clone")
                        .workspaceFont(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = repository.safeGitHubURL {
                    Link("View on GitHub", destination: url)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(ProjectPage.allCases) { destination in
                    Button {
                        navigate(destination)
                    } label: {
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(page == destination ? Color.accentColor : Color.secondary)
                }
            }

            VStack {
                VStack(alignment: .leading, spacing: 12) {
                    Label(page.rawValue, systemImage: page.symbol)
                        .workspaceFont(.title2, weight: .bold)
                        .frame(maxWidth: .infinity, alignment: page == .overview ? .center : .leading)
                    if store.projectHistoryLoading {
                        ProgressView("Loading GitHub history…")
                    } else if let error = store.projectHistoryError {
                        ContentUnavailableView {
                            Label("GitHub history unavailable", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") { Task { await store.loadProjectHistory(repository: repository) } }
                        }
                    } else {
                        historyContent
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                .padding(8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }
        .padding(28)
        .frame(maxWidth: 1600, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        }
        .onChange(of: page) { _, newPage in
            if newPage != .pullRequests { openedPullRequestNumber = nil }
        }
        .task(id: "\(repository.id)-\(page.rawValue)") {
            await store.loadProjectHistory(repository: repository, forceRefresh: page == .pullRequests)
        }
        .sheet(isPresented: $showingCreatePullRequest, onDismiss: { createPullRequestHead = nil }) {
            CreatePullRequestView(repository: repository, branches: store.projectBranches, store: store, initialHead: createPullRequestHead)
                .frame(width: 520, height: 430)
                .dismissOnOutsideClick()
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        switch page {
        case .overview:
            VStack(alignment: .center, spacing: 16) {
                Text(repository.summary ?? "This repository has no description.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Label("\(store.projectBranches.count) branches · \(store.projectCommits.count) recent commits · \(store.projectPullRequests.count) pull requests", systemImage: "globe")
                    .workspaceFont(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        case .branches:
            if store.projectBranches.isEmpty { ContentUnavailableView("No branches returned", systemImage: "arrow.branch") }
            else {
                branchGraph
            }
        case .commits:
            if store.projectCommits.isEmpty { ContentUnavailableView("No commits returned", systemImage: "clock.arrow.circlepath") }
            else {
                commitTimeline
            }
        case .pullRequests:
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(store.projectPullRequests.filter { $0.state == "open" }.count) open")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("New pull request", systemImage: "plus") {
                        createPullRequestHead = nil
                        showingCreatePullRequest = true
                    }
                        .disabled(store.projectBranches.count < 2 || store.pullRequestActionInProgress)
                        .accessibilityIdentifier("create-pull-request")
                }
                if store.projectBranches.count < 2 {
                    Text("A pushed source branch and a different base branch are needed to create a pull request.")
                        .workspaceFont(.caption).foregroundStyle(.secondary)
                }
                if store.projectPullRequests.isEmpty {
                    ContentUnavailableView("No pull requests returned", systemImage: "arrow.triangle.pull")
                } else {
                    ForEach(store.projectPullRequests) { pullRequest in
                        PullRequestCard(
                            pullRequest: pullRequest,
                            sourceURL: safeGitHubURL(pullRequest.htmlURL),
                            onOpen: {
                                openedPullRequestNumber = pullRequest.number
                                Task { await store.loadPullRequestDetail(pullRequest.number, repository: repository) }
                            }
                        )
                        .id("\(repository.id)-\(pullRequest.number)")
                    }
                }
            }
        case .issues:
            Text("Issue history is not loaded yet.").foregroundStyle(.secondary)
        }
    }

    private var branchGraph: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Remote branch graph", systemImage: "point.3.connected.trianglepath.dotted")
                    .workspaceFont(.headline)
                Spacer()
                if let branch = store.selectedProjectBranch, branch != repository.defaultBranch {
                    Button("Create pull request", systemImage: "arrow.triangle.pull") {
                        createPullRequestHead = branch
                        showingCreatePullRequest = true
                    }
                    .disabled(store.projectBranches.count < 2 || store.pullRequestActionInProgress)
                    .accessibilityIdentifier("create-pull-request-from-selected-branch")
                }
                Text("GitHub · branch heads").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.projectBranches) { branch in
                        let selected = store.selectedProjectBranch == branch.name
                        Button {
                            Task { await store.selectProjectBranch(branch.name, repository: repository) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 7) {
                                    Circle().fill(selected ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width: 10, height: 10)
                                    Text(branch.name).workspaceFont(.callout, weight: .semibold).lineLimit(1)
                                }
                                Rectangle().fill(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.3)).frame(height: 2)
                                Text(branch.commit.sha.prefix(7)).workspaceFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                                if branch.name == repository.defaultBranch { Text("DEFAULT").workspaceFont(size: 9, weight: .bold).foregroundStyle(.tint) }
                            }
                            .frame(width: 150, alignment: .leading)
                            .padding(12)
                            .workspaceSurfaceBackground(selected ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("branch-graph-\(branch.name)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let branch = store.selectedProjectBranch {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tint)
                    Text("Commits on \(branch)").workspaceFont(.subheadline, weight: .semibold)
                    Text("· up to 100 recent").workspaceFont(.caption).foregroundStyle(.secondary)
                }
                commitTimeline
            }
        }
    }

    private var commitTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.projectCommits.enumerated()), id: \.element.id) { index, commit in
                VStack(alignment: .leading, spacing: 0) {
                    Button { store.selectProjectCommit(commit.sha) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().fill(store.selectedProjectCommitSHA == commit.sha ? Color.accentColor : Color.secondary.opacity(0.55))
                                    .frame(width: 10, height: 10).padding(.top, 4)
                                if index < store.projectCommits.count - 1 {
                                    Rectangle().fill(Color.secondary.opacity(0.22)).frame(width: 2).frame(minHeight: 30)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.commit.message.components(separatedBy: "\n").first ?? commit.sha).lineLimit(1)
                                Text("\(commit.sha.prefix(7)) · \(displayGitHubTimestamp(commit.commit.author?.date))")
                                    .workspaceFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedProjectCommitSHA == commit.sha { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("commit-\(commit.sha)")
                    if store.selectedProjectCommitSHA == commit.sha {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider().padding(.vertical, 4)
                            Text("Commit message").workspaceFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                            MarkdownMessageView(markdown: commit.commit.message, id: "commit-\(commit.sha)")
                            HStack {
                                Text(commit.sha.prefix(12)).workspaceFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                                Spacer()
                                if let url = safeGitHubURL(commit.htmlURL) { Link("Open commit on GitHub", destination: url).accessibilityIdentifier("open-selected-commit") }
                            }
                        }
                        .padding(14)
                        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("selected-commit-details")
                    }
                }
            }
        }
    }

}

private func safeGitHubURL(_ url: URL) -> URL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "https", components.host == "github.com",
          components.user == nil, components.password == nil, components.port == nil,
          components.query == nil, components.fragment == nil else { return nil }
    return url
}

private struct CreatePullRequestView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: GitHubRepository
    let branches: [GitHubBranch]
    let store: WorkspaceStore
    var initialHead: String? = nil
    @State private var head = ""
    @State private var base = ""
    @State private var title = ""
    @State private var requestBody = ""
    @State private var errorMessage: String?

    private var branchNames: [String] { branches.map(\.name) }
    private var headOptions: [String] { branchNames.filter { $0 != base } }
    private var canCreate: Bool {
        !head.isEmpty && !base.isEmpty && head != base
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.pullRequestActionInProgress
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Compare branch", selection: $head) {
                    ForEach(headOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Base branch", selection: $base) {
                    ForEach(branchNames, id: \.self) { Text($0).tag($0) }
                }
                TextField("Pull request title", text: $title)
                    .accessibilityIdentifier("new-pull-request-title")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                    TextEditor(text: $requestBody).frame(minHeight: 120)
                        .accessibilityIdentifier("new-pull-request-description")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).workspaceFont(.callout)
                }
            }
            .navigationTitle("Create pull request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if store.pullRequestActionInProgress { ProgressView().controlSize(.small) }
                        else { Text("Create") }
                    }
                    .disabled(!canCreate)
                    .accessibilityIdentifier("submit-create-pull-request")
                }
            }
            .onAppear {
                base = repository.defaultBranch ?? branchNames.first ?? ""
                head = initialHead.flatMap { branchNames.contains($0) && $0 != base ? $0 : nil }
                    ?? branchNames.first(where: { $0 != base }) ?? ""
            }
            .onChange(of: base) { _, newBase in
                if head == newBase { head = branchNames.first(where: { $0 != newBase }) ?? "" }
            }
        }
    }

    private func create() async {
        do {
            _ = try await store.createPullRequest(repository: repository, head: head, base: base, title: title, body: requestBody)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PullRequestCard: View {
    let pullRequest: GitHubPullRequest
    let sourceURL: URL?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: pullRequest.state == "open" ? "arrow.triangle.pull" : "checkmark.circle")
                    .workspaceFont(.title3).foregroundStyle(pullRequest.state == "open" ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(pullRequest.title) #\(pullRequest.number)")
                        .workspaceFont(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("\(pullRequest.state.capitalized) · @\(pullRequest.user?.login ?? "unknown") · updated \(displayGitHubTimestamp(pullRequest.updatedAt))")
                        .workspaceFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if sourceURL != nil {
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right").workspaceFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pull-request-\(pullRequest.number)")
    }
}

private enum PullRequestDetailTab: String, CaseIterable, Identifiable {
    case conversation = "Conversation"
    case commits = "Commits"
    case checks = "Checks"
    case filesChanged = "Files changed"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .conversation: "text.bubble"
        case .commits: "point.3.connected.trianglepath.dotted"
        case .checks: "checklist"
        case .filesChanged: "doc.text"
        }
    }
}

private struct PullRequestDetailView: View {
    let pullRequest: GitHubPullRequest
    let repository: GitHubRepository
    let store: WorkspaceStore
    let onBack: () -> Void
    @State private var selectedTab: PullRequestDetailTab = .conversation
    @State private var responseText = ""
    @State private var showsMergeConfirmation = false
    @State private var mergeCommitTitle = ""
    @State private var mergeCommitMessage = ""

    private var canWrite: Bool { pullRequest.state == "open" }
    private var commitCount: Int { pullRequest.commits ?? store.selectedPullRequestCommits.count }
    private var fileCount: Int { pullRequest.changedFiles ?? store.selectedPullRequestFiles.count }
    private var changeStats: String {
        "+\(pullRequest.additions ?? store.selectedPullRequestFiles.reduce(0) { $0 + $1.additions }) −\(pullRequest.deletions ?? store.selectedPullRequestFiles.reduce(0) { $0 + $1.deletions })"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Pull Requests", systemImage: "chevron.left", action: onBack)
                .buttonStyle(.plain).foregroundStyle(.secondary)

            header
            tabBar
            if showsMergeConfirmation { mergeConfirmationView }

            HStack(alignment: .top, spacing: 24) {
                tabContent.frame(maxWidth: .infinity, alignment: .leading)
                metadataSidebar.frame(width: 245, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pull-request-detail-\(pullRequest.number)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(pullRequest.title).workspaceFont(size: 27, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text("#\(pullRequest.number)").workspaceFont(size: 25).foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Button {
                    selectedTab = .checks
                } label: {
                    Label(mergeStatus, systemImage: pullRequest.mergeable == true ? "checkmark.circle" : "circle")
                }
                .buttonStyle(.bordered)
                Menu {
                    if let sourceURL = safeGitHubURL(pullRequest.htmlURL) {
                        Link("Open on GitHub", destination: sourceURL)
                    }
                } label: {
                    Label("Code", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                if canWrite {
                    Button("Merge…", systemImage: "arrow.triangle.merge") { beginMergeConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.pullRequestActionInProgress)
                        .accessibilityIdentifier("pull-request-merge-\(pullRequest.number)")
                }
            }
            HStack(spacing: 7) {
                Label(pullRequest.mergedAt == nil ? pullRequest.state.capitalized : "Merged", systemImage: pullRequest.mergedAt == nil ? (pullRequest.state == "open" ? "arrow.triangle.pull" : "checkmark") : "checkmark")
                    .workspaceFont(.callout, weight: .semibold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .workspaceSurfaceBackground(pullRequest.mergedAt != nil ? Color.purple : (pullRequest.state == "open" ? Color.green : Color.secondary), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                Text("@\(pullRequest.user?.login ?? "unknown") wants to merge \(commitCount) \(commitCount == 1 ? "commit" : "commits") into")
                    .foregroundStyle(.secondary)
                Text(pullRequest.base?.ref ?? "base")
                    .workspaceFont(.callout, weight: .semibold, design: .monospaced)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .workspaceSurfaceBackground(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Text("from") .foregroundStyle(.secondary)
                Text(pullRequest.head?.ref ?? "head")
                    .workspaceFont(.callout, weight: .semibold, design: .monospaced)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .workspaceSurfaceBackground(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
        }
        .padding(.bottom, 2)
    }

    private var mergeStatus: String {
        if pullRequest.mergedAt != nil { return "Merged" }
        if pullRequest.state == "closed" { return "Closed" }
        if pullRequest.mergeable == true { return "Able to merge" }
        if pullRequest.mergeable == false { return "Conflicts" }
        return pullRequest.mergeableState?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Merge status"
    }

    private var mergeConfirmationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.merge")
                    .workspaceFont(.title2, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .workspaceSurfaceBackground(Color.green, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commit message").workspaceFont(.headline)
                    TextField("Commit message", text: $mergeCommitTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("merge-commit-title")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Extended description").workspaceFont(.headline)
                TextEditor(text: $mergeCommitMessage)
                    .workspaceFont(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .workspaceSurfaceBackground(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
                    .accessibilityIdentifier("merge-commit-description")
            }

            Text("GitHub will create the merge commit as @\(store.signedInUsername ?? pullRequest.user?.login ?? "your account").")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Confirm merge", systemImage: "arrow.triangle.merge") {
                    showsMergeConfirmation = false
                    Task {
                        await store.mergePullRequest(repository: repository, number: pullRequest.number, commitTitle: mergeCommitTitle, commitMessage: mergeCommitMessage)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(mergeCommitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.pullRequestActionInProgress)
                .accessibilityIdentifier("confirm-pull-request-merge")
                Button("Cancel") { showsMergeConfirmation = false }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
        .accessibilityIdentifier("merge-confirmation-form")
    }

    private func beginMergeConfirmation() {
        let head = (pullRequest.head?.label ?? "\(repository.owner.login):\(pullRequest.head?.ref ?? "head")").replacingOccurrences(of: ":", with: "/")
        mergeCommitTitle = "Merge pull request #\(pullRequest.number) from \(head)"
        mergeCommitMessage = pullRequest.title
        showsMergeConfirmation = true
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PullRequestDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Label(tab.rawValue, systemImage: tab.symbol)
                        Text("\(count(for: tab))")
                            .workspaceFont(.caption, weight: .semibold, monospacedDigits: true)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .workspaceSurfaceBackground(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .workspaceSurfaceBackground(selectedTab == tab ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pull-request-tab-\(tab.id.replacingOccurrences(of: " ", with: "-").lowercased())")
            }
            Spacer(minLength: 8)
            Text(changeStats).workspaceFont(.caption, weight: .semibold, monospacedDigits: true)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pull-request-change-stats")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1) }
    }

    private func count(for tab: PullRequestDetailTab) -> Int {
        switch tab {
        case .conversation: store.selectedPullRequestComments.count
        case .commits: commitCount
        case .checks: store.selectedPullRequestChecks.count
        case .filesChanged: fileCount
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.pullRequestDetailLoading {
                ProgressView("Loading pull request details…").padding(.vertical, 30)
            } else if let error = store.pullRequestDetailError {
                ContentUnavailableView("Pull request details unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                switch selectedTab {
                case .conversation: conversation
                case .commits: commits
                case .checks: checks
                case .filesChanged: filesChanged
                }
            }
            if store.selectedPullRequestNumber == pullRequest.number, let message = store.pullRequestActionMessage {
                Text(message).workspaceFont(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("pull-request-action-message")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.fill").workspaceFont(.title2).foregroundStyle(.secondary)
                    Text("@\(pullRequest.user?.login ?? "unknown")").fontWeight(.semibold)
                    Text("commented \(displayGitHubTimestamp(pullRequest.updatedAt))").foregroundStyle(.secondary)
                    Spacer()
                    Text("Author").workspaceFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.45)))
                }
                .padding(12)
                .workspaceSurfaceBackground(Color.accentColor.opacity(0.08))
                MarkdownPreviewView(markdown: pullRequest.body?.isEmpty == false ? pullRequest.body! : "No description provided.")
                    .padding(18)
            }
            .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.55), lineWidth: 1))

            if store.selectedPullRequestComments.isEmpty && store.selectedPullRequestReviews.isEmpty && store.selectedPullRequestReviewComments.isEmpty {
                ContentUnavailableView("No conversation yet", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
            ForEach(store.selectedPullRequestComments) { comment in
                discussionCard(author: comment.user?.login ?? "unknown", timestamp: comment.createdAt, body: comment.body, symbol: "text.bubble")
            }
            ForEach(store.selectedPullRequestReviews) { review in
                discussionCard(author: review.user?.login ?? "unknown", timestamp: review.submittedAt, body: review.body ?? review.state, symbol: "checkmark.bubble")
            }
            ForEach(store.selectedPullRequestReviewComments) { comment in
                discussionCard(author: comment.user?.login ?? "unknown", timestamp: comment.createdAt, body: "\(comment.path ?? "Changed file") · \(comment.body)", symbol: "text.bubble")
            }

            if canWrite { reviewComposer }
        }
    }

    private func discussionCard(author: String, timestamp: String?, body: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text("@\(author)").fontWeight(.semibold)
                Text("commented \(displayGitHubTimestamp(timestamp))").foregroundStyle(.secondary)
            }
            Text(body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
    }

    private var commits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commits on this pull request").workspaceFont(.headline)
            if store.selectedPullRequestCommits.isEmpty {
                ContentUnavailableView("No commits returned", systemImage: "point.3.connected.trianglepath.dotted")
            }
            ForEach(store.selectedPullRequestCommits) { commit in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(.tint).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.commit.message.components(separatedBy: "\n").first ?? commit.sha)
                            .fontWeight(.medium).lineLimit(2)
                        Text("\(commit.sha.prefix(7)) · \(displayGitHubTimestamp(commit.commit.author?.date))")
                            .workspaceFont(.caption, design: .monospaced).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("Open", destination: commit.htmlURL)
                }
                .padding(12)
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Checks").workspaceFont(.headline)
            if let error = store.selectedPullRequestChecksError {
                ContentUnavailableView("Checks unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if store.selectedPullRequestChecks.isEmpty {
                ContentUnavailableView("No checks reported", systemImage: "checklist")
            }
            ForEach(store.selectedPullRequestChecks) { check in
                HStack(spacing: 10) {
                    Image(systemName: check.conclusion == "success" ? "checkmark.circle.fill" : check.status == "completed" ? "xmark.circle.fill" : "clock")
                        .foregroundStyle(check.conclusion == "success" ? Color.green : check.status == "completed" ? Color.red : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.name).fontWeight(.medium)
                        Text(check.conclusion ?? check.status).workspaceFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = check.htmlURL { Link("Details", destination: url) }
                }
                .padding(12)
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var filesChanged: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changed files (\(store.selectedPullRequestFiles.count))").workspaceFont(.headline)
            if store.selectedPullRequestFiles.isEmpty {
                ContentUnavailableView("No changed files returned", systemImage: "doc.text")
            }
            ForEach(store.selectedPullRequestFiles) { file in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(file.filename).workspaceFont(.callout, design: .monospaced).textSelection(.enabled)
                        Spacer()
                        Text("+\(file.additions)").foregroundStyle(.green)
                        Text("−\(file.deletions)").foregroundStyle(.red)
                    }
                    if let patch = file.patch {
                        ScrollView(.horizontal) {
                            Text(patch).workspaceFont(.caption, design: .monospaced).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Diff unavailable for this file.").workspaceFont(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
            }
        }
    }

    private var reviewComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leave a comment or review").workspaceFont(.headline)
            TextEditor(text: $responseText).workspaceFont(.body).frame(minHeight: 85, maxHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .accessibilityIdentifier("pull-request-review-response")
            HStack {
                Button("Comment") { submit(event: nil) }
                Button("Submit review") { submit(event: "COMMENT") }
                Button("Approve") { submit(event: "APPROVE") }
                Button("Request changes") { submit(event: "REQUEST_CHANGES") }
            }
            .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.pullRequestActionInProgress)
        }
        .padding(14)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metadataSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            metadataSection("Reviewers") {
                let requested = pullRequest.requestedReviewers ?? []
                if requested.isEmpty {
                    Text(store.selectedPullRequestReviews.isEmpty ? "No reviews" : store.selectedPullRequestReviews.map { "@\($0.user?.login ?? "unknown")" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(requested.enumerated()), id: \.offset) { _, reviewer in Text("@\(reviewer.login)") }
                }
                if canWrite { Text("Still in progress").foregroundStyle(.secondary) }
            }
            metadataSection("Assignees") {
                let assignees = pullRequest.assignees ?? []
                if assignees.isEmpty { Text("No one").foregroundStyle(.secondary) }
                else { ForEach(Array(assignees.enumerated()), id: \.offset) { _, user in Text("@\(user.login)") } }
            }
            metadataSection("Labels") {
                let labels = pullRequest.labels ?? []
                if labels.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                else {
                    HStack { ForEach(labels) { label in Text(label.name).workspaceFont(.caption, weight: .medium).padding(.horizontal, 8).padding(.vertical, 4).workspaceSurfaceBackground(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) } }
                }
            }
            metadataSection("Projects") { Text("None yet").foregroundStyle(.secondary) }
            metadataSection("Milestone") { Text(pullRequest.milestone?.title ?? "No milestone").foregroundStyle(.secondary) }
            metadataSection("Development") {
                Text("Successfully merging this pull request may close linked issues.").foregroundStyle(.secondary)
                Text("None yet").foregroundStyle(.secondary)
            }
            metadataSection("Notifications") { Text("Notification settings are managed by GitHub.").foregroundStyle(.secondary) }
        }
        .workspaceFont(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).workspaceFont(.subheadline, weight: .semibold).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "gearshape").workspaceFont(.caption).foregroundStyle(.tertiary)
            }
            content()
            Divider()
        }
    }

    private func submit(event: String?) {
        let body = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        Task {
            if let event {
                await store.submitPullRequestReview(body, event: event, repository: repository, number: pullRequest.number)
            } else {
                await store.postPullRequestComment(body, repository: repository, number: pullRequest.number)
            }
            if store.pullRequestActionMessage == "Comment posted." || store.pullRequestActionMessage == "Review submitted." {
                responseText = ""
            }
        }
    }
}

struct MarkdownMessageView: View {
    let markdown: String
    let id: String
    @State private var isExpanded = true
    @State private var showsMarkdownSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Minimize" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .accessibilityIdentifier("message-toggle-\(id)")
                Button("Preview") { showsMarkdownSource = false }
                    .tint(showsMarkdownSource ? .secondary : .accentColor)
                    .accessibilityIdentifier("message-preview-\(id)")
                Button("Markdown") { showsMarkdownSource = true }
                    .tint(showsMarkdownSource ? .accentColor : .secondary)
                    .accessibilityIdentifier("message-markdown-\(id)")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if isExpanded {
                Group {
                    if showsMarkdownSource {
                        Text(markdown).workspaceFont(.body, design: .monospaced)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("message-source-\(id)")
                    } else {
                        MarkdownPreviewView(markdown: markdown)
                            .accessibilityIdentifier("message-preview-content-\(id)")
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }
}

func readableMarkdown(_ markdown: String) -> AttributedString {
    (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
}

enum MarkdownBlockStyle: Equatable {
    case heading(Int)
    case paragraph
    case unorderedItem
    case orderedItem(String)
    case quote
    case code
    case divider
}

struct MarkdownBlock: Equatable, Identifiable {
    let id: Int
    let text: String
    let style: MarkdownBlockStyle
}

func markdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String]?

    func append(_ text: String, style: MarkdownBlockStyle) {
        blocks.append(MarkdownBlock(id: blocks.count, text: text, style: style))
    }

    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        append(paragraph.joined(separator: " "), style: .paragraph)
        paragraph.removeAll(keepingCapacity: true)
    }

    for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let codeLines = code {
            if trimmed.hasPrefix("```") {
                append(codeLines.joined(separator: "\n"), style: .code)
                code = nil
            } else {
                code?.append(line)
            }
            continue
        }
        if trimmed.hasPrefix("```") {
            flushParagraph()
            code = []
            continue
        }
        if trimmed.isEmpty {
            flushParagraph()
            continue
        }

        let headingDepth = trimmed.prefix(while: { $0 == "#" }).count
        if (1...6).contains(headingDepth), trimmed.dropFirst(headingDepth).first?.isWhitespace == true {
            flushParagraph()
            append(String(trimmed.dropFirst(headingDepth)).trimmingCharacters(in: .whitespaces), style: .heading(headingDepth))
            continue
        }
        if ["---", "***", "___"].contains(trimmed) {
            flushParagraph()
            append("", style: .divider)
            continue
        }

        let item = line.drop(while: \.isWhitespace)
        if let marker = ["- ", "* ", "+ "].first(where: { item.hasPrefix($0) }) {
            flushParagraph()
            append(String(item.dropFirst(marker.count)), style: .unorderedItem)
            continue
        }
        let digits = item.prefix(while: \.isNumber)
        let suffix = item.dropFirst(digits.count)
        if !digits.isEmpty, let delimiter = suffix.first, [".", ")"].contains(delimiter), suffix.dropFirst().first?.isWhitespace == true {
            flushParagraph()
            append(String(suffix.dropFirst(2)), style: .orderedItem("\(digits)\(delimiter)"))
            continue
        }
        if trimmed.hasPrefix(">") {
            flushParagraph()
            append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces), style: .quote)
            continue
        }
        paragraph.append(trimmed)
    }

    if let code { append(code.joined(separator: "\n"), style: .code) }
    flushParagraph()
    return blocks
}

private struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(markdownBlocks(markdown)) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil, components.user == nil, components.password == nil else {
                return .discarded
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.style {
        case let .heading(level):
            Text(readableMarkdown(block.text))
                .workspaceFont(size: [0: 23, 1: 23, 2: 20, 3: 18, 4: 16, 5: 15, 6: 14][level] ?? 14, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            Text(readableMarkdown(block.text))
                .workspaceFont(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .unorderedItem, .orderedItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.style == .unorderedItem ? "•" : orderedMarker(block.style))
                    .foregroundStyle(.secondary)
                Text(readableMarkdown(block.text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                Text(readableMarkdown(block.text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 8)
        case .code:
            Text(block.text)
                .workspaceFont(.body, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        case .divider:
            Divider()
        }
    }

    private func orderedMarker(_ style: MarkdownBlockStyle) -> String {
        guard case let .orderedItem(marker) = style else { return "" }
        return marker
    }
}

private struct SettingsView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var providerIntegrations: ProviderIntegrationsStore
    @AppStorage("contentAreaOpacity") private var contentAreaOpacity = 1.0
    @AppStorage("workspaceFontSize") private var workspaceFontSize = "medium"
    @AppStorage("workspaceAppearance") private var workspaceAppearance = "system"
    @AppStorage("quickSummaryEnabled") private var quickSummaryEnabled = true
    @AppStorage("quickSummaryPollingIntervalSeconds") private var quickSummaryPollingIntervalSeconds = 60
    @AppStorage("quickSummarySystemNotificationsEnabled") private var quickSummarySystemNotificationsEnabled = false
    @State private var notificationPermissionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard("Appearance") {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Picker("Theme", selection: $workspaceAppearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("appearance-theme")
                    }
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Picker("Font Size", selection: $workspaceFontSize) {
                            Text("Small").tag("small")
                            Text("Medium").tag("medium")
                            Text("Large").tag("large")
                            Text("XL").tag("xl")
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("appearance-font-size")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Card Background Opacity")
                            Spacer()
                            Text("\(Int(contentAreaOpacity * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $contentAreaOpacity, in: 0.2...1, step: 0.05)
                            .accessibilityIdentifier("content-area-opacity")
                    }
                }
                settingsCard("Quick Summary") {
                    Toggle("Show notch summary", isOn: $quickSummaryEnabled)
                    HStack {
                        Text("PR refresh interval")
                        Spacer()
                        Picker("PR refresh interval", selection: $quickSummaryPollingIntervalSeconds) {
                            Text("1 minute").tag(60)
                            Text("5 minutes").tag(300)
                            Text("15 minutes").tag(900)
                        }
                        .labelsHidden()
                    }
                    Toggle("macOS notifications", isOn: $quickSummarySystemNotificationsEnabled)
                        .onChange(of: quickSummarySystemNotificationsEnabled) { _, enabled in
                            Task {
                                let allowed = await store.setSummarySystemNotificationsEnabled(enabled)
                                if !allowed {
                                    quickSummarySystemNotificationsEnabled = false
                                    notificationPermissionMessage = "Notifications were not enabled. You can allow them in System Settings."
                                } else {
                                    notificationPermissionMessage = nil
                                }
                            }
                        }
                    if let notificationPermissionMessage {
                        Text(notificationPermissionMessage).foregroundStyle(.secondary)
                    }
                    Text("In-app popups are always available. System notifications are optional.")
                        .foregroundStyle(.secondary)
                }
                settingsCard("GitHub") {
                    Text("Connection: \(store.connectionState.label)")
                    if !store.repositories.isEmpty {
                        Button("Sign Out", role: .destructive) { store.signOut() }
                    } else if case .needsConfiguration = store.connectionState {
                        Text("Client ID is read from the app’s GitHubClientID configuration key.")
                            .foregroundStyle(.secondary)
                    }
                }
                settingsCard("Coding Providers") {
                    ProviderSettingsView(integrations: providerIntegrations)
                }
                settingsCard("Access") {
                    Text("GitHub writes are limited to pull request creation, comments, reviews, and confirmed merges. The app never pushes local branches. Sign out removes the token and leaves local clones untouched.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).workspaceFont(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
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
