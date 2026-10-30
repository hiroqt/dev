import Foundation
import Observation

enum Destination: Hashable {
    case allProjects
    case activity
    case settings
    case project(Int64, ProjectPage)
    case localProject(UUID, LocalProjectPage)
}

enum RecentProjectReference: Hashable, Identifiable {
    case github(Int64)
    case local(UUID)

    var id: String {
        switch self {
        case let .github(id): "github:\(id)"
        case let .local(id): "local:\(id.uuidString)"
        }
    }
}

struct OverviewPullRequest: Identifiable, Sendable {
    let repository: GitHubRepository
    let request: GitHubPullRequest
    var id: String { "\(repository.id):\(request.number)" }
}

enum LocalProjectPage: String, CaseIterable, Hashable, Identifiable {
    case overview = "Overview"
    case files = "Files"
    var id: String { rawValue }
    var symbol: String { self == .overview ? "square.grid.2x2" : "doc.text" }
}

struct LocalProject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var bookmark: Data

    static func adding(_ url: URL) throws -> LocalProject {
        LocalProject(id: UUID(), name: url.lastPathComponent, bookmark: try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    var url: URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}

struct LocalProjectTextFile {
    let contents: String
    let isMarkdown: Bool
    let language: String

    static func read(_ fileURL: URL, inside rootURL: URL) throws -> LocalProjectTextFile {
        let startedAccess = rootURL.startAccessingSecurityScopedResource()
        defer { if startedAccess { rootURL.stopAccessingSecurityScopedResource() } }

        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let projectPrefix = rootPath == "/" ? "/" : rootPath + "/"
        guard resolvedFile.path.hasPrefix(projectPrefix) else { throw LocalProjectFileError.outsideProject }

        let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink == false, values.isRegularFile == true else { throw LocalProjectFileError.notRegularFile }
        let maximumBytes = 2_000_000
        guard let size = values.fileSize, size <= maximumBytes else { throw LocalProjectFileError.tooLarge }

        let handle = try FileHandle(forReadingFrom: resolvedFile)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw LocalProjectFileError.tooLarge }
        guard !data.contains(0), let contents = String(data: data, encoding: .utf8) else { throw LocalProjectFileError.notText }
        let ext = fileURL.pathExtension.lowercased()
        let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
        return LocalProjectTextFile(contents: contents, isMarkdown: markdownExtensions.contains(ext), language: ext.isEmpty ? "Text" : ext.uppercased())
    }
}

private enum LocalProjectFileError: LocalizedError {
    case outsideProject
    case notRegularFile
    case tooLarge
    case notText

    var errorDescription: String? {
        switch self {
        case .outsideProject: "This file is outside the selected project folder."
        case .notRegularFile: "Symbolic links and non-file items can’t be previewed."
        case .tooLarge: "Files larger than 2 MB can’t be previewed here."
        case .notText: "This file isn’t UTF-8 text and can’t be previewed here."
        }
    }
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
    private(set) var localProjects: [LocalProject] = (try? JSONDecoder().decode([LocalProject].self, from: UserDefaults.standard.data(forKey: "localProjects") ?? Data())) ?? []
    private(set) var sidebarProjectOrder = UserDefaults.standard.stringArray(forKey: "sidebarProjectOrder") ?? []
    private(set) var pinnedSidebarProjects = Set(UserDefaults.standard.stringArray(forKey: "pinnedSidebarProjects") ?? [])
    private(set) var sidebarProjectNames = UserDefaults.standard.dictionary(forKey: "sidebarProjectNames") as? [String: String] ?? [:]
    private(set) var sidebarProjectColors = UserDefaults.standard.dictionary(forKey: "sidebarProjectColors") as? [String: String] ?? [:]
    private(set) var sidebarProjectIcons = UserDefaults.standard.dictionary(forKey: "sidebarProjectIcons") as? [String: String] ?? [:]
    private(set) var localProjectError: String?
    private(set) var recentProjectKeys = UserDefaults.standard.stringArray(forKey: "recentProjectKeys") ?? []
    private(set) var overviewPullRequests: [OverviewPullRequest] = []
    private(set) var overviewPullRequestsLoading = false
    private(set) var overviewPullRequestsError: String?
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
    private(set) var openPullRequestCounts: [Int64: Int] = [:]
    private var pullRequestCountRefreshRequestID = UUID()
    private(set) var selectedPullRequestNumber: Int?
    private(set) var selectedPullRequestFiles: [GitHubPullRequestFile] = []
    private(set) var selectedPullRequestComments: [GitHubPullRequestComment] = []
    private(set) var selectedPullRequestReviewComments: [GitHubPullRequestComment] = []
    private(set) var selectedPullRequestReviews: [GitHubPullRequestReview] = []
    private(set) var selectedPullRequestCommits: [GitHubCommit] = []
    private(set) var selectedPullRequestChecks: [GitHubCheckRun] = []
    private(set) var selectedPullRequestChecksError: String?
    private(set) var pullRequestDetailLoading = false
    private(set) var pullRequestActionInProgress = false
    private(set) var pullRequestActionMessage: String?
    private(set) var pullRequestDetailError: String?
    private(set) var projectHistoryLoading = false
    private(set) var projectHistoryError: String?
    private var historyRepositoryID: Int64?
    private var branchCommitRequestID = UUID()
    private var overviewPullRequestRequestID = UUID()
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

