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
    private let historyAPI: any GitHubProjectHistoryProviding
    private let pullRequestAPI: any GitHubPullRequestManaging
    private let contributionAPI: any GitHubContributionProviding
    private let viewerAPI: any GitHubViewerProviding
    private let deviceFlow: any GitHubDeviceAuthorizing
    private let tokenStore: any GitHubTokenStoring
    private let clientID: String?
    private let cloner = LocalGitCloner()

    private var signInTask: Task<Void, Never>?
    private(set) var repositories: [GitHubRepository] = []
    private(set) var signedInUsername: String?
    private(set) var clonedRepositoryPaths: [Int64: String] = {
        let saved = UserDefaults.standard.dictionary(forKey: "clonedRepositoryPaths") as? [String: String] ?? [:]
        return saved.reduce(into: [:]) { paths, entry in
            if let id = Int64(entry.key) { paths[id] = entry.value }
        }
    }()
    private(set) var cloningRepositoryIDs: Set<Int64> = []
    private(set) var cloneError: String?
    private(set) var projectBranches: [GitHubBranch] = []
    private(set) var projectCommits: [GitHubCommit] = []
    private(set) var selectedProjectBranch: String?
    private(set) var selectedProjectCommitSHA: String?
    private(set) var projectPullRequests: [GitHubPullRequest] = []
    private(set) var selectedPullRequestNumber: Int?
    private(set) var selectedPullRequestFiles: [GitHubPullRequestFile] = []
    private(set) var selectedPullRequestComments: [GitHubPullRequestComment] = []
    private(set) var selectedPullRequestReviewComments: [GitHubPullRequestComment] = []
    private(set) var selectedPullRequestReviews: [GitHubPullRequestReview] = []
    private(set) var pullRequestDetailLoading = false
    private(set) var pullRequestActionInProgress = false
    private(set) var pullRequestActionMessage: String?
    private(set) var pullRequestDetailError: String?
    private(set) var projectHistoryLoading = false
    private(set) var projectHistoryError: String?
    private var historyRepositoryID: Int64?
    private var branchCommitRequestID = UUID()
    private(set) var contributionActivity: GitHubContributionSummary?
    private(set) var contributionActivityYear: Int?
    private(set) var contributionActivityLoading = false
    private(set) var contributionActivityError: String?
    private var contributionActivityRequestID = UUID()
    private(set) var connectionState: GitHubConnectionState = .checking
    private(set) var authorization: GitHubDeviceAuthorization?
    var searchText = ""

    init(
        clientID: String? = GitHubConfiguration.clientID,
        api: any GitHubRepositoryProviding = GitHubAPIClient(),
        historyAPI: any GitHubProjectHistoryProviding = GitHubAPIClient(),
        pullRequestAPI: any GitHubPullRequestManaging = GitHubAPIClient(),
        contributionAPI: any GitHubContributionProviding = GitHubAPIClient(),
        viewerAPI: any GitHubViewerProviding = GitHubAPIClient(),
        deviceFlow: any GitHubDeviceAuthorizing = GitHubDeviceFlow(),
        tokenStore: any GitHubTokenStoring = KeychainGitHubTokenStore()
    ) {
        self.clientID = clientID
        self.api = api
        self.historyAPI = historyAPI
        self.pullRequestAPI = pullRequestAPI
        self.contributionAPI = contributionAPI
        self.viewerAPI = viewerAPI
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

    var clonedRepositories: [GitHubRepository] {
        repositories.filter { isCloned($0) }
    }

    func isCloned(_ repository: GitHubRepository) -> Bool {
        guard let path = clonedRepositoryPaths[repository.id] else { return false }
        return FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appending(path: ".git").path)
    }

    func clone(_ repository: GitHubRepository, into parent: URL) async {
        guard !isCloned(repository), !cloningRepositoryIDs.contains(repository.id) else { return }
        cloneError = nil
        cloningRepositoryIDs.insert(repository.id)
        defer { cloningRepositoryIDs.remove(repository.id) }
        do {
            let destination = parent.appending(path: repository.name, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: destination.path) {
                rememberClone(try await cloner.addExistingClone(repository: repository, at: destination), for: repository)
                return
            }
            guard var token = try tokenStore.load() else { throw GitHubBackendError.unauthorized }
            if let expiresAt = token.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
                guard let clientID else { throw GitHubBackendError.clientNotConfigured }
                token = try await deviceFlow.refresh(clientID: clientID, token: token)
                try tokenStore.save(token)
            }
            let path = try await cloner.clone(repository: repository, parent: parent, accessToken: token.accessToken)
            rememberClone(path, for: repository)
        } catch {
            cloneError = error.localizedDescription
        }
    }

    func addExistingClone(_ repository: GitHubRepository, at folder: URL) async {
        guard !isCloned(repository), !cloningRepositoryIDs.contains(repository.id) else { return }
        cloneError = nil
        cloningRepositoryIDs.insert(repository.id)
        defer { cloningRepositoryIDs.remove(repository.id) }
        do {
            rememberClone(try await cloner.addExistingClone(repository: repository, at: folder), for: repository)
        } catch {
            cloneError = error.localizedDescription
        }
    }

    private func rememberClone(_ folder: URL, for repository: GitHubRepository) {
        clonedRepositoryPaths[repository.id] = folder.path
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: clonedRepositoryPaths.map { (String($0.key), $0.value) }), forKey: "clonedRepositoryPaths")
    }

    func loadProjectHistory(repository: GitHubRepository) async {
        guard historyRepositoryID != repository.id || (!projectHistoryLoading && projectHistoryError != nil) else { return }
        historyRepositoryID = repository.id
        projectHistoryLoading = true
        projectHistoryError = nil
        projectBranches = []
        projectCommits = []
        projectPullRequests = []
        selectedPullRequestNumber = nil
        selectedPullRequestFiles = []
        selectedPullRequestComments = []
        selectedPullRequestReviewComments = []
        selectedPullRequestReviews = []
        pullRequestActionMessage = nil
        pullRequestDetailError = nil
        selectedProjectBranch = nil
        selectedProjectCommitSHA = nil
        defer { if historyRepositoryID == repository.id { projectHistoryLoading = false } }
        do {
            guard var token = try tokenStore.load() else { throw GitHubBackendError.unauthorized }
            if let expiresAt = token.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
                guard let clientID else { throw GitHubBackendError.clientNotConfigured }
                token = try await deviceFlow.refresh(clientID: clientID, token: token)
                try tokenStore.save(token)
            }
            let accessToken = token.accessToken
            async let branches = historyAPI.branches(repository: repository, accessToken: accessToken)
            async let pullRequests = historyAPI.pullRequests(repository: repository, accessToken: accessToken)
            let result = try await (branches, pullRequests)
            try Task.checkCancellation()
            guard historyRepositoryID == repository.id else { return }
            projectBranches = result.0
            projectPullRequests = result.1
            let branch = result.0.first(where: { $0.name == repository.defaultBranch })?.name ?? result.0.first?.name
            if let branch { await selectProjectBranch(branch, repository: repository, accessToken: accessToken) }
        } catch is CancellationError {
            if historyRepositoryID == repository.id {
                historyRepositoryID = nil
                projectHistoryLoading = false
            }
        } catch {
            if historyRepositoryID == repository.id { projectHistoryError = error.localizedDescription }
        }
    }

    func selectProjectBranch(_ branch: String, repository: GitHubRepository, accessToken: String? = nil) async {
        guard selectedProjectBranch != branch else { return }
        let requestID = UUID()
        branchCommitRequestID = requestID
        selectedProjectBranch = branch
        selectedProjectCommitSHA = nil
        projectCommits = []
        do {
            var token: String
            if let accessToken {
                token = accessToken
            } else {
                guard var savedToken = try tokenStore.load() else { throw GitHubBackendError.unauthorized }
                if let expiresAt = savedToken.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
                    guard let clientID else { throw GitHubBackendError.clientNotConfigured }
                    savedToken = try await deviceFlow.refresh(clientID: clientID, token: savedToken)
                    try tokenStore.save(savedToken)
                }
                token = savedToken.accessToken
            }
            let commits = try await historyAPI.commits(repository: repository, branch: branch, accessToken: token)
            try Task.checkCancellation()
            guard branchCommitRequestID == requestID, historyRepositoryID == repository.id else { return }
            projectCommits = commits
            selectedProjectCommitSHA = commits.first?.sha
        } catch is CancellationError {
            return
        } catch {
            if branchCommitRequestID == requestID { projectHistoryError = error.localizedDescription }
        }
    }

    func selectProjectCommit(_ sha: String) { selectedProjectCommitSHA = sha }

    func loadPullRequestDetail(_ number: Int, repository: GitHubRepository) async {
        selectedPullRequestNumber = number
        selectedPullRequestFiles = []
        selectedPullRequestComments = []
        selectedPullRequestReviewComments = []
        selectedPullRequestReviews = []
        pullRequestDetailError = nil
        pullRequestDetailLoading = true
        defer { if selectedPullRequestNumber == number { pullRequestDetailLoading = false } }
        do {
            let token = try await currentAccessToken()
            async let files = pullRequestAPI.pullRequestFiles(repository: repository, number: number, accessToken: token)
            async let comments = pullRequestAPI.pullRequestComments(repository: repository, number: number, accessToken: token)
            async let reviewComments = pullRequestAPI.pullRequestReviewComments(repository: repository, number: number, accessToken: token)
            async let reviews = pullRequestAPI.pullRequestReviews(repository: repository, number: number, accessToken: token)
            let result = try await (files, comments, reviewComments, reviews)
            try Task.checkCancellation()
            guard selectedPullRequestNumber == number else { return }
            selectedPullRequestFiles = result.0
            selectedPullRequestComments = result.1
            selectedPullRequestReviewComments = result.2
            selectedPullRequestReviews = result.3
        } catch is CancellationError {
            return
        } catch {
            if selectedPullRequestNumber == number { pullRequestDetailError = error.localizedDescription }
        }
    }

    func postPullRequestComment(_ body: String, repository: GitHubRepository, number: Int) async {
        await performPullRequestAction(repository: repository, number: number) {
            try await self.pullRequestAPI.comment(on: repository, number: number, body: body, accessToken: $0)
            self.pullRequestActionMessage = "Comment posted."
        }
    }

    func submitPullRequestReview(_ body: String, event: String, repository: GitHubRepository, number: Int) async {
        await performPullRequestAction(repository: repository, number: number) {
            try await self.pullRequestAPI.submitReview(on: repository, number: number, body: body, event: event, accessToken: $0)
            self.pullRequestActionMessage = "Review submitted."
        }
    }

    func mergePullRequest(repository: GitHubRepository, number: Int) async {
        await performPullRequestAction(repository: repository, number: number) {
            let result = try await self.pullRequestAPI.merge(repository: repository, number: number, accessToken: $0)
            guard result.merged else { throw GitHubBackendError.invalidResponse }
            self.pullRequestActionMessage = "Pull request merged."
            do {
                self.projectPullRequests = try await self.historyAPI.pullRequests(repository: repository, accessToken: $0)
            } catch {
                self.pullRequestActionMessage = "Pull request merged, but the PR list could not refresh. Refresh project history to verify its state."
            }
        }
    }

    private func performPullRequestAction(repository: GitHubRepository, number: Int, action: (String) async throws -> Void) async {
        guard !pullRequestActionInProgress else { return }
        pullRequestActionInProgress = true
        pullRequestActionMessage = nil
        defer { pullRequestActionInProgress = false }
        do {
            let token = try await currentAccessToken()
            try await action(token)
            if selectedPullRequestNumber == number { await loadPullRequestDetail(number, repository: repository) }
            if pullRequestActionMessage == "Review submitted.", let year = contributionActivityYear {
                await loadContributionActivity(year: year)
            }
        } catch {
            pullRequestActionMessage = error.localizedDescription
        }
    }

    private func currentAccessToken() async throws -> String {
        guard var token = try tokenStore.load() else { throw GitHubBackendError.unauthorized }
        if let expiresAt = token.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
            guard let clientID else { throw GitHubBackendError.clientNotConfigured }
            token = try await deviceFlow.refresh(clientID: clientID, token: token)
            try tokenStore.save(token)
        }
        return token.accessToken
    }

    func loadContributionActivity(year: Int) async {
        contributionActivityYear = year
        let requestID = UUID()
        contributionActivityRequestID = requestID
        contributionActivity = nil
        contributionActivityError = nil
        contributionActivityLoading = true
        defer { if contributionActivityRequestID == requestID { contributionActivityLoading = false } }
        do {
            guard var token = try tokenStore.load() else { throw GitHubBackendError.unauthorized }
            if let expiresAt = token.expiresAt, expiresAt <= Date().addingTimeInterval(60) {
                guard let clientID else { throw GitHubBackendError.clientNotConfigured }
                token = try await deviceFlow.refresh(clientID: clientID, token: token)
                try tokenStore.save(token)
            }
            let activity = try await contributionAPI.contributions(year: year, accessToken: token.accessToken)
            try Task.checkCancellation()
            guard contributionActivityRequestID == requestID else { return }
            contributionActivity = activity
        } catch is CancellationError {
            return
        } catch {
            if contributionActivityRequestID == requestID { contributionActivityError = error.localizedDescription }
        }
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
            signedInUsername = nil
            contributionActivityRequestID = UUID()
            contributionActivity = nil
            contributionActivityError = nil
            contributionActivityLoading = false
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
            signedInUsername = try? await viewerAPI.viewerLogin(accessToken: token.accessToken)
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
