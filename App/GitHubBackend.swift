import Foundation

struct GitHubRepositoryOwner: Decodable, Hashable, Sendable {
    let login: String
}

struct GitHubRepository: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let fullName: String
    let owner: GitHubRepositoryOwner
    let summary: String?
    let isPrivate: Bool
    let visibility: String?
    let htmlURL: URL
    let defaultBranch: String?
    let pushedAt: String?

    var visibilityDescription: String { visibility ?? (isPrivate ? "Private" : "Public") }
    var safeGitHubURL: URL? {
        guard let components = URLComponents(url: htmlURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.path == "/\(fullName)", components.query == nil, components.fragment == nil else { return nil }
        return htmlURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, owner, visibility
        case fullName = "full_name"
        case summary = "description"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case defaultBranch = "default_branch"
        case pushedAt = "pushed_at"
    }
}

struct GitHubHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
    let headers: [String: String]
}

protocol GitHubHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse
}

struct URLSessionGitHubTransport: GitHubHTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubBackendError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key.lowercased()] = String(describing: value)
        }
        return GitHubHTTPResponse(statusCode: response.statusCode, data: data, headers: headers)
    }
}

enum GitHubBackendError: LocalizedError, Equatable {
    case clientNotConfigured
    case invalidResponse
    case invalidVerificationURL
    case deviceFlowDisabled
    case incorrectClientCredentials
    case unauthorized
    case forbidden
    case contributionAccessDenied
    case invalidPullRequestAction
    case rateLimited(Date?)
    case httpStatus(Int)
    case deviceCodeExpired
    case accessDenied
    case signInFailed
    case keychainStatus(Int32)

    var errorDescription: String? {
        switch self {
        case .clientNotConfigured: "Add the GitHub App client ID in Config/GitHub.xcconfig to enable sign-in."
        case .invalidResponse: "GitHub returned a response the app could not read."
        case .invalidVerificationURL: "GitHub returned an unsupported sign-in URL."
        case .deviceFlowDisabled: "Enable Device Flow in your GitHub App settings, then try again."
        case .incorrectClientCredentials: "The configured GitHub App client ID was rejected. Check Config/GitHub.xcconfig."
        case .unauthorized: "GitHub sign-in expired. Sign in again to refresh repository access."
        case .forbidden: "GitHub denied access. Check the app installation and organization approval. PR actions also require Pull requests: write permission in the GitHub App settings."
        case .contributionAccessDenied: "GitHub denied contribution access. Check the app's read permissions and contribution privacy settings."
        case .invalidPullRequestAction: "Enter a non-empty review message and check that the pull request number is valid."
        case .rateLimited(let retryAt):
            if let retryAt { "GitHub rate limit reached. Try again after \(retryAt.formatted(date: .omitted, time: .shortened))." }
            else { "GitHub rate limit reached. Try again shortly." }
        case .httpStatus: "GitHub could not complete the request. Try again later."
        case .deviceCodeExpired: "The GitHub sign-in code expired. Start sign-in again."
        case .accessDenied: "GitHub sign-in was cancelled."
        case .signInFailed: "GitHub sign-in could not be completed. Check the app configuration and try again."
        case .keychainStatus: "The GitHub credential could not be stored securely in Keychain."
        }
    }
}

protocol GitHubRepositoryProviding: Sendable {
    func repositories(accessToken: String) async throws -> [GitHubRepository]
}

struct GitHubBranch: Decodable, Identifiable, Sendable {
    let name: String
    let commit: CommitReference
    var id: String { name }

    struct CommitReference: Decodable, Sendable { let sha: String }
}

struct GitHubCommit: Decodable, Identifiable, Sendable {
    let sha: String
    let htmlURL: URL
    let commit: Commit
    var id: String { sha }

    struct Commit: Decodable, Sendable {
        let message: String
        let author: Author?
        struct Author: Decodable, Sendable { let date: String? }
    }

    enum CodingKeys: String, CodingKey { case sha, commit; case htmlURL = "html_url" }
}

struct GitHubPullRequest: Decodable, Identifiable, Sendable {
    let number: Int
    let title: String
    let state: String
    let htmlURL: URL
    let updatedAt: String
    let mergedAt: String?
    let body: String?
    let user: User?
    var id: Int { number }

    struct User: Decodable, Sendable { let login: String }
    enum CodingKeys: String, CodingKey {
        case number, title, state, body, user
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
    }
}

struct GitHubPullRequestFile: Decodable, Identifiable, Sendable {
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String?
    var id: String { filename }
}

