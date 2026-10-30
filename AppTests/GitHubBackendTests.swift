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

private struct ContributionProviderStub: GitHubContributionProviding {
    let activity: GitHubContributionSummary
    func contributions(year: Int, accessToken: String) async throws -> GitHubContributionSummary { activity }
}

private struct ViewerProviderStub: GitHubViewerProviding {
    func viewerLogin(accessToken: String) async throws -> String { "octocat" }
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

    @Test func loadsBranchCommitAndPullRequestHistoryWithReadOnlyRequests() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 3).utf8))
        let transport = StubTransport([
            .init(statusCode: 200, data: Data(#"[{"name":"main","commit":{"sha":"branch-sha"}}]"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"[{"sha":"commit-sha","html_url":"https://github.com/owner/repo-3/commit/commit-sha","commit":{"message":"Recent change","author":{"date":"2026-10-30T12:00:00Z"}}}]"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"[{"number":8,"title":"Fix","state":"closed","body":"PR description","html_url":"https://github.com/owner/repo-3/pull/8","updated_at":"2026-10-30T12:00:00Z","merged_at":"2026-10-30T13:00:00Z","user":{"login":"octocat"}}]"#.utf8), headers: [:])
        ])
        let api = GitHubAPIClient(transport: transport)

        let branches = try await api.branches(repository: repository, accessToken: "test-token")
        let commits = try await api.commits(repository: repository, branch: "main", accessToken: "test-token")
        let pullRequests = try await api.pullRequests(repository: repository, accessToken: "test-token")
        let requests = await transport.requests()

        #expect(branches.map(\.name) == ["main"])
        #expect(commits.first?.commit.message == "Recent change")
        #expect(pullRequests.first?.mergedAt != nil)
        #expect(pullRequests.first?.body == "PR description")
        #expect(requests.count == 3)
        #expect(URLComponents(url: requests.first(where: { $0.url?.path.hasSuffix("/commits") == true })!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "sha" })?.value == "main")
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
    }

    @Test func loadsPullRequestFilesAndDiscussionThenPostsReviewAndMerges() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 3).utf8))
        let transport = StubTransport([
            .init(statusCode: 200, data: Data(#"[{"filename":"Sources/App.swift","status":"modified","additions":3,"deletions":1,"patch":"@@ -1 +1 @@"}]"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"[{"id":1,"body":"Looks good","created_at":"2026-10-30T12:00:00Z","user":{"login":"octocat"}}]"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"[{"id":5,"path":"Sources/App.swift","line":12,"body":"Consider this case","created_at":"2026-10-30T12:00:00Z","user":{"login":"octocat"}}]"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"[{"id":2,"state":"APPROVED","body":"Approved","submitted_at":"2026-10-30T12:00:00Z","user":{"login":"octocat"}}]"#.utf8), headers: [:]),
            .init(statusCode: 201, data: Data(#"{"id":3}"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"{"id":4}"#.utf8), headers: [:]),
            .init(statusCode: 200, data: Data(#"{"merged":true,"message":"Pull Request successfully merged"}"#.utf8), headers: [:])
        ])
        let api = GitHubAPIClient(transport: transport)
        let files = try await api.pullRequestFiles(repository: repository, number: 8, accessToken: "test-token")
        let comments = try await api.pullRequestComments(repository: repository, number: 8, accessToken: "test-token")
        let reviewComments = try await api.pullRequestReviewComments(repository: repository, number: 8, accessToken: "test-token")
        let reviews = try await api.pullRequestReviews(repository: repository, number: 8, accessToken: "test-token")
        try await api.comment(on: repository, number: 8, body: "Thanks", accessToken: "test-token")
        try await api.submitReview(on: repository, number: 8, body: "Approved", event: "APPROVE", accessToken: "test-token")
        let merge = try await api.merge(repository: repository, number: 8, accessToken: "test-token")
        let requests = await transport.requests()

        #expect(files.first?.filename == "Sources/App.swift")
        #expect(comments.first?.body == "Looks good")
        #expect(reviewComments.first?.path == "Sources/App.swift")
        #expect(reviews.first?.state == "APPROVED")
        #expect(merge.merged)
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "GET", "GET", "POST", "POST", "PUT"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
        let commentBody = try #require(requests[4].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        let reviewBody = try #require(requests[5].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(commentBody["body"] == "Thanks")
        #expect(reviewBody["event"] == "APPROVE")
        #expect(requests[6].url?.path.hasSuffix("/pulls/8/merge") == true)
    }

    @Test func rejectsInvalidPullRequestWritesBeforeNetwork() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 3).utf8))
        let transport = StubTransport([])
        let api = GitHubAPIClient(transport: transport)

        await #expect(throws: GitHubBackendError.invalidPullRequestAction) {
            try await api.comment(on: repository, number: 8, body: " \n", accessToken: "test-token")
        }
        await #expect(throws: GitHubBackendError.invalidPullRequestAction) {
            try await api.submitReview(on: repository, number: 8, body: "Looks fine", event: "MERGE", accessToken: "test-token")
        }
        await #expect(throws: GitHubBackendError.invalidPullRequestAction) {
            try await api.merge(repository: repository, number: -1, accessToken: "test-token")
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func loadsSignedInViewerUsernameWithoutAdditionalPermissions() async throws {
        let transport = StubTransport([.init(statusCode: 200, data: Data(#"{"data":{"viewer":{"login":"octocat"}}}"#.utf8), headers: [:])])
        let login = try await GitHubAPIClient(transport: transport).viewerLogin(accessToken: "test-token")
        let request = try #require(await transport.requests().first)
        let body = try #require(request.httpBody)
        let requestJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(login == "octocat")
        #expect((requestJSON["query"] as? String)?.contains("viewer { login }") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test func formatsGitHubTimestampsAsMonthDayYear() {
        #expect(displayGitHubTimestamp("2026-10-30T12:00:00Z").hasPrefix("Oct 30, 2026"))
        #expect(displayGitHubTimestamp("invalid") == "Date unavailable")
    }

    @Test func rendersMarkdownAsReadableText() {
        let preview = String(readableMarkdown("# Setup\n\nOpen **Preview**.").characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let blocks = markdownBlocks("# Setup\n\nFirst paragraph.\ncontinued line.\n\n- One\n- Two\n\n```swift\nlet ready = true\n```")

        #expect(preview.contains("Setup"))
        #expect(preview.contains("Preview"))
        #expect(!preview.contains("**"))
        #expect(blocks.map(\.style) == [.heading(1), .paragraph, .unorderedItem, .unorderedItem, .code])
        #expect(blocks[1].text == "First paragraph. continued line.")
        #expect(blocks[4].text == "let ready = true")
    }

    @Test func loadsContributionCalendarForSelectedYearWithAuthenticatedGraphQL() async throws {
        let payload = #"{"data":{"viewer":{"login":"octocat","contributionsCollection":{"contributionCalendar":{"totalContributions":12,"months":[{"firstDay":"2025-01-01","name":"January","totalWeeks":1,"year":2025}],"weeks":[{"firstDay":"2025-01-01","contributionDays":[{"date":"2025-01-01","contributionCount":2,"contributionLevel":"SECOND_QUARTILE","weekday":3}]}]},"totalCommitContributions":8,"totalIssueContributions":1,"totalPullRequestContributions":2,"totalPullRequestReviewContributions":1,"totalRepositoriesWithContributedCommits":2,"commitContributionsByRepository":[{"repository":{"nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello"}}],"restrictedContributionsCount":0}}}}"#
        let transport = StubTransport([.init(statusCode: 200, data: Data(payload.utf8), headers: [:])])
        let api = GitHubAPIClient(transport: transport)
        let activity = try await api.contributions(year: 2025, accessToken: "test-token")
        let request = try #require(await transport.requests().first)
        let body = try #require(request.httpBody)
        let requestJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try #require(requestJSON["variables"] as? [String: String])
        let query = try #require(requestJSON["query"] as? String)

        #expect(activity.login == "octocat")
        #expect(activity.calendar.totalContributions == 12)
        #expect(activity.calendar.weeks.first?.contributionDays.first?.contributionCount == 2)
        #expect(activity.commits == 8)
        #expect(activity.repositories.first?.nameWithOwner == "octocat/hello")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(query.contains("contributionsCollection(from: $from, to: $to)"))
        #expect(!query.contains("user { login }"))
        #expect(variables["from"] == "2025-01-01T00:00:00Z")
        #expect(variables["to"] == "2025-12-31T23:59:59Z")
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

    @Test func cloneNeverOverwritesAnExistingDestination() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 1).utf8))
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = parent.appending(path: repository.name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        await #expect(throws: LocalGitError.destinationExists) {
            try await LocalGitCloner().clone(repository: repository, parent: parent, accessToken: "unused")
        }
    }

    @Test func cloneRecognizesAnExistingCheckoutForTheSelectedRepository() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 1).utf8))
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let folder = parent.appending(path: repository.name)
        defer { try? FileManager.default.removeItem(at: parent) }
        try initializeGitFolder(folder, remote: "https://github.com/owner/repo-1.git")

        let result = try await LocalGitCloner().clone(repository: repository, parent: parent, accessToken: "unused")

        #expect(result.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test @MainActor func workspaceLoadsRemoteRepositoriesAndKeepsThemWhenRefreshFails() async throws {
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: Data(repositoryJSON(id: 41).utf8))
        let api = RepositoryProviderStub(repository: repository)
        let tokens = FixedTokenStore(token: GitHubToken(accessToken: "keychain-token", refreshToken: nil, expiresAt: nil))
        let store = WorkspaceStore(clientID: "client-id", api: api, viewerAPI: ViewerProviderStub(), tokenStore: tokens)

        await store.restoreSession()
        #expect(store.connectionState == .connected)
        #expect(store.repositories.map(\.id) == [41])
        #expect(store.repositories.first?.fullName == "owner/repo-41")
        #expect(store.signedInUsername == "octocat")

        await store.refresh()
        #expect(store.repositories.map(\.id) == [41])
        if case .stale = store.connectionState { } else { Issue.record("Expected prior remote data to remain visible as stale") }
    }

    @Test @MainActor func workspaceLoadsContributionActivityWithStoredToken() async throws {
        let activity = GitHubContributionSummary(
            user: .init(login: "octocat"),
            calendar: GitHubContributionCalendar(totalContributions: 7, months: [], weeks: []),
            commits: 5,
            issues: 1,
            pullRequests: 1,
            reviews: 0,
            repositoryCount: 1,
            repositories: [],
            restrictedContributionsCount: 0
        )
        let tokens = FixedTokenStore(token: GitHubToken(accessToken: "keychain-token", refreshToken: nil, expiresAt: nil))
        let store = WorkspaceStore(
            clientID: "client-id",
            contributionAPI: ContributionProviderStub(activity: activity),
            tokenStore: tokens
        )

        await store.loadContributionActivity(year: 2025)

        #expect(store.contributionActivity?.login == "octocat")
        #expect(store.contributionActivity?.calendar.totalContributions == 7)
        #expect(store.contributionActivityError == nil)
        #expect(!store.contributionActivityLoading)
    }

    private func repositoryJSON(id: Int) -> String {
        "{\"id\":\(id),\"name\":\"repo-\(id)\",\"full_name\":\"owner/repo-\(id)\",\"private\":false,\"visibility\":\"public\",\"description\":\"A repository\",\"html_url\":\"https://github.com/owner/repo-\(id)\",\"default_branch\":\"main\",\"pushed_at\":\"2026-10-29T09:00:00Z\",\"owner\":{\"login\":\"owner\"}}"
    }

    private func initializeGitFolder(_ folder: URL, remote: String) throws {
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        for arguments in [["init", "--quiet", folder.path], ["-C", folder.path, "remote", "add", "origin", remote]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LocalGitError.notMatchingRepository }
        }
    }
}
