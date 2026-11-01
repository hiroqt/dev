import SwiftUI

struct ProviderSettingsView: View {
    @Bindable var integrations: ProviderIntegrationsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider apps and CLIs are separate sign-ins. dev launches them locally and does not send project files or prompts.")
                .foregroundStyle(.secondary)
            ForEach(CodingProvider.allCases) { provider in
                ProviderSettingsCard(provider: provider, integrations: integrations)
            }
        }
        .task { await integrations.refreshAvailability() }
    }
}

private struct ProviderSettingsCard: View {
    let provider: CodingProvider
    @Bindable var integrations: ProviderIntegrationsStore
    @AppStorage private var isEnabled: Bool
    @AppStorage private var plan: String
    @AppStorage private var otherPlan: String

    init(provider: CodingProvider, integrations: ProviderIntegrationsStore) {
        self.provider = provider
        self.integrations = integrations
        _isEnabled = AppStorage(wrappedValue: provider.defaultEnabled, ProviderIntegrationPreferences.globalKey(provider))
        _plan = AppStorage(wrappedValue: "Not selected", ProviderIntegrationPreferences.planKey(provider))
        _otherPlan = AppStorage(wrappedValue: "", "providerIntegration.\(provider.rawValue).otherPlan")
    }

    private var installed: Bool { integrations.executablePaths[provider] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enable \(provider.name)", isOn: $isEnabled)
                .accessibilityIdentifier("provider-global-\(provider.rawValue)-enabled")
                .onChange(of: isEnabled) { _, enabled in
                    guard provider == .antigravity || provider == .codex else { return }
                    Task {
                        if enabled { await integrations.refreshAvailability() }
                        await integrations.refreshUsage()
                    }
                }
            HStack {
                Text("CLI")
                Spacer()
                Text(integrations.isRefreshing ? "Checking…" : installed ? "Available" : "Not found")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Plan (optional)")
                Spacer()
                Picker("Plan", selection: $plan) {
                    ForEach(provider.plans, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            if plan == "Other" {
                TextField("Plan name", text: $otherPlan)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Plan is a label only; dev does not estimate limits from it.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
            if provider == .codex {
                HStack {
                    Text("Sign-in")
                    Spacer()
                    Text(signInLabel).foregroundStyle(.secondary)
                    Button("Check") { Task { await integrations.refreshCodexSignIn() } }
                        .disabled(!installed || integrations.codexSignInState == .checking)
                        .help("Runs Codex's login status command. Workload identity may consume a single-use token.")
                }
            } else {
                LabeledContent("Sign-in", value: "Unknown; check in CLI")
            }
            if provider == .codex {
                let snapshot = integrations.usageSnapshots[.codex]
                LabeledContent("Detected Codex plan", value: snapshot?.planType?.capitalized ?? "Unavailable")
                LabeledContent("5-hour / weekly usage in dev", value: snapshot?.groups.isEmpty == false ? "Available" : "Unavailable")
                Button("Refresh Codex usage") { Task { await integrations.refreshUsage() } }
                    .disabled(!installed || !isEnabled || integrations.isRefreshingUsage)
                Text("dev reads Codex's structured local app-server usage response after launch and every five minutes. It does not read the terminal screen or store Codex credentials.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            } else {
                LabeledContent("5-hour / weekly usage in dev", value: "Unavailable")
                Text("Open the CLI and enter \(provider.usageCommand) to check provider-reported usage. dev does not parse interactive terminal output.")
                    .workspaceFont(.caption).foregroundStyle(.secondary)
            }
            Link("Setup and CLI documentation", destination: provider.setupURL)
                .workspaceFont(.caption)
        }
        .padding(12)
        .workspaceSurfaceBackground(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var signInLabel: String {
        switch integrations.codexSignInState {
        case .unknown: "Unknown"
        case .checking: "Checking…"
        case .connected: "Connected"
        }
    }
}