struct GitHubPullRequestComment: Decodable, Identifiable, Sendable {
    let id: Int64
    let body: String
    let createdAt: String
    let path: String?
    let line: Int?
    let user: User?
    struct User: Decodable, Sendable { let login: String }
    enum CodingKeys: String, CodingKey { case id, body, user, path, line; case createdAt = "created_at" }
}

struct GitHubPullRequestReview: Decodable, Identifiable, Sendable {
    let id: Int64
    let state: String
    let body: String?
    let submittedAt: String?
    let user: User?
    struct User: Decodable, Sendable { let login: String }
    enum CodingKeys: String, CodingKey { case id, state, body, user; case submittedAt = "submitted_at" }
}

struct GitHubMergeResult: Decodable, Sendable {
    let merged: Bool
    let message: String
}

struct GitHubContributionSummary: Decodable, Sendable {
    var user: User?
    let calendar: GitHubContributionCalendar
    let commits: Int
    let issues: Int
    let pullRequests: Int
    let reviews: Int
    let repositoryCount: Int
    let repositories: [GitHubContributionRepository]
    let restrictedContributionsCount: Int
    var login: String { user?.login ?? "" }

    struct User: Decodable, Sendable { let login: String }

    enum CodingKeys: String, CodingKey {
        case user, restrictedContributionsCount
        case calendar = "contributionCalendar"
        case commits = "totalCommitContributions"
        case issues = "totalIssueContributions"
        case pullRequests = "totalPullRequestContributions"
        case reviews = "totalPullRequestReviewContributions"
        case repositories = "commitContributionsByRepository"
        case repositoryCount = "totalRepositoriesWithContributedCommits"
    }
}

struct GitHubContributionCalendar: Decodable, Sendable {
    let totalContributions: Int
    let months: [Month]
    let weeks: [Week]

    struct Month: Decodable, Sendable, Identifiable {
        let firstDay: String
        let name: String
        let totalWeeks: Int
        let year: Int
        var id: String { firstDay }
    }

    struct Week: Decodable, Sendable, Identifiable {
        let firstDay: String
        let contributionDays: [Day]
        var id: String { firstDay }
    }

    struct Day: Decodable, Sendable, Identifiable {
        let date: String
        let contributionCount: Int
        let contributionLevel: String
        let weekday: Int
        var id: String { date }
    }
}

struct GitHubContributionRepository: Decodable, Sendable, Identifiable {
    let repository: Details
    var nameWithOwner: String { repository.nameWithOwner }
    var url: URL { repository.url }
    var id: String { repository.nameWithOwner }

    struct Details: Decodable, Sendable {
        let nameWithOwner: String
        let url: URL
    }
}

protocol GitHubProjectHistoryProviding: Sendable {
    func branches(repository: GitHubRepository, accessToken: String) async throws -> [GitHubBranch]
    func commits(repository: GitHubRepository, branch: String, accessToken: String) async throws -> [GitHubCommit]
    func pullRequests(repository: GitHubRepository, accessToken: String) async throws -> [GitHubPullRequest]
}

protocol GitHubPullRequestManaging: Sendable {
    func pullRequestFiles(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestFile]
    func pullRequestComments(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestComment]
    func pullRequestReviewComments(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestComment]
    func pullRequestReviews(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestReview]
    func comment(on repository: GitHubRepository, number: Int, body: String, accessToken: String) async throws
    func submitReview(on repository: GitHubRepository, number: Int, body: String, event: String, accessToken: String) async throws
    func merge(repository: GitHubRepository, number: Int, accessToken: String) async throws -> GitHubMergeResult
}

protocol GitHubContributionProviding: Sendable {
    func contributions(year: Int, accessToken: String) async throws -> GitHubContributionSummary
}

protocol GitHubViewerProviding: Sendable {
    func viewerLogin(accessToken: String) async throws -> String
}

struct GitHubAPIClient: GitHubRepositoryProviding, GitHubProjectHistoryProviding, GitHubPullRequestManaging, GitHubContributionProviding, GitHubViewerProviding {
    static let apiVersion = "2026-03-10"
    private let transport: any GitHubHTTPTransport

    init(transport: any GitHubHTTPTransport = URLSessionGitHubTransport()) {
        self.transport = transport
    }

