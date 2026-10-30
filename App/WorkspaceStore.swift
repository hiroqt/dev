import Foundation
import Observation

enum Destination: Hashable {
    case allProjects
    case activity
    case settings
    case project(Int64, ProjectPage)
}

enum ProjectPage: String, CaseIterable, Hashable, Identifiable {
    case overview = "Overview"
    case branches = "Branches"
    case commits = "Commits"
    case pullRequests = "Pull Requests"
    case issues = "Issues"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .branches: "point.3.connected.trianglepath.dotted"
        case .commits: "clock.arrow.circlepath"
        case .pullRequests: "arrow.triangle.pull"
        case .issues: "circle.dashed"
        }
    }
}

enum GitHubConnectionState: Equatable {
    case checking
    case needsConfiguration
    case signedOut
    case authorizing
    case awaitingAuthorization
    case loading
    case connected
    case stale(String)
    case failed(String)
}

@MainActor
@Observable
final class WorkspaceStore {
    private let api: any GitHubRepositoryProviding
    private let deviceFlow: any GitHubDeviceAuthorizing
    private let tokenStore: any GitHubTokenStoring
    private let clientID: String?

    private var signInTask: Task<Void, Never>?
    private(set) var repositories: [GitHubRepository] = []
    private(set) var connectionState: GitHubConnectionState = .checking
    private(set) var authorization: GitHubDeviceAuthorization?
    var searchText = ""

    init(
        clientID: String? = GitHubConfiguration.clientID,
        api: any GitHubRepositoryProviding = GitHubAPIClient(),
        deviceFlow: any GitHubDeviceAuthorizing = GitHubDeviceFlow(),
        tokenStore: any GitHubTokenStoring = KeychainGitHubTokenStore()
    ) {
        self.clientID = clientID
        self.api = api
        self.deviceFlow = deviceFlow
        self.tokenStore = tokenStore
    }

    var filteredRepositories: [GitHubRepository] {
        guard !searchText.isEmpty else { return repositories }
        return repositories.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
                || ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    func repository(id: Int64) -> GitHubRepository? {
        repositories.first { $0.id == id }
    }

    func restoreSession() async {
        do {
            guard let token = try tokenStore.load() else {
                connectionState = clientID == nil ? .needsConfiguration : .signedOut
                return
            }
            try await fetchRepositories(using: token)
        } catch {
            setFailure(error)
        }
    }

    func startSignIn() {
        guard clientID != nil else {
            connectionState = .needsConfiguration
            return
        }
        signInTask?.cancel()
        signInTask = Task { await performSignIn() }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        authorization = nil
        connectionState = clientID == nil ? .needsConfiguration : .signedOut
    }

    func refresh() async {
        do {
            guard let token = try tokenStore.load() else {
                connectionState = clientID == nil ? .needsConfiguration : .signedOut
                return
            }
            try await fetchRepositories(using: token)
        } catch {
            setFailure(error)
        }
    }

    func signOut() {
        do {
            try tokenStore.delete()
            repositories = []
            authorization = nil
            connectionState = clientID == nil ? .needsConfiguration : .signedOut
        } catch {
            setFailure(error)
        }
    }

    private func performSignIn() async {
        guard let clientID else { connectionState = .needsConfiguration; return }
        connectionState = .authorizing
        do {
            let authorization = try await deviceFlow.requestCode(clientID: clientID)
            self.authorization = authorization
            connectionState = .awaitingAuthorization
            let token = try await deviceFlow.pollForToken(clientID: clientID, authorization: authorization)
            try Task.checkCancellation()
            try tokenStore.save(token)
            self.authorization = nil
            try await fetchRepositories(using: token)
        } catch is CancellationError {
            authorization = nil
            connectionState = .signedOut
        } catch {
            authorization = nil
            setFailure(error)
        }
    }

    private func fetchRepositories(using storedToken: GitHubToken) async throws {
        var token = storedToken
        if let expiresAt = token.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
            guard let clientID else { throw GitHubBackendError.clientNotConfigured }
            token = try await deviceFlow.refresh(clientID: clientID, token: token)
            try tokenStore.save(token)
        }
        connectionState = .loading
        do {
            let fetched = try await api.repositories(accessToken: token.accessToken)
            repositories = fetched
            connectionState = .connected
        } catch {
            if repositories.isEmpty {
                throw error
            }
            connectionState = .stale(error.localizedDescription)
        }
    }

    private func setFailure(_ error: Error) {
        connectionState = repositories.isEmpty
            ? .failed(error.localizedDescription)
            : .stale(error.localizedDescription)
    }
}