    @discardableResult
    func addLocalProject(at url: URL) -> UUID? {
        localProjectError = nil
        if let existing = localProjects.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) { return existing.id }
        do {
            let project = try LocalProject.adding(url)
            localProjects.append(project)
            UserDefaults.standard.set(try JSONEncoder().encode(localProjects), forKey: "localProjects")
            return project.id
        } catch {
            localProjectError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createLocalProject(named name: String, in parent: URL) -> UUID? {
        localProjectError = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\\") else {
            localProjectError = "Enter a folder name without path separators."
            return nil
        }
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            localProjectError = "A folder or file with that name already exists. Choose another name."
            return nil
        }
        let startedAccess = parent.startAccessingSecurityScopedResource()
        defer { if startedAccess { parent.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            return addLocalProject(at: folder)
        } catch {
            localProjectError = error.localizedDescription
            return nil
        }
    }

    func removeLocalProject(_ project: LocalProject) {
        localProjects.removeAll { $0.id == project.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(localProjects), forKey: "localProjects")
        removeSidebarProject("local:\(project.id.uuidString)")
    }

    func removeRepositoryFromSidebar(_ repository: GitHubRepository) {
        clonedRepositoryPaths.removeValue(forKey: repository.id)
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: clonedRepositoryPaths.map { (String($0.key), $0.value) }), forKey: "clonedRepositoryPaths")
        removeSidebarProject("github:\(repository.id)")
    }

    func removeSidebarProject(_ key: String) {
        sidebarProjectOrder.removeAll { $0 == key }
        pinnedSidebarProjects.remove(key)
        sidebarProjectNames.removeValue(forKey: key)
        sidebarProjectColors.removeValue(forKey: key)
        sidebarProjectIcons.removeValue(forKey: key)
        UserDefaults.standard.set(sidebarProjectOrder, forKey: "sidebarProjectOrder")
        UserDefaults.standard.set(Array(pinnedSidebarProjects), forKey: "pinnedSidebarProjects")
        UserDefaults.standard.set(sidebarProjectNames, forKey: "sidebarProjectNames")
        UserDefaults.standard.set(sidebarProjectColors, forKey: "sidebarProjectColors")
        UserDefaults.standard.set(sidebarProjectIcons, forKey: "sidebarProjectIcons")
        recentProjectKeys.removeAll { $0 == key }
        UserDefaults.standard.set(recentProjectKeys, forKey: "recentProjectKeys")
    }

    func setSidebarProjectAppearance(_ key: String, name: String, color: String, icon: String) {
        sidebarProjectNames[key] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sidebarProjectColors[key] = color
        sidebarProjectIcons[key] = icon
        UserDefaults.standard.set(sidebarProjectNames, forKey: "sidebarProjectNames")
        UserDefaults.standard.set(sidebarProjectColors, forKey: "sidebarProjectColors")
        UserDefaults.standard.set(sidebarProjectIcons, forKey: "sidebarProjectIcons")
    }

    func toggleSidebarPin(_ key: String) {
        if !pinnedSidebarProjects.insert(key).inserted { pinnedSidebarProjects.remove(key) }
        UserDefaults.standard.set(Array(pinnedSidebarProjects), forKey: "pinnedSidebarProjects")
    }

    func moveSidebarProject(_ source: String, before target: String) {
        guard source != target, source.split(separator: ":").first == target.split(separator: ":").first else { return }
        let existingKeys = clonedRepositories.map { "github:\($0.id)" } + localProjects.map { "local:\($0.id.uuidString)" }
        var order = existingKeys.sorted { lhs, rhs in
            (sidebarProjectOrder.firstIndex(of: lhs) ?? .max) < (sidebarProjectOrder.firstIndex(of: rhs) ?? .max)
        }
        guard let sourceIndex = order.firstIndex(of: source), let targetIndex = order.firstIndex(of: target) else { return }
        order.remove(at: sourceIndex)
        order.insert(source, at: order.firstIndex(of: target) ?? targetIndex)
        sidebarProjectOrder = order
        UserDefaults.standard.set(sidebarProjectOrder, forKey: "sidebarProjectOrder")
    }

    func orderedSidebarProjects<T>(_ projects: [T], key: (T) -> String) -> [T] {
        projects.enumerated().sorted { lhs, rhs in
            let leftKey = key(lhs.element)
            let rightKey = key(rhs.element)
            let leftPinned = pinnedSidebarProjects.contains(leftKey)
            let rightPinned = pinnedSidebarProjects.contains(rightKey)
            if leftPinned != rightPinned { return leftPinned }
            let leftRank = sidebarProjectOrder.firstIndex(of: leftKey) ?? .max
            let rightRank = sidebarProjectOrder.firstIndex(of: rightKey) ?? .max
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
    }

    var recentProjects: [RecentProjectReference] {
        recentProjectKeys.compactMap { key in
            if key.hasPrefix("github:"), let id = Int64(key.dropFirst("github:".count)) { return .github(id) }
            if key.hasPrefix("local:"), let id = UUID(uuidString: String(key.dropFirst("local:".count))) { return .local(id) }
            return nil
        }.filter { reference in
            switch reference {
            case let .github(id): repositories.contains { $0.id == id && isCloned($0) }
            case let .local(id): localProjects.contains { $0.id == id }
            }
        }
    }

    func recordRecentProject(for destination: Destination?) {
        let key: String
        switch destination {
        case let .project(id, _): key = "github:\(id)"
        case let .localProject(id, _): key = "local:\(id.uuidString)"
        default: return
        }
        recentProjectKeys.removeAll { $0 == key }
        recentProjectKeys.insert(key, at: 0)
        recentProjectKeys = Array(recentProjectKeys.prefix(20))
        UserDefaults.standard.set(recentProjectKeys, forKey: "recentProjectKeys")
    }

    func loadOverviewPullRequests() async {
        guard !repositories.isEmpty else {
            overviewPullRequests = []
            overviewPullRequestsError = nil
            return
        }
        let requestID = UUID()
        overviewPullRequestRequestID = requestID
        overviewPullRequestsLoading = true
        defer { if overviewPullRequestRequestID == requestID { overviewPullRequestsLoading = false } }
        do {
            let token = try await currentAccessToken()
            let provider = historyAPI
            let sources = repositories
            var next = 0
            var partial = false
            var requests: [OverviewPullRequest] = []
            var failedRepositoryIDs = Set<Int64>()
            await withTaskGroup(of: (GitHubRepository, [GitHubPullRequest]?).self) { group in
                for repository in sources.prefix(5) {
                    group.addTask {
                        (repository, try? await provider.recentPullRequests(repository: repository, limit: 8, accessToken: token))
                    }
                }
                next = min(5, sources.count)
                while let (repository, result) = await group.next() {
                    guard overviewPullRequestRequestID == requestID else { group.cancelAll(); return }
                    if let result {
                        requests.append(contentsOf: result.map { OverviewPullRequest(repository: repository, request: $0) })
                    } else {
                        partial = true
                        failedRepositoryIDs.insert(repository.id)
                    }
                    if next < sources.count {
                        let repository = sources[next]
                        next += 1
                        group.addTask {
                            (repository, try? await provider.recentPullRequests(repository: repository, limit: 8, accessToken: token))
                        }
                    }
                }
            }
            guard overviewPullRequestRequestID == requestID else { return }
            requests += overviewPullRequests.filter { failedRepositoryIDs.contains($0.repository.id) }
            overviewPullRequests = requests.sorted { $0.request.updatedAt > $1.request.updatedAt }.prefix(8).map { $0 }
            overviewPullRequestsError = partial ? "Some repositories could not be refreshed." : nil
        } catch {
            guard overviewPullRequestRequestID == requestID else { return }
            overviewPullRequestsError = overviewPullRequests.isEmpty ? "Connect to GitHub to load recent pull requests." : "Recent pull requests may be out of date."
        }
    }

    func loadAllOverviewPullRequests() async -> (requests: [OverviewPullRequest], error: String?) {
        guard !repositories.isEmpty else { return ([], nil) }
        guard let token = try? await currentAccessToken() else {
            return (overviewPullRequests, "Connect to GitHub to load pull requests from every repository.")
        }
        let provider = historyAPI
        let sources = repositories
        var next = 0
        var requests: [OverviewPullRequest] = []
        var failedRepositoryIDs = Set<Int64>()
        await withTaskGroup(of: (GitHubRepository, [GitHubPullRequest]?).self) { group in
            for repository in sources.prefix(5) {
                group.addTask {
                    (repository, try? await provider.pullRequests(repository: repository, accessToken: token))
                }
            }
            next = min(5, sources.count)
            while let (repository, result) = await group.next() {
                if let result {
                    requests.append(contentsOf: result.map { OverviewPullRequest(repository: repository, request: $0) })
                } else {
                    failedRepositoryIDs.insert(repository.id)
                }
                if next < sources.count {
                    let repository = sources[next]
                    next += 1
                    group.addTask {
                        (repository, try? await provider.pullRequests(repository: repository, accessToken: token))
                    }
                }
            }
        }
        requests += overviewPullRequests.filter { failedRepositoryIDs.contains($0.repository.id) }
        requests.sort { $0.request.updatedAt > $1.request.updatedAt }
        return (requests, failedRepositoryIDs.isEmpty ? nil : "Some repositories could not be refreshed; their last available pull requests are included.")
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

    func loadProjectHistory(repository: GitHubRepository, forceRefresh: Bool = false) async {
        guard historyRepositoryID != repository.id || (!projectHistoryLoading && (forceRefresh || projectHistoryError != nil)) else { return }
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
        selectedPullRequestCommits = []
        selectedPullRequestChecks = []
        selectedPullRequestChecksError = nil
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
            openPullRequestCounts[repository.id] = result.1.filter { $0.state == "open" }.count
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

    func refreshOpenPullRequestCounts(for repositories: [GitHubRepository], accessToken: String) async {
        guard (try? tokenStore.load())?.accessToken == accessToken else { return }
        let requestID = UUID()
        pullRequestCountRefreshRequestID = requestID
        let provider = historyAPI
        let concurrencyLimit = 5
        await withTaskGroup(of: (Int64, Int?).self) { group in
            var nextRepository = 0
            for repository in repositories.prefix(concurrencyLimit) {
                group.addTask {
                    do {
                        let open = try await provider.openPullRequests(repository: repository, accessToken: accessToken)
                        return (repository.id, open.count)
                    } catch {
                        return (repository.id, nil)
                    }
                }
                nextRepository += 1
            }
            while let (repositoryID, count) = await group.next() {
                guard pullRequestCountRefreshRequestID == requestID else { group.cancelAll(); return }
                if let count { openPullRequestCounts[repositoryID] = count }
                else { openPullRequestCounts[repositoryID] = nil }
                if nextRepository < repositories.count {
                    let repository = repositories[nextRepository]
                    nextRepository += 1
                    group.addTask {
                        do {
                            let open = try await provider.openPullRequests(repository: repository, accessToken: accessToken)
                            return (repository.id, open.count)
                        } catch {
                            return (repository.id, nil)
                        }
                    }
                }
            }
        }
    }

    func createPullRequest(repository: GitHubRepository, head: String, base: String, title: String, body: String) async throws -> GitHubPullRequest {
        guard !pullRequestActionInProgress else { throw GitHubBackendError.invalidPullRequestAction }
        pullRequestActionInProgress = true
        pullRequestActionMessage = nil
        defer { pullRequestActionInProgress = false }
        let token = try await currentAccessToken()
        let request = try await pullRequestAPI.createPullRequest(repository: repository, head: head, base: base, title: title, body: body, accessToken: token)
        if !projectPullRequests.contains(where: { $0.number == request.number }) {
            projectPullRequests.insert(request, at: 0)
        }
        openPullRequestCounts[repository.id] = projectPullRequests.filter { $0.state == "open" }.count
        pullRequestActionMessage = "Pull request #\(request.number) created."
        pullRequestCountRefreshRequestID = UUID()
        Task { await refreshOpenPullRequestCounts(for: repositories, accessToken: token) }
        return request
    }

    func loadPullRequestDetail(_ number: Int, repository: GitHubRepository) async {
        selectedPullRequestNumber = number
        selectedPullRequestFiles = []
        selectedPullRequestComments = []
        selectedPullRequestReviewComments = []
        selectedPullRequestReviews = []
        selectedPullRequestCommits = []
        selectedPullRequestChecks = []
        selectedPullRequestChecksError = nil
        pullRequestDetailError = nil
        pullRequestDetailLoading = true
        defer { if selectedPullRequestNumber == number { pullRequestDetailLoading = false } }
        do {
            let token = try await currentAccessToken()
            async let files = pullRequestAPI.pullRequestFiles(repository: repository, number: number, accessToken: token)
            async let comments = pullRequestAPI.pullRequestComments(repository: repository, number: number, accessToken: token)
            async let reviewComments = pullRequestAPI.pullRequestReviewComments(repository: repository, number: number, accessToken: token)
            async let reviews = pullRequestAPI.pullRequestReviews(repository: repository, number: number, accessToken: token)
            async let commits = pullRequestAPI.pullRequestCommits(repository: repository, number: number, accessToken: token)
            let headSHA = projectPullRequests.first(where: { $0.number == number })?.head?.sha
            async let checks: (runs: [GitHubCheckRun], error: String?) = {
                guard let sha = headSHA else {
                    return ([], nil)
                }
                do { return (try await pullRequestAPI.pullRequestChecks(repository: repository, headSHA: sha, accessToken: token), nil) }
                catch { return ([], error.localizedDescription) }
            }()
            let result = try await (files, comments, reviewComments, reviews, commits, checks)
            try Task.checkCancellation()
            guard selectedPullRequestNumber == number else { return }
            selectedPullRequestFiles = result.0
            selectedPullRequestComments = result.1
            selectedPullRequestReviewComments = result.2
            selectedPullRequestReviews = result.3
            selectedPullRequestCommits = result.4
            selectedPullRequestChecks = result.5.runs
            selectedPullRequestChecksError = result.5.error
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

    func mergePullRequest(repository: GitHubRepository, number: Int, commitTitle: String, commitMessage: String) async {
        await performPullRequestAction(repository: repository, number: number) {
            let result = try await self.pullRequestAPI.merge(repository: repository, number: number, commitTitle: commitTitle, commitMessage: commitMessage, accessToken: $0)
            guard result.merged else { throw GitHubBackendError.invalidResponse }
            self.pullRequestActionMessage = "Pull request merged."
            if let index = self.projectPullRequests.firstIndex(where: { $0.number == number }) {
                self.projectPullRequests[index].state = "closed"
                self.projectPullRequests[index].mergedAt = ISO8601DateFormatter().string(from: Date())
            }
            if let count = self.openPullRequestCounts[repository.id] {
                self.openPullRequestCounts[repository.id] = max(0, count - 1)
            }
            do {
                self.projectPullRequests = try await self.historyAPI.pullRequests(repository: repository, accessToken: $0)
                self.openPullRequestCounts[repository.id] = self.projectPullRequests.filter { $0.state == "open" }.count
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
            pullRequestCountRefreshRequestID = UUID()
            openPullRequestCounts = [:]
            repositories = []
            signedInUsername = nil
            contributionActivityRequestID = UUID()
            contributionActivity = nil
            contributionActivityError = nil
            contributionActivityLoading = false
            overviewPullRequestRequestID = UUID()
            overviewPullRequests = []
            overviewPullRequestsError = nil
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
            Task { await refreshOpenPullRequestCounts(for: fetched, accessToken: token.accessToken) }
            Task { await loadOverviewPullRequests() }
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
