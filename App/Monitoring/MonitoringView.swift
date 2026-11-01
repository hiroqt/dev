import SwiftUI
import Charts

struct MonitoringView: View {
    @Bindable var store: MonitoringStore
    @Bindable var integrations: ProviderIntegrationsStore
    @State private var tab = MonitoringTab.server
    @State private var hours = 24
    @State private var targetURL = ""
    @State private var targetError = false
    @State private var connection: MonitoringConnection = .vercel
    @State private var token = ""
    @State private var showingConnectionSetup = true
    @State private var deploymentProjectID: String?

    private var chartPoints: [MonitoringChartPoint] {
        let samples = store.samples.filter { $0.date > Date.now.addingTimeInterval(-Double(hours) * 3_600) }
        var segment = 0
        return samples.enumerated().map { index, sample in
            if index > 0, sample.date.timeIntervalSince(samples[index - 1].date) > 90 { segment += 1 }
            return MonitoringChartPoint(sample: sample, segment: segment)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Monitoring").workspaceFont(.largeTitle, weight: .bold)
                            Text("Your Mac, deployments, and AI accounts in one place.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Local monitoring", systemImage: "desktopcomputer").foregroundStyle(.secondary)
                    }
                    .id("monitoring-top")
                    Picker("Monitoring category", selection: $tab) {
                        ForEach(MonitoringTab.allCases) { item in
                            Text(item.rawValue).tag(item).accessibilityIdentifier("monitoring-tab-\(item.id)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("monitoring-tabs")
                    if let error = store.historyError { warning(error) }
                    switch tab {
                    case .server:
                        connectionsSection([.vercel, .render], title: "Server / Deployment")
                        if deploymentProjectID == nil { uptimeSection }
                    case .computer:
                        computerSection
                    case .ai:
                        aiSection
                        connectionsSection([.openAI, .anthropic], title: "API usage & billing")
                    }
                    Text("Monitoring runs while dev is running. Sleep and closed intervals are gaps, not successful checks. No prompts, source files, or HTTP response bodies are stored. Warnings appear here only.")
                        .workspaceFont(.caption).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity)
            }
            .onChange(of: deploymentProjectID) { _, _ in proxy.scrollTo("monitoring-top", anchor: .top) }
            .onChange(of: tab) { _, _ in proxy.scrollTo("monitoring-top", anchor: .top) }
        }
        .accessibilityIdentifier("monitoring-view")
        .onChange(of: connection) { _, _ in token = "" }
        .onChange(of: store.connected) { _, accounts in
            if !accounts.contains(.vercel) { deploymentProjectID = nil }
        }
        .onChange(of: tab) { _, selected in
            token = ""
            connection = selected == .ai ? .openAI : .vercel
        }
    }

