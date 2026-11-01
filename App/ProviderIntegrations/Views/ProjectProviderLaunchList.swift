import SwiftUI

struct ProjectProviderLaunchList: View {
    @Bindable var integrations: ProviderIntegrationsStore
    let projectID: String?
    let launch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coding providers").workspaceFont(.headline)
            if let projectID {
                ForEach(CodingProvider.allCases) { provider in
                    ProviderProjectRow(provider: provider, projectID: projectID, integrations: integrations) {
                        launch(provider.launchCommand)
                    }
                }
            } else {
                Text("Select a project to configure or launch its providers.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await integrations.refreshAvailability() }
    }
}

private struct ProviderProjectRow: View {
    let provider: CodingProvider
    let projectID: String
    @Bindable var integrations: ProviderIntegrationsStore
    let launch: () -> Void
    @AppStorage private var globallyEnabled: Bool
    @AppStorage private var projectEnabled: Bool

    init(provider: CodingProvider, projectID: String, integrations: ProviderIntegrationsStore, launch: @escaping () -> Void) {
        self.provider = provider
        self.projectID = projectID
        self.integrations = integrations
        self.launch = launch
        _globallyEnabled = AppStorage(wrappedValue: provider.defaultEnabled, ProviderIntegrationPreferences.globalKey(provider))
        _projectEnabled = AppStorage(wrappedValue: true, ProviderIntegrationPreferences.projectKey(provider, projectID: projectID))
    }

    private var executable: URL? { integrations.executablePaths[provider] }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("\(provider.name) · \(status)", isOn: $projectEnabled)
                .disabled(!globallyEnabled)
                .accessibilityIdentifier("project-provider-\(provider.rawValue)-enabled")
            Spacer(minLength: 0)
            if executable != nil {
                Button("Launch") {
                    launch()
                    if provider == .codex {
                        Task { await integrations.refreshUsage() }
                    }
                }
                    .disabled(!globallyEnabled || !projectEnabled)
                    .accessibilityIdentifier("project-provider-\(provider.rawValue)-launch")
            } else {
                Link("Get CLI", destination: provider.setupURL)
                    .workspaceFont(.caption)
            }
        }
        .workspaceFont(.callout)
        if globallyEnabled && projectEnabled {
            Text("Usage: enter \(provider.usageCommand) in the CLI. Sign-in: \(provider.signInStatus).")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        } else if !globallyEnabled {
            Text("Enable this provider in Settings to use it here.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        }
    }

    private var status: String {
        guard globallyEnabled else { return "disabled in Settings" }
        return executable == nil ? "CLI not found" : "available"
    }
}
