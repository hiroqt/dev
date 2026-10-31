import SwiftUI

struct ProviderUsageSummary: View {
    @Bindable var integrations: ProviderIntegrationsStore
    @AppStorage("providerIntegration.codex.enabled") private var codexEnabled = true
    @AppStorage("providerIntegration.antigravity.enabled") private var antigravityEnabled = false

    private var canRefreshUsage: Bool {
        (codexEnabled && integrations.executablePaths[.codex] != nil)
            || (antigravityEnabled && integrations.executablePaths[.antigravity] != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("AI usage", systemImage: "chart.bar.xaxis").workspaceFont(.subheadline, weight: .semibold)
                Spacer()
                Button("Refresh") { Task { await integrations.refreshUsage() } }
                    .font(.caption)
                    .disabled(integrations.isRefreshingUsage || !canRefreshUsage)
                    .accessibilityIdentifier("provider-usage-refresh")
            }
            ForEach(CodingProvider.allCases) { provider in
                ProviderUsageSummaryRow(provider: provider, snapshot: integrations.usageSnapshots[provider])
            }
        }
    }
}

private struct ProviderUsageSummaryRow: View {
    let provider: CodingProvider
    let snapshot: ProviderUsageSnapshot?
    @State private var expanded = false
    @AppStorage private var plan: String
    @AppStorage private var otherPlan: String
    @AppStorage private var globallyEnabled: Bool

    init(provider: CodingProvider, snapshot: ProviderUsageSnapshot?) {
        self.provider = provider
        self.snapshot = snapshot
        _plan = AppStorage(wrappedValue: "Not selected", ProviderIntegrationPreferences.planKey(provider))
        _otherPlan = AppStorage(wrappedValue: "", "providerIntegration.\(provider.rawValue).otherPlan")
        _globallyEnabled = AppStorage(wrappedValue: provider.defaultEnabled, ProviderIntegrationPreferences.globalKey(provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(provider.logoAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Spacer()
                    Text(statusLabel)
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("provider-usage-\(provider.rawValue)")
            .accessibilityLabel("\(provider.name), \(statusLabel)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                usageDetails
            }
        }
    }

    private var usageDetails: some View {
            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot?.planType.map { "Detected plan: \($0.capitalized)" } ?? planLabel.map { "Plan label: \($0)" } ?? "Plan not selected")
                    .font(.caption).foregroundStyle(.secondary)
                if let snapshot {
                    ForEach(Array(snapshot.groups.enumerated()), id: \.offset) { item in
                        let group = item.element
                        Text(group.name).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(group.buckets.enumerated()), id: \.offset) { item in
                            let bucket = item.element
                            HStack {
                                Text(bucket.name)
                                Spacer()
                                Text("\(bucket.remainingPercent)% left").monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                    if !hasWindow(.fiveHour) { usageLine("5-hour limit") }
                    if !hasWindow(.weekly) { usageLine("Weekly limit") }
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text(snapshot.credits ?? "Unavailable").monospacedDigit()
                    }
                    .font(.caption)
                    Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    usageLine("5-hour limit")
                    usageLine("Weekly limit")
                    usageLine("Credits")
                    Text("Usage data is unavailable in dev. Check it with \(provider.usageCommand) in the provider CLI.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Link("Manage usage / help", destination: provider.usageGuideURL)
                    .font(.caption)
            }
            .padding(.leading, 20)
            .padding(.vertical, 4)
    }

    private var planLabel: String? {
        if plan == "Other" { return otherPlan.isEmpty ? nil : otherPlan }
        return plan == "Not selected" ? nil : plan
    }

    private var statusLabel: String {
        if !globallyEnabled { return "Off in Settings" }
        if snapshot?.groups.isEmpty == false { return "Updated" }
        return snapshot?.planType == nil ? "Unavailable" : "Plan detected"
    }

    private func hasWindow(_ window: ProviderUsageWindow) -> Bool {
        snapshot?.groups.contains { group in group.buckets.contains { $0.window == window } } ?? false
    }

    private func usageLine(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("Unavailable").foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
