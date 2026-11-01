import SwiftUI

struct MonitoringPagination {
    let total: Int
    let pageSize: Int
    let page: Int

    init(total: Int, page: Int, pageSize: Int) {
        self.total = max(0, total)
        self.pageSize = max(1, pageSize)
        let count = self.total == 0 ? 1 : (self.total - 1) / self.pageSize + 1
        self.page = min(max(0, page), count - 1)
    }

    var pageCount: Int { total == 0 ? 1 : (total - 1) / pageSize + 1 }
    var range: Range<Int> {
        let start = page * pageSize
        return start..<(start + min(pageSize, total - start))
    }
    var pageAfterLoading: Int { range.count < pageSize ? page : page + 1 }
    var summary: String { total == 0 ? "0 results" : "\(range.lowerBound + 1)–\(range.upperBound) of \(total)" }
}

struct VercelDeploymentDashboard: View {
    @Bindable var store: MonitoringStore
    @State private var query = ""
    @State private var projectPage = 0
    @Binding var selectedProjectID: String?
    @State private var scope = "All accounts"
    @State private var deploymentPage = 0
    @State private var selectedDeploymentID: String?
    @State private var navigationRevision = 0

    private var projects: [VercelProject] {
        store.vercelProjects.filter { project in
            (scope == "All accounts" || project.scopeName == scope)
                && (query.isEmpty || "\(project.name) \(project.scopeName)".localizedCaseInsensitiveContains(query))
        }
    }
    private var projectPagination: MonitoringPagination { .init(total: projects.count, page: projectPage, pageSize: 6) }
    private var selectedProject: VercelProject? { store.vercelProjects.first { $0.id == selectedProjectID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let project = selectedProject {
                projectOverview(project)
            } else {
                overview
            }
        }
        .onChange(of: query) { _, _ in projectPage = 0 }
        .onChange(of: scope) { _, _ in projectPage = 0 }
        .onChange(of: store.vercelProjects.map(\.id)) { _, ids in
            projectPage = projectPagination.page
            if let selectedProjectID, !ids.contains(selectedProjectID) { self.selectedProjectID = nil }
            if scope != "All accounts", !store.vercelProjects.contains(where: { $0.scopeName == scope }) { scope = "All accounts" }
        }
        .onChange(of: selectedProjectID) { _, _ in navigationRevision += 1; deploymentPage = 0; selectedDeploymentID = nil }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deployment workspace").workspaceFont(.title, weight: .bold)
                    Text("A clear view of your projects and the releases behind them.").workspaceFont(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(store.vercelProjects.count) projects", systemImage: "square.stack.3d.up")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    overviewRail.frame(width: 230).padding(.trailing, 20)
                        .overlay(alignment: .trailing) { Divider() }
                    projectBrowser.frame(minWidth: 500)
                }
                VStack(alignment: .leading, spacing: 20) { overviewRail; Divider(); projectBrowser }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vercel-project-overview")
        .monitoringCard()
    }