    func repositories(accessToken: String) async throws -> [GitHubRepository] {
        guard !accessToken.isEmpty else { throw GitHubBackendError.unauthorized }
        var page = 1
        var repositories: [GitHubRepository] = []

        while true {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://api.github.com/user/repos")!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "visibility", value: "all"),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "direction", value: "desc")
            ]
            guard let url = components.url else { throw GitHubBackendError.invalidResponse }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let response = try await transport.send(request)
            try validate(response)
            guard let pageRepositories = try? JSONDecoder().decode([GitHubRepository].self, from: response.data) else {
                throw GitHubBackendError.invalidResponse
            }
            repositories.append(contentsOf: pageRepositories)
            guard pageRepositories.count == 100 else { return repositories }
            page += 1
        }
    }

    func branches(repository: GitHubRepository, accessToken: String) async throws -> [GitHubBranch] {
        try await list(GitHubBranch.self, repository: repository, endpoint: "branches", accessToken: accessToken)
    }

    func commits(repository: GitHubRepository, branch: String, accessToken: String) async throws -> [GitHubCommit] {
        try await list(GitHubCommit.self, repository: repository, endpoint: "commits", accessToken: accessToken, query: [URLQueryItem(name: "sha", value: branch)], maxPages: 1)
    }

    func pullRequests(repository: GitHubRepository, accessToken: String) async throws -> [GitHubPullRequest] {
        try await list(GitHubPullRequest.self, repository: repository, endpoint: "pulls", accessToken: accessToken, query: [URLQueryItem(name: "state", value: "all")])
    }

    func pullRequestFiles(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestFile] {
        guard number > 0 else { throw GitHubBackendError.invalidPullRequestAction }
        return try await list(GitHubPullRequestFile.self, repository: repository, endpoint: "pulls/\(number)/files", accessToken: accessToken)
    }

    func pullRequestComments(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestComment] {
        guard number > 0 else { throw GitHubBackendError.invalidPullRequestAction }
        return try await list(GitHubPullRequestComment.self, repository: repository, endpoint: "issues/\(number)/comments", accessToken: accessToken)
    }

    func pullRequestReviewComments(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestComment] {
        guard number > 0 else { throw GitHubBackendError.invalidPullRequestAction }
        return try await list(GitHubPullRequestComment.self, repository: repository, endpoint: "pulls/\(number)/comments", accessToken: accessToken)
    }

    func pullRequestReviews(repository: GitHubRepository, number: Int, accessToken: String) async throws -> [GitHubPullRequestReview] {
        guard number > 0 else { throw GitHubBackendError.invalidPullRequestAction }
        return try await list(GitHubPullRequestReview.self, repository: repository, endpoint: "pulls/\(number)/reviews", accessToken: accessToken)
    }

    func comment(on repository: GitHubRepository, number: Int, body: String, accessToken: String) async throws {
        try validatePullRequestAction(number: number, body: body)
        try await mutate(repository: repository, endpoint: "issues/\(number)/comments", body: ["body": body], accessToken: accessToken)
    }

    func submitReview(on repository: GitHubRepository, number: Int, body: String, event: String, accessToken: String) async throws {
        try validatePullRequestAction(number: number, body: body)
        guard ["COMMENT", "APPROVE", "REQUEST_CHANGES"].contains(event) else { throw GitHubBackendError.invalidPullRequestAction }
        try await mutate(repository: repository, endpoint: "pulls/\(number)/reviews", body: ["body": body, "event": event], accessToken: accessToken)
    }

    func merge(repository: GitHubRepository, number: Int, accessToken: String) async throws -> GitHubMergeResult {
        guard number > 0 else { throw GitHubBackendError.invalidPullRequestAction }
        let data = try await mutate(repository: repository, endpoint: "pulls/\(number)/merge", method: "PUT", body: ["merge_method": "merge"], accessToken: accessToken)
        guard let result = try? JSONDecoder().decode(GitHubMergeResult.self, from: data) else { throw GitHubBackendError.invalidResponse }
        return result
    }

    func viewerLogin(accessToken: String) async throws -> String {
        guard !accessToken.isEmpty else { throw GitHubBackendError.unauthorized }
        let body = try JSONEncoder().encode(GraphQLRequest(query: "query { viewer { login } }", variables: [:]))
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        try validate(response)
        guard let envelope = try? JSONDecoder().decode(ViewerLoginResponse.self, from: response.data),
              let login = envelope.data?.viewer.login else { throw GitHubBackendError.invalidResponse }
        return login
    }

    func contributions(year: Int, accessToken: String) async throws -> GitHubContributionSummary {
        guard !accessToken.isEmpty else { throw GitHubBackendError.unauthorized }
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentYear = calendar.component(.year, from: now)
        guard year >= 2008, year <= currentYear else { throw GitHubBackendError.invalidResponse }
        let from: Date
        let to: Date
        if year == currentYear {
            to = now
            from = calendar.date(byAdding: .year, value: -1, to: now)!
        } else {
            from = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            to = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!.addingTimeInterval(-1)
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        let variables = ["from": formatter.string(from: from), "to": formatter.string(from: to)]
        let query = """
        query($from: DateTime!, $to: DateTime!) {
          viewer {
            login
            contributionsCollection(from: $from, to: $to) {
              contributionCalendar {
                totalContributions
                months { firstDay name totalWeeks year }
                weeks { firstDay contributionDays { date contributionCount contributionLevel weekday } }
              }
              totalCommitContributions
              totalIssueContributions
              totalPullRequestContributions
              totalPullRequestReviewContributions
              totalRepositoriesWithContributedCommits
              commitContributionsByRepository(maxRepositories: 100) { repository { nameWithOwner url } }
              restrictedContributionsCount
            }
          }
        }
        """
        let requestBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response = try await transport.send(request)
        try Task.checkCancellation()
        try validate(response)
        guard let envelope = try? JSONDecoder().decode(GraphQLResponse.self, from: response.data) else {
            throw GitHubBackendError.invalidResponse
        }
        if let error = envelope.errors?.first {
            throw error.type == "FORBIDDEN" ? GitHubBackendError.contributionAccessDenied : GitHubBackendError.invalidResponse
        }
        guard var summary = envelope.data?.viewer.contributionsCollection,
              let login = envelope.data?.viewer.login else { throw GitHubBackendError.invalidResponse }
        summary.user = .init(login: login)
        return summary
    }

    private func list<T: Decodable & Sendable>(
        _ type: T.Type,
        repository: GitHubRepository,
        endpoint: String,
        accessToken: String,
        query: [URLQueryItem] = [],
        maxPages: Int = .max
    ) async throws -> [T] {
        guard !accessToken.isEmpty else { throw GitHubBackendError.unauthorized }
        let parts = repository.fullName.split(separator: "/")
        guard parts.count == 2,
              let repositoryURL = repository.safeGitHubURL,
              repositoryURL.path == "/\(repository.fullName)" else { throw GitHubBackendError.invalidResponse }
        let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let owner = String(parts[0]).addingPercentEncoding(withAllowedCharacters: pathCharacters),
              let name = String(parts[1]).addingPercentEncoding(withAllowedCharacters: pathCharacters) else {
            throw GitHubBackendError.invalidResponse
        }
        var results: [T] = []
        for page in 1...maxPages {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(name)/\(endpoint)")!
            components.queryItems = query + [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components.url else { throw GitHubBackendError.invalidResponse }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await transport.send(request)
            try validate(response)
            guard let items = try? JSONDecoder().decode([T].self, from: response.data) else { throw GitHubBackendError.invalidResponse }
            results.append(contentsOf: items)
            guard items.count == 100 else { return results }
        }
        return results
    }

    @discardableResult
    private func mutate(repository: GitHubRepository, endpoint: String, method: String = "POST", body: [String: String], accessToken: String) async throws -> Data {
        guard !accessToken.isEmpty else { throw GitHubBackendError.unauthorized }
        let parts = repository.fullName.split(separator: "/")
        guard parts.count == 2, let repositoryURL = repository.safeGitHubURL, repositoryURL.path == "/\(repository.fullName)" else {
            throw GitHubBackendError.invalidResponse
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let owner = String(parts[0]).addingPercentEncoding(withAllowedCharacters: allowed),
              let name = String(parts[1]).addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/\(endpoint)") else {
            throw GitHubBackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { try validate(response); throw GitHubBackendError.httpStatus(response.statusCode) }
        return response.data
    }

    private func validate(_ response: GitHubHTTPResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401: throw GitHubBackendError.unauthorized
        case 403 where response.headers["x-ratelimit-remaining"] == "0", 429:
            let reset = response.headers["x-ratelimit-reset"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
            throw GitHubBackendError.rateLimited(reset)
        case 403: throw GitHubBackendError.forbidden
        default: throw GitHubBackendError.httpStatus(response.statusCode)
        }
    }

    private func validatePullRequestAction(number: Int, body: String) throws {
        guard number > 0,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              body.utf8.count <= 65_536 else { throw GitHubBackendError.invalidPullRequestAction }
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLResponse: Decodable {
    let data: DataPayload?
    let errors: [ErrorPayload]?

    struct DataPayload: Decodable { let viewer: Viewer }
    struct Viewer: Decodable {
        let login: String
        let contributionsCollection: GitHubContributionSummary
    }
    struct ErrorPayload: Decodable { let type: String? }
}

private struct ViewerLoginResponse: Decodable {
    let data: DataPayload?
    struct DataPayload: Decodable { let viewer: Viewer }
    struct Viewer: Decodable { let login: String }
}

func displayGitHubTimestamp(_ value: String?) -> String {
    guard let value else { return "Date unavailable" }
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = isoFormatter.date(from: value) ?? {
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: value)
    }()
    guard let date else { return "Date unavailable" }
    let displayFormatter = DateFormatter()
    displayFormatter.locale = Locale(identifier: "en_US_POSIX")
    displayFormatter.timeZone = .current
    displayFormatter.dateFormat = "MMM d, yyyy, h:mm a"
    return displayFormatter.string(from: date)
}

struct GitHubToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

struct GitHubDeviceAuthorization: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: Int
}

protocol GitHubDeviceAuthorizing: Sendable {
    func requestCode(clientID: String) async throws -> GitHubDeviceAuthorization
    func pollForToken(clientID: String, authorization: GitHubDeviceAuthorization) async throws -> GitHubToken
    func refresh(clientID: String, token: GitHubToken) async throws -> GitHubToken
}

struct GitHubDeviceFlow: GitHubDeviceAuthorizing {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    private let transport: any GitHubHTTPTransport
    private let sleep: Sleep

    init(transport: any GitHubHTTPTransport = URLSessionGitHubTransport(), sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.sleep = sleep
    }

    func requestCode(clientID: String) async throws -> GitHubDeviceAuthorization {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubBackendError.clientNotConfigured
        }
        let response = try await transport.send(oauthRequest(
            path: "/login/device/code",
            values: [("client_id", clientID), ("scope", "offline_access")]
        ))
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: response.data)
            switch error?.error {
            case "device_flow_disabled": throw GitHubBackendError.deviceFlowDisabled
            case "incorrect_client_credentials": throw GitHubBackendError.incorrectClientCredentials
            default: throw GitHubBackendError.httpStatus(response.statusCode)
            }
        }
        let payload = try? JSONDecoder().decode(DeviceCodeResponse.self, from: response.data)
        let uri = payload.flatMap { URL(string: $0.verificationURI) }
        let components = uri.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        guard let payload, let uri, let components,
              components.scheme == "https", components.host == "github.com", components.path == "/login/device",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil, components.fragment == nil else {
            throw GitHubBackendError.invalidVerificationURL
        }
        return GitHubDeviceAuthorization(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURL: uri,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            interval: max(payload.interval, 1)
        )
    }

    func pollForToken(clientID: String, authorization: GitHubDeviceAuthorization) async throws -> GitHubToken {
        var interval = authorization.interval
        while Date() < authorization.expiresAt {
            try Task.checkCancellation()
            try await sleep(.seconds(interval))
            guard Date() < authorization.expiresAt else { break }
            let response = try await transport.send(oauthRequest(
                path: "/login/oauth/access_token",
                values: [
                    ("client_id", clientID),
                    ("device_code", authorization.deviceCode),
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                ]
            ))
            guard (200..<300).contains(response.statusCode),
                  let payload = try? JSONDecoder().decode(OAuthTokenResponse.self, from: response.data) else {
                throw GitHubBackendError.signInFailed
            }
            if let error = payload.error {
                switch error {
                case "authorization_pending": continue
                case "slow_down":
                    interval += 5
                    continue
                case "expired_token", "bad_verification_code": throw GitHubBackendError.deviceCodeExpired
                case "access_denied": throw GitHubBackendError.accessDenied
                default: throw GitHubBackendError.signInFailed
                }
            }
            if let token = payload.token { return token }
            throw GitHubBackendError.signInFailed
        }
        throw GitHubBackendError.deviceCodeExpired
    }

    func refresh(clientID: String, token: GitHubToken) async throws -> GitHubToken {
        guard let refreshToken = token.refreshToken else { throw GitHubBackendError.unauthorized }
        let response = try await transport.send(oauthRequest(
            path: "/login/oauth/access_token",
            values: [
                ("client_id", clientID),
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken)
            ]
        ))
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(OAuthTokenResponse.self, from: response.data),
              let refreshed = payload.token else { throw GitHubBackendError.unauthorized }
        return refreshed
    }

    private func oauthRequest(path: String, values: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://github.com\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        return request
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case error
    }

    var token: GitHubToken? {
        guard let accessToken else { return nil }
        return GitHubToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
}

enum GitHubConfiguration {
    static var clientID: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String else { return nil }
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
