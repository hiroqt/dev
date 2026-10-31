import Foundation
import Observation

@MainActor
@Observable
final class ProviderIntegrationsStore {
    private(set) var executablePaths: [CodingProvider: URL] = [:]
    private(set) var codexSignInState: ProviderSignInState = .unknown
    private(set) var isRefreshing = false
    private(set) var isRefreshingUsage = false
    private(set) var usageSnapshots: [CodingProvider: ProviderUsageSnapshot] = [:]
    private var refreshUsageRequestedAgain = false
    private let detectExecutables: @Sendable () -> [CodingProvider: URL]
    private let checkCodexSignIn: @Sendable (URL) -> Bool
    private let readCodexUsage: @Sendable (URL) -> ProviderUsageSnapshot?
    private let readAntigravityUsage: @Sendable (URL) -> ProviderUsageSnapshot?

    init(
        detectExecutables: @escaping @Sendable () -> [CodingProvider: URL] = ProviderCLIResolver.currentExecutablePaths,
        checkCodexSignIn: @escaping @Sendable (URL) -> Bool = ProviderCLIResolver.codexIsSignedIn,
        readCodexUsage: @escaping @Sendable (URL) -> ProviderUsageSnapshot? = CodexAppServerUsageCLI.read,
        readAntigravityUsage: @escaping @Sendable (URL) -> ProviderUsageSnapshot? = AntigravityUsageCLI.read
    ) {
        self.detectExecutables = detectExecutables
        self.checkCodexSignIn = checkCodexSignIn
        self.readCodexUsage = readCodexUsage
        self.readAntigravityUsage = readAntigravityUsage
    }

    func refreshAvailability() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let detect = detectExecutables
        executablePaths = await Task.detached(priority: .utility, operation: detect).value
        isRefreshing = false
        if executablePaths[.codex] == nil { codexSignInState = .unknown }
    }

    func refreshCodexSignIn() async {
        guard let executable = executablePaths[.codex] else {
            codexSignInState = .unknown
            return
        }
        codexSignInState = .checking
        let check = checkCodexSignIn
        let signedIn = await Task.detached(priority: .utility) { check(executable) }.value
        codexSignInState = signedIn ? .connected : .unknown
    }

    func refreshUsage() async {
        if isRefreshingUsage {
            refreshUsageRequestedAgain = true
            return
        }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        repeat {
            refreshUsageRequestedAgain = false
            await readUsageSnapshots()
        } while refreshUsageRequestedAgain
    }

    private func readUsageSnapshots() async {
        let codexPath = executablePaths[.codex]
        let antigravityPath = executablePaths[.antigravity]
        let codexEnabled = ProviderIntegrationPreferences.isEnabled(.codex)
        let antigravityEnabled = ProviderIntegrationPreferences.isEnabled(.antigravity)

        if !codexEnabled || codexPath == nil { usageSnapshots[.codex] = nil }
        if !antigravityEnabled || antigravityPath == nil { usageSnapshots[.antigravity] = nil }

        let readCodex = readCodexUsage
        let readAntigravity = readAntigravityUsage
        let codexTask = codexEnabled ? codexPath.map { executable in
            Task.detached(priority: .utility) { readCodex(executable) }
        } : nil
        let antigravityTask = antigravityEnabled ? antigravityPath.map { executable in
            Task.detached(priority: .utility) { readAntigravity(executable) }
        } : nil

        if let codexTask {
            usageSnapshots[.codex] = await codexTask.value
        }
        if let antigravityTask {
            usageSnapshots[.antigravity] = await antigravityTask.value
        }
    }
}
