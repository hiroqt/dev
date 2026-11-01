import SwiftUI
import Charts

func latestDeploymentBranches(_ deployments: [VercelDeployment]) -> [VercelDeployment] {
    var branches: [String: VercelDeployment] = [:]
    for deployment in deployments {
        guard let branch = deployment.branch, !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        if let previous = branches[branch], (previous.createdAt ?? .distantPast) >= (deployment.createdAt ?? .distantPast) { continue }
        branches[branch] = deployment
    }
    return branches.values.sorted {
        if $0.createdAt == $1.createdAt { return ($0.branch ?? "") < ($1.branch ?? "") }
        return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
    }
}

struct DeploymentInsights: View {
    let project: VercelProject
    let traffic: VercelTraffic?
    let deployments: [VercelDeployment]
    let hasMore: Bool

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
            GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
            GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top)
        ], alignment: .leading, spacing: 16) {
            observability.frame(maxWidth: .infinity, alignment: .leading).monitoringCard()
            analytics.frame(maxWidth: .infinity, alignment: .leading).monitoringCard()
            DeploymentBranches(deployments: deployments, hasMore: hasMore)
                .id(project.id).frame(maxWidth: .infinity, alignment: .leading).monitoringCard()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var observability: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Observability", systemImage: "waveform.path.ecg").workspaceFont(.headline)
            ForEach(["CDN requests", "Function invocations", "Error rate"], id: \.self) { title in
                HStack {
                    Text(title).workspaceFont(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("—").workspaceFont(.title2).foregroundStyle(.secondary)
                }
                Divider()
            }
            Text("Traffic, runtime errors and bandwidth are available in Vercel’s dashboard.").workspaceFont(.caption).foregroundStyle(.secondary)
            if let url = project.dashboardURL { Link("Open Observability ↗", destination: url.appending(path: "observability")) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private var analytics: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Web Analytics").workspaceFont(.headline); Spacer(); Text("7 days").workspaceFont(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 24) {
                count("Visitors", traffic?.visitors)
                count("Page views", traffic?.pageviews)
            }
            if let traffic, !traffic.daily.isEmpty {
                Chart(traffic.daily) { day in
                    BarMark(x: .value("Day (UTC)", day.date, unit: .day, calendar: utcCalendar), y: .value("Page views", day.pageviews))
                        .foregroundStyle(Color.accentColor.gradient).cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: Date.FormatStyle(timeZone: .gmt).month().day()) } }
                .environment(\.timeZone, .gmt)
                .environment(\.calendar, utcCalendar)
                .frame(height: 130)
                .accessibilityLabel("Daily page views, UTC; \(traffic.daily.count) reported days")
                Text("Daily page views · UTC · reported days only").workspaceFont(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.title2)
                    Text("No daily series").workspaceFont(.subheadline, weight: .semibold)
                    Text("A chart appears when Vercel returns daily data.").workspaceFont(.caption).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: 130)
            }
            if let traffic { Text(traffic.detail).workspaceFont(.caption).foregroundStyle(.secondary) }
            if traffic?.seriesUnavailable == true { Text("Daily series unavailable; totals remain visible.").workspaceFont(.caption).foregroundStyle(.orange) }
            if let url = project.dashboardURL { Link("Open Web Analytics ↗", destination: url.appending(path: "analytics")) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func count(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value?.formatted() ?? "—").workspaceFont(.title, weight: .semibold).monospacedDigit()
            Text(title).workspaceFont(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeploymentBranches: View {
    let deployments: [VercelDeployment]
    let hasMore: Bool
    @State private var query = ""
    @State private var readyOnly = false
    @State private var page = 0

    private var filtered: [VercelDeployment] {
        latestDeploymentBranches(deployments).filter {
            (!readyOnly || $0.state.uppercased() == "READY") && (query.isEmpty || ($0.branch ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let pagination = MonitoringPagination(total: filtered.count, page: page, pageSize: 5)
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Deployment branches").workspaceFont(.title2, weight: .semibold); Spacer(); Text("\(filtered.count) reported").workspaceFont(.caption).foregroundStyle(.secondary) }
            HStack {
                TextField("Search branches", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Ready only", isOn: $readyOnly).toggleStyle(.checkbox)
            }
            ForEach(Array(filtered[pagination.range])) { deployment in
                ViewThatFits(in: .horizontal) {
                    HStack { branchName(deployment); Spacer(); branchStatus(deployment) }
                    VStack(alignment: .leading, spacing: 10) { branchName(deployment); branchStatus(deployment) }
                }.padding(.vertical, 12)
                Divider()
            }
            if filtered.isEmpty { Text("No matching branches in loaded deployment history.").foregroundStyle(.secondary) }
            if pagination.pageCount > 1 {
                HStack {
                    Text(pagination.summary).workspaceFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous") { page = pagination.page - 1 }.disabled(pagination.page == 0)
                    Button("Next") { page = pagination.page + 1 }.disabled(pagination.page + 1 >= pagination.pageCount)
                }
            }
            Text("Latest deployment per branch in loaded history\(hasMore ? "; older records are available below" : ""). Git branch existence is not verified.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: readyOnly) { _, _ in page = 0 }
    }

    private func branchName(_ deployment: VercelDeployment) -> some View {
        Label(deployment.branch ?? "", systemImage: "arrow.triangle.branch").workspaceFont(.subheadline, weight: .medium).lineLimit(2)
    }

    private func branchStatus(_ deployment: VercelDeployment) -> some View {
        HStack(spacing: 12) {
            DeploymentStatusBadge(state: deployment.state)
            if let date = deployment.createdAt { Text(date, style: .relative).workspaceFont(.caption).foregroundStyle(.secondary) }
            if let url = deployment.url { Link(deployment.target == "production" ? "Production ↗" : "Preview ↗", destination: url) }
        }.workspaceFont(.caption)
    }
}
