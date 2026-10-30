import Foundation
import Testing
@testable import dev

private actor StubTransport: GitHubHTTPTransport {
    private var responses: [GitHubHTTPResponse]
    private var recordedRequests: [URLRequest] = []

    init(_ responses: [GitHubHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        recordedRequests.append(request)
        guard !responses.isEmpty else { throw GitHubBackendError.invalidResponse }
        return responses.removeFirst()
    }

    func requests() -> [URLRequest] { recordedRequests }
}

private actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func sleep(_ duration: Duration) { delays.append(duration) }
}

private actor RepositoryProviderStub: GitHubRepositoryProviding {
    private var requests = 0
    private let repository: GitHubRepository

    init(repository: GitHubRepository) { self.repository = repository }

    func repositories(accessToken: String) async throws -> [GitHubRepository] {
        defer { requests += 1 }
        if requests == 0 { return [repository] }
        throw GitHubBackendError.forbidden
    }
}

private struct FixedTokenStore: GitHubTokenStoring {
    let token: GitHubToken?
    func load() throws -> GitHubToken? { token }
    func save(_ token: GitHubToken) throws { }
    func delete() throws { }
}

struct GitHubBackendTests {
    @Test func listsEveryRepositoryPageAndSendsReadOnlyAuthenticatedRequests() async throws {
        let firstPage = (1...100).map { repositoryJSON(id: $0) }.joined(separator: ",")
        let transport = StubTransport([
            .init(statusCode: 200, data: Data("[\(firstPage)]".utf8), headers: [:]),
            .init(statusCode: 200, data: Data("[\(repositoryJSON(id: 101))]".utf8), headers: [:])
        ])
        let api = GitHubAPIClient(transport: transport)

        let repositories = try await api.repositories(accessToken: "test-access-token")
        let requests = await transport.requests()

        #expect(repositories.count == 101)
        #expect(repositories[0].fullName == "owner/repo-1")
        #expect(repositories[100].id == 101)
        #expect(requests.count == 2)
        #expect(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value == "1")
        #expect(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value == "2")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        #expect(requests[0].value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func mapsUnauthorizedWithoutExposingResponseBody() async throws {
        let transport = StubTransport([.init(statusCode: 401, data: Data("sensitive provider body".utf8), headers: [:])])
        let api = GitHubAPIClient(transport: transport)

        await #expect(throws: GitHubBackendError.unauthorized) {
            try await api.repositories(accessToken: "expired-token")
        }
    }

    @Test func deviceFlowHonorsPollingIntervalAndSlowDown() async throws {
        let authorization = #"{"device_code":"device-secret","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
        let pending = #"{"error":"authorization_pending"}"#
        let slowDown = #"{"error":"slow_down"}"#
        let success = #"{"access_token":"ghu_access","refresh_token":"ghr_refresh","expires_in":28800}"#
        let transport = StubTransport([
            .init(statusCode: 200, data: Data(authorization.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(pending.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(slowDown.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(success.utf8), headers: [:])
        ])
        let sleeper = SleepRecorder()
        let flow = GitHubDeviceFlow(transport: transport, sleep: { await sleeper.sleep($0) })

        let device = try await flow.requestCode(clientID: "public-client-id")
        let token = try await flow.pollForToken(clientID: "public-client-id", authorization: device)
        let delays = await sleeper.delays

        #expect(device.userCode == "ABCD-EFGH")
        #expect(device.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(token.accessToken == "ghu_access")
        #expect(token.refreshToken == "ghr_refresh")
        #expect(delays == [.seconds(5), .seconds(5), .seconds(10)])
    }

    @Test func rejectsUntrustedVerificationURL() async throws {
        let unsafeURLs = [
            "https://attacker.example/login/device",
            "https://attacker@github.com/login/device",
            "https://github.com:444/login/device"
        ]
        for url in unsafeURLs {
            let payload = #"{"device_code":"code","user_code":"ABCD-EFGH","verification_uri":"\#(url)","expires_in":900,"interval":5}"#
            let transport = StubTransport([.init(statusCode: 200, data: Data(payload.utf8), headers: [:])])
            let flow = GitHubDeviceFlow(transport: transport, sleep: { _ in })
            await #expect(throws: GitHubBackendError.invalidVerificationURL) {
                try await flow.requestCode(clientID: "public-client-id")
            }
        }
    }

    @Test func onlyExposesHTTPSGitHubRepositoryLinks() throws {
        let safe = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 1).utf8))
        let unsafeJSON = repositoryJSON(id: 2).replacingOccurrences(
            of: "https://github.com/owner/repo-2",
            with: "https://attacker@github.com/owner/repo-2"
        )
        let unsafe = try JSONDecoder().decode(GitHubRepository.self, from: Data(unsafeJSON.utf8))

        #expect(safe.safeGitHubURL?.host == "github.com")
        #expect(unsafe.safeGitHubURL == nil)
    }

    @Test @MainActor func workspaceLoadsRemoteRepositoriesAndKeepsThemWhenRefreshFails() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 41).utf8))
        let api = RepositoryProviderStub(repository: repository)
        let tokens = FixedTokenStore(token: GitHubToken(accessToken: "keychain-token", refreshToken: nil, expiresAt: nil))
        let store = WorkspaceStore(clientID: "client-id", api: api, tokenStore: tokens)

        await store.restoreSession()
        #expect(store.connectionState == .connected)
        #expect(store.repositories.map(\.id) == [41])
        #expect(store.repositories.first?.fullName == "owner/repo-41")

        await store.refresh()
        #expect(store.repositories.map(\.id) == [41])
        if case .stale = store.connectionState { } else { Issue.record("Expected prior remote data to remain visible as stale") }
    }

    private func repositoryJSON(id: Int) -> String {
        "{\"id\":\(id),\"name\":\"repo-\(id)\",\"full_name\":\"owner/repo-\(id)\",\"private\":false,\"visibility\":\"public\",\"description\":\"A repository\",\"html_url\":\"https://github.com/owner/repo-\(id)\",\"default_branch\":\"main\",\"pushed_at\":\"2026-10-29T09:00:00Z\",\"owner\":{\"login\":\"owner\"}}"
    }
}