    private var overviewRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Account snapshot", systemImage: "square.grid.2x2").workspaceFont(.headline)
                railMetric("Visible projects", value: String(store.vercelProjects.count), icon: "shippingbox")
                railMetric("Production targets", value: String(store.vercelProjects.filter { $0.production != nil }.count), icon: "globe")
                railMetric("Account scopes", value: String(Set(store.vercelProjects.map { $0.teamID ?? "personal" }).count), icon: "person.2")
                Text("Inventory reported by Vercel. Usage quotas and bandwidth are viewed in Observability.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Label("Recent releases", systemImage: "clock.arrow.circlepath").workspaceFont(.headline)
                let recent = store.vercelProjects.filter { latest(for: $0) != nil }.sorted {
                    (latest(for: $0)?.createdAt ?? .distantPast) > (latest(for: $1)?.createdAt ?? .distantPast)
                }
                if recent.isEmpty { Text("Release metadata is not available yet.").workspaceFont(.caption).foregroundStyle(.secondary) }
                ForEach(Array(recent.prefix(4))) { project in
                    Button { open(project) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name).workspaceFont(.subheadline, weight: .semibold).lineLimit(1)
                            if let release = latest(for: project) {
                                Text(release.detail.isEmpty ? release.target : release.detail).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                                DeploymentStatusBadge(state: release.state)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Divider()
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Monitoring notes", systemImage: "waveform.path.ecg").workspaceFont(.headline)
                Text("Project status describes a deployment, not continuous uptime. Browser analytics and deployment records stay separate.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
                if !store.vercelWarnings.isEmpty {
                    Label("\(store.vercelWarnings.count) access or discovery notices above", systemImage: "exclamationmark.triangle")
                        .workspaceFont(.caption).foregroundStyle(.orange)
                }
            }
            Divider()
        }
    }

    private var projectBrowser: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { projectSearch; accountFilter.frame(width: 180) }
                VStack(alignment: .leading, spacing: 12) { projectSearch; accountFilter }
            }
            if store.refreshing { ProgressView("Syncing projects…") }
            if projects.isEmpty && !store.refreshing {
                ContentUnavailableView(query.isEmpty ? "No projects loaded" : "No matching projects", systemImage: "shippingbox", description: Text("Check your search, account filter, or connection permissions."))
            }
            VStack(spacing: 0) {
                ForEach(Array(projects[projectPagination.range])) { project in
                    projectCard(project)
                    Divider()
                }
            }
            if !projects.isEmpty {
                DeploymentPager(summary: "\(projectPagination.summary) projects", page: projectPagination.page, canPrevious: projectPagination.page > 0, canNext: projectPagination.page + 1 < projectPagination.pageCount, loading: false, identifier: "vercel-projects", previous: { projectPage = projectPagination.page - 1 }, next: { projectPage = projectPagination.page + 1 })
            }
        }
    }

    private var projectSearch: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search projects or teams", text: $query).textFieldStyle(.plain)
                .accessibilityIdentifier("vercel-project-search")
        }.padding(12).workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var accountFilter: some View {
        Picker("Account", selection: $scope) {
            Text("All accounts").tag("All accounts")
            ForEach(Array(Set(store.vercelProjects.map(\.scopeName))).sorted(), id: \.self) { Text($0).tag($0) }
        }.labelsHidden().accessibilityLabel("Filter deployment account")
    }

    private func railMetric(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).workspaceFont(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).workspaceFont(.title3, weight: .semibold).monospacedDigit()
        }
    }

    private func latest(for project: VercelProject) -> VercelDeployment? {
        [project.latest, project.production, store.vercelDeployments[project.id]?.first].compactMap { $0 }
            .max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private func open(_ project: VercelProject) {
        selectedProjectID = project.id
        if store.vercelDeployments[project.id] == nil { Task { await store.loadVercelDeployments(project) } }
    }

    private func projectCard(_ project: VercelProject) -> some View {
        let release = latest(for: project)
        return Button { open(project) } label: {
            HStack(spacing: 14) {
                WebsiteProjectLogo(websiteURL: project.primaryURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name).workspaceFont(.headline)
                    Text(project.primaryURL?.host ?? project.scopeName).workspaceFont(.caption).foregroundStyle(.secondary)
                    if let release {
                        Text(release.detail.isEmpty ? "Release metadata available" : release.detail).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Label(project.repository ?? project.scopeName, systemImage: "point.3.connected.trianglepath.dotted")
                        .workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if let release {
                        DeploymentStatusBadge(state: release.state)
                        if let date = release.createdAt { Text(date, style: .relative).workspaceFont(.caption).foregroundStyle(.secondary) }
                    } else { Text("Status not reported").workspaceFont(.caption).foregroundStyle(.secondary) }
                }
                Image(systemName: "chevron.right").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View deployments for \(project.name), \(project.scopeName)")
        .accessibilityIdentifier("vercel-project-\(project.id)")
    }

    private func projectOverview(_ project: VercelProject) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button { selectedProjectID = nil } label: { Label("All projects", systemImage: "chevron.left") }
                    .buttonStyle(.plain).accessibilityIdentifier("vercel-back-to-projects")
                Image(systemName: "chevron.right").workspaceFont(.caption).foregroundStyle(.tertiary)
                Text(project.name).workspaceFont(.subheadline, weight: .semibold)
                Spacer()
                Text(project.scopeName).workspaceFont(.caption).foregroundStyle(.secondary)
            }
            Divider()
            productionHero(project)
            Divider()
            DeploymentInsights(project: project, traffic: store.vercelTraffic[project.id], deployments: store.vercelDeployments[project.id] ?? [], hasMore: store.vercelNextCursors[project.id] != nil)
            Divider()
            history(project)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vercel-project-detail")
        .monitoringCard()
    }

    private func productionHero(_ project: VercelProject) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name).workspaceFont(.title, weight: .bold)
                    Label("Production release", systemImage: "globe").workspaceFont(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let production = project.production { DeploymentStatusBadge(state: production.state) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    endpointPanel(project).frame(width: 320).padding(.trailing, 24).overlay(alignment: .trailing) { Divider() }
                    productionMetadata(project).frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 18) { endpointPanel(project); productionMetadata(project) }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { releaseActions(project); Spacer(); Text("Production snapshot reported by Vercel").workspaceFont(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 12) { releaseActions(project); Text("Production snapshot reported by Vercel").workspaceFont(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func endpointPanel(_ project: VercelProject) -> some View {
        VStack(spacing: 14) {
            WebsiteProjectLogo(websiteURL: project.primaryURL, size: 96)
            Text(project.productionURL?.host ?? "No production endpoint reported").workspaceFont(.headline).multilineTextAlignment(.center).textSelection(.enabled)
            Text("Deployment endpoint").workspaceFont(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 24).frame(maxWidth: .infinity, minHeight: 250)
    }

    private func productionMetadata(_ project: VercelProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let production = project.production {
                metadataField("Deployment", value: production.url?.host ?? production.id)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status").workspaceFont(.caption).foregroundStyle(.secondary)
                        DeploymentStatusBadge(state: production.state)
                    }
                    metadataField("Created", value: production.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not reported")
                }
                Divider()
                metadataField("Source", value: [production.branch, production.commitSHA.map { String($0.prefix(7)) }].compactMap { $0 }.joined(separator: " · "))
                if !production.detail.isEmpty { Text(production.detail).workspaceFont(.subheadline).textSelection(.enabled) }
            } else {
                Label("No current production target reported", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                Text("Deployment history below may include previews or earlier releases.").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            if !project.domains.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Domains").workspaceFont(.caption).foregroundStyle(.secondary)
                    ForEach(Array(project.domains.prefix(3)), id: \.self) { domain in
                        if let url = MonitoringRemote.webURL("https://\(domain)") { Link(domain, destination: url) }
                    }
                    if project.domains.count > 3 { Text("+\(project.domains.count - 3) additional domains").workspaceFont(.caption).foregroundStyle(.secondary) }
                }
            }
            if let framework = project.framework { metadataField("Framework", value: framework) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func releaseActions(_ project: VercelProject) -> some View {
        HStack(spacing: 12) {
            if let url = project.productionURL {
                Link(destination: url) { Label("Visit production", systemImage: "arrow.up.right") }.buttonStyle(.borderedProminent)
            } else if let url = project.latest?.url {
                Link("Open latest deployment", destination: url).buttonStyle(.bordered)
            }
            if let url = project.repositoryURL { Link(destination: url) { Label("Source", systemImage: "chevron.left.forwardslash.chevron.right") }.buttonStyle(.bordered) }
            if let url = project.dashboardURL { Link("Project in Vercel", destination: url).buttonStyle(.bordered) }
        }.workspaceFont(.caption)
    }

    private func metadataField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).workspaceFont(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Not reported" : value).workspaceFont(.subheadline).textSelection(.enabled)
        }
    }

    private func history(_ project: VercelProject) -> some View {
        let requestRevision = navigationRevision
        let deployments = store.vercelDeployments[project.id] ?? []
        let pagination = MonitoringPagination(total: deployments.count, page: deploymentPage, pageSize: 5)
        let visible = Array(deployments[pagination.range])
        let loading = store.vercelLoading.contains(project.id)
        let moreAvailable = store.vercelNextCursors[project.id] != nil
        let selected = visible.first { $0.id == selectedDeploymentID } ?? visible.first
        return VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Deployment history").workspaceFont(.title2, weight: .semibold); Spacer(); projectActions(project, loading: loading) }
                VStack(alignment: .leading, spacing: 12) { Text("Deployment history").workspaceFont(.title2, weight: .semibold); projectActions(project, loading: loading) }
            }
            if let date = store.vercelDeploymentDates[project.id] {
                Text("History checked \(date.formatted(date: .abbreviated, time: .shortened))").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            if let error = store.vercelProjectErrors[project.id] {
                Label(error, systemImage: "exclamationmark.triangle").workspaceFont(.caption).foregroundStyle(.orange)
            }
            if loading { ProgressView("Reading Vercel…") }
            if deployments.isEmpty && !loading {
                ContentUnavailableView("No deployments loaded", systemImage: "clock.arrow.circlepath", description: Text("Refresh history to retry, or open the project in Vercel."))
            }
            ForEach(visible) { deployment in
                deploymentRow(deployment, latest: deployments.first?.id == deployment.id, selected: selected?.id == deployment.id)
                Divider()
            }
            if !deployments.isEmpty {
                DeploymentPager(summary: "\(pagination.summary) loaded\(moreAvailable ? " · more available" : "")", page: pagination.page, canPrevious: pagination.page > 0, canNext: pagination.page + 1 < pagination.pageCount || moreAvailable, loading: loading, identifier: "vercel-history", nextLabel: pagination.range.count < pagination.pageSize && moreAvailable ? "Load more deployments" : "Next page", previous: {
                    deploymentPage = pagination.page - 1; selectedDeploymentID = nil
                }, next: {
                    Task {
                        guard selectedProjectID == project.id, navigationRevision == requestRevision, deploymentPage == pagination.page else { return }
                        if pagination.page + 1 < pagination.pageCount {
                            deploymentPage = pagination.page + 1; selectedDeploymentID = nil
                        } else {
                            await store.loadVercelDeployments(project, more: true)
                            guard selectedProjectID == project.id, navigationRevision == requestRevision, deploymentPage == pagination.page, (store.vercelDeployments[project.id]?.count ?? 0) > deployments.count else { return }
                            if pagination.pageAfterLoading != deploymentPage { selectedDeploymentID = nil }
                            deploymentPage = pagination.pageAfterLoading
                        }
                    }
                })
            }
            if let selected { deploymentDetails(selected) }

        }

        .onChange(of: store.vercelDeploymentDates[project.id]) { _, _ in deploymentPage = 0; selectedDeploymentID = nil }
        .onChange(of: store.connectionDates[.vercel]) { _, _ in Task { await store.loadVercelDeployments(project) } }
    }

    private func projectActions(_ project: VercelProject, loading: Bool) -> some View {
        HStack(spacing: 12) {
            Button { deploymentPage = 0; selectedDeploymentID = nil; Task { await store.loadVercelDeployments(project) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }.disabled(loading).help("Refresh deployment history")
            if let url = project.dashboardURL {
                Link("Observability", destination: url.appending(path: "observability"))
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("Open project in Vercel")
            }
        }.workspaceFont(.caption)
    }

    private func deploymentRow(_ deployment: VercelDeployment, latest: Bool, selected: Bool) -> some View {
        Button { selectedDeploymentID = deployment.id } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(latest ? "Latest deployment" : String(deployment.id.suffix(10))).workspaceFont(.subheadline, weight: .semibold)
                        Spacer()
                        DeploymentStatusBadge(state: deployment.state)
                    }
                    Text(deployment.detail.isEmpty ? deployment.target : deployment.detail).workspaceFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack {
                        Label(deployment.target, systemImage: "point.3.connected.trianglepath.dotted")
                        Spacer()
                        if let date = deployment.createdAt { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                    }.workspaceFont(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vercel-deployment-\(deployment.id)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func deploymentDetails(_ deployment: VercelDeployment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Deployment details", systemImage: "doc.text.magnifyingglass").workspaceFont(.headline)
            Text(deployment.id).workspaceFont(.caption).monospaced().textSelection(.enabled)
            if !deployment.detail.isEmpty { Text(deployment.detail).workspaceFont(.subheadline).textSelection(.enabled) }
            if let url = deployment.url { Link(destination: url) { Label(url.host ?? "Open deployment", systemImage: "arrow.up.right.square") } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .workspaceSurfaceBackground(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RenderDeploymentDashboard: View {
    let rows: [MonitoringRemoteRow]
    @State private var page = 0

    var body: some View {
        let records = rows.filter { $0.id != "partial" }
        let pagination = MonitoringPagination(total: records.count, page: page, pageSize: 6)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.filter { $0.id == "partial" }) { row in
                Label(row.detail, systemImage: "exclamationmark.triangle").workspaceFont(.caption).foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 12) {
                ForEach(Array(records[pagination.range])) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(row.title, systemImage: "server.rack").workspaceFont(.headline)
                        Text(row.detail).workspaceFont(.caption).foregroundStyle(row.warning ? .orange : .secondary)
                        if let url = row.url { Link("Open service", destination: url) }
                    }.frame(maxWidth: .infinity, alignment: .leading).monitoringCard()
                }
            }
            if !records.isEmpty {
                DeploymentPager(summary: "\(pagination.summary) loaded services", page: pagination.page, canPrevious: pagination.page > 0, canNext: pagination.page + 1 < pagination.pageCount, loading: false, identifier: "render-services", previous: { page = pagination.page - 1 }, next: { page = pagination.page + 1 })
            }
        }.onChange(of: rows.map(\.id)) { _, _ in page = 0 }
    }
}

struct DeploymentStatusBadge: View {
    let state: String
    private var color: Color {
        switch state.uppercased() {
        case "READY": .green
        case "ERROR": .red
        case "BUILDING", "QUEUED", "INITIALIZING": .orange
        default: .secondary
        }
    }
    var body: some View {
        Label(state.capitalized, systemImage: state.uppercased() == "READY" ? "checkmark.circle.fill" : state.uppercased() == "ERROR" ? "xmark.circle.fill" : "clock")
            .workspaceFont(.caption).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DeploymentPager: View {
    let summary: String
    let page: Int
    let canPrevious: Bool
    let canNext: Bool
    let loading: Bool
    let identifier: String
    var nextLabel = "Next page"
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Text(summary).workspaceFont(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(action: previous) { Image(systemName: "chevron.left") }.disabled(!canPrevious || loading)
                .accessibilityLabel("Previous page").accessibilityIdentifier("\(identifier)-previous")
            Text("Page \(page + 1)").workspaceFont(.caption).monospacedDigit()
            Button(action: next) { Image(systemName: "chevron.right") }.disabled(!canNext || loading)
                .accessibilityLabel(nextLabel).help(nextLabel).accessibilityIdentifier("\(identifier)-next")
        }
    }
}