    private var computerSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let error = store.systemError { warning(error) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], spacing: 12) {
                metric("CPU", value: store.current?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Sampling…", icon: "cpu")
                metric("Memory", value: store.current.map { "\(bytes($0.memoryUsed)) / \(bytes($0.memoryTotal))" } ?? "Sampling…", icon: "memorychip")
                metric("Swap", value: store.current.map { bytes($0.swapUsed) } ?? "—", icon: "arrow.left.arrow.right")
                metric("Disk available", value: store.current.map { bytes($0.diskFree) } ?? "—", icon: "internaldrive")
                metric("Download", value: store.current?.download.map { "\(bytes($0))/s" } ?? "Sampling…", icon: "arrow.down")
                metric("Upload", value: store.current?.upload.map { "\(bytes($0))/s" } ?? "Sampling…", icon: "arrow.up")
            }
            ComputerActivityView()
            ComputerStorageView()
            if let sample = store.current, sample.diskFree < 10_000_000_000 { warning("Less than 10 GB disk space available.") }
            HStack {
                Text("Mac activity").workspaceFont(.title2, weight: .semibold)
                Spacer()
                Picker("History", selection: $hours) {
                    Text("1 hour").tag(1)
                    Text("24 hours").tag(24)
                    Text("7 days").tag(168)
                }.pickerStyle(.segmented).frame(maxWidth: 280)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("CPU & memory").workspaceFont(.headline)
                Chart {
                    ForEach(chartPoints) { point in
                        let sample = point.sample
                        let segment = point.segment
                        LineMark(x: .value("Time", sample.date), y: .value("Percent", sample.memoryTotal > 0 ? sample.memoryUsed / sample.memoryTotal * 100 : 0), series: .value("Segment", "memory-\(segment)"))
                            .foregroundStyle(by: .value("Metric", "Memory"))
                        if let cpu = sample.cpuPercent {
                            LineMark(x: .value("Time", sample.date), y: .value("Percent", cpu), series: .value("Segment", "cpu-\(segment)"))
                                .foregroundStyle(by: .value("Metric", "CPU"))
                        }
                    }
                }.chartYScale(domain: 0...100).frame(height: 200)
                Text("RAM includes active, wired, and compressed pages. Network counts physical en interfaces; VPN and bridge traffic is excluded to avoid double counting. Minute samples are kept for seven days.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }.monitoringCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("Network throughput · MB/s").workspaceFont(.headline)
                Chart {
                    ForEach(chartPoints) { point in
                        let sample = point.sample
                        if let download = sample.download {
                            LineMark(x: .value("Time", sample.date), y: .value("MB/s", download / 1_000_000), series: .value("Segment", "down-\(point.segment)"))
                                .foregroundStyle(by: .value("Direction", "Download"))
                        }
                        if let upload = sample.upload {
                            LineMark(x: .value("Time", sample.date), y: .value("MB/s", upload / 1_000_000), series: .value("Segment", "up-\(point.segment)"))
                                .foregroundStyle(by: .value("Direction", "Upload"))
                        }
                    }
                }.frame(height: 160)
            }.monitoringCard()
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI subscription quotas").workspaceFont(.title2, weight: .semibold)
            ProviderUsageSummary(integrations: integrations)
            Text("Subscription quotas are separate from API charges. Claude subscription usage remains unavailable until a supported source is connected.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        }.monitoringCard()
    }

    private var uptimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Website uptime").workspaceFont(.title2, weight: .semibold)
            Text("Observed HTTPS HEAD checks from this Mac, once per minute (endpoints must support HEAD). Availability is the percentage of successful sampled checks, not continuous uptime.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("https://your-app.com/health", text: $targetURL).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("monitoring-uptime-url")
                Button("Add monitor") {
                    Task {
                        if await store.addTarget(targetURL) { targetURL = ""; targetError = false } else { targetError = true }
                    }
                }.disabled(targetURL.isEmpty)
            }
            if targetError { warning("Use a unique HTTPS URL without credentials, query, or fragment. Up to 20 targets are supported.") }
            if store.targets.isEmpty { Text("Add a URL to start measuring availability.").foregroundStyle(.secondary) }
            ForEach(store.targets) { target in
                let checks = store.observations.filter { $0.targetID == target.id }
                let latest = checks.last
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Link(target.url.absoluteString, destination: target.url)
                        Text(latest.map { "\($0.healthy ? "Responding" : "Check failed") · HTTP \($0.status.map(String.init) ?? "unavailable") · \($0.date.formatted(date: .abbreviated, time: .shortened))" } ?? "Waiting for first check")
                            .workspaceFont(.caption).foregroundStyle(latest?.healthy == false ? .orange : .secondary)
                        if let latest, Date.now.timeIntervalSince(latest.date) > 120 { Text("Stale · no recent check").foregroundStyle(.orange) }
                    }
                    Spacer()
                    if !checks.isEmpty {
                        Text(String(format: "%.1f%% observed", 100 * Double(checks.filter(\.healthy).count) / Double(checks.count)))
                    }
                    if let ms = latest?.milliseconds { Text(String(format: "%.0f ms", ms)).foregroundStyle(.secondary) }
                    Button("Remove", systemImage: "minus.circle") { Task { await store.removeTarget(target) } }.labelStyle(.iconOnly)
                        .accessibilityLabel("Remove monitor for \(target.url.host ?? "website")")
                }
                Divider()
            }
        }.monitoringCard()
    }

    private func connectionsSection(_ connections: [MonitoringConnection], title: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if tab != .server || deploymentProjectID == nil {
                HStack {
                    Text(title).workspaceFont(.title2, weight: .semibold)
                    Spacer()
                    Button("Refresh connections") { Task { await store.refreshRemote() } }.disabled(store.refreshing)
                }
                DisclosureGroup("Connection settings", isExpanded: $showingConnectionSetup) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Connection", selection: $connection) {
                            ForEach(connections) { Text($0.name).tag($0) }
                        }.frame(maxWidth: 300)
                        SecureField("Account token / organization reporting key", text: $token).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("monitoring-connection-token")
                        HStack {
                            Button("Save connection") {
                                let credential = token
                                let selectedConnection = connection
                                token = ""
                                Task { await store.connect(selectedConnection, token: credential) }
                            }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("Saved in macOS Keychain. Read-only requests only.").workspaceFont(.caption).foregroundStyle(.secondary)
                        }
                        if connection == .vercel {
                            Link("Create a Vercel access token", destination: URL(string: "https://vercel.com/account/tokens")!)
                            Text("Create a token with access to the account or team that owns your projects. Save it here to discover accessible personal and team projects. Select a project card to explore its deployment history.")
                                .workspaceFont(.caption).foregroundStyle(.secondary)
                        }
                        if tab == .ai {
                            Text("OpenAI and Anthropic require organization reporting/admin credentials, rather than ordinary project inference keys. Reports cover the last seven days; provider reporting may be delayed.")
                                .workspaceFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear { showingConnectionSetup = !connections.contains { store.connected.contains($0) } }
                .onChange(of: store.connected) { _, accounts in
                    if connections.contains(where: { accounts.contains($0) }) { showingConnectionSetup = false }
                }

            }
            ForEach(connections.filter { tab != .server || deploymentProjectID == nil || $0 == .vercel }) { item in
                if tab != .server || deploymentProjectID == nil {
                    Divider()
                    HStack {
                        Text(item.name).workspaceFont(.headline)
                        Spacer()
                        if let date = store.connectionDates[item] {
                            Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))").workspaceFont(.caption).foregroundStyle(.secondary)
                        }
                        if store.connected.contains(item) { Button("Disconnect") { store.disconnect(item) } }
                    }
                }
                if let error = store.connectionErrors[item] { warning(error) }
                if let date = store.connectionDates[item], Date.now.timeIntervalSince(date) > 600 { warning("Stale · last refresh more than 10 minutes ago.") }
                if !store.connected.contains(item) { Text("Not connected").foregroundStyle(.secondary) }
                if item == .vercel, store.connected.contains(.vercel) {
                    if !store.vercelWarnings.isEmpty {
                        DisclosureGroup("\(store.vercelWarnings.count) discovery notices") {
                            ForEach(Array(store.vercelWarnings.enumerated()), id: \.offset) { _, text in warning(text) }
                        }
                    }
                    VercelDeploymentDashboard(store: store, selectedProjectID: $deploymentProjectID)
                }
                if store.remoteRows[item]?.isEmpty == true { Text("No records returned in this account scope.").foregroundStyle(.secondary) }
                if item == .render {
                    RenderDeploymentDashboard(rows: store.remoteRows[item] ?? [])
                } else {
                    ForEach(store.remoteRows[item] ?? []) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            if let url = row.url { Link(row.title, destination: url) } else { Text(row.title).workspaceFont(.headline) }
                            Text(row.detail).workspaceFont(.subheadline).foregroundStyle(row.warning ? .orange : .secondary)
                        }
                    }
                }
            }
        }
        .padding(tab == .server ? 0 : 18)
        .workspaceSurfaceBackground(tab == .server ? Color.clear : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).workspaceFont(.subheadline).foregroundStyle(.secondary)
            Text(value).workspaceFont(.title3, weight: .semibold).monospacedDigit()
        }.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).monitoringCard()
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).workspaceFont(.caption)
    }

    private func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .memory)
    }
}

extension View {
    func monitoringCard() -> some View {
        padding(18).workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MonitoringChartPoint: Identifiable {
    var id: Date { sample.date }
    let sample: MonitoringSample
    let segment: Int
}

private enum MonitoringTab: String, CaseIterable, Identifiable {
    case server = "Server / Deployment"
    case computer = "Computer"
    case ai = "AI"

    var id: String {
        switch self {
        case .server: "server"
        case .computer: "computer"
        case .ai: "ai"
        }
    }
}
