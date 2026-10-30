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

    var cloneStateDescription: String { "Not cloned" }
    var visibilityDescription: String { visibility ?? (isPrivate ? "Private" : "Public") }
    var safeGitHubURL: URL? {
        guard let components = URLComponents(url: htmlURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil else { return nil }
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
    case unauthorized
    case forbidden
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
        case .unauthorized: "GitHub sign-in expired. Sign in again to refresh repository access."
        case .forbidden: "GitHub denied access. Check the app installation and organization approval."
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

struct GitHubAPIClient: GitHubRepositoryProviding {
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
        let payload = try? JSONDecoder().decode(DeviceCodeResponse.self, from: response.data)
        let uri = payload.flatMap { URL(string: $0.verificationURI) }
        let components = uri.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        guard (200..<300).contains(response.statusCode),
              let payload, let uri, let components,
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

enum GitHubConfiguration {
    static var clientID: String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String else { return nil }
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
