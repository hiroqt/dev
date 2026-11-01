import XCTest
@testable import dev

final class VercelMonitoringTests: XCTestCase {
    func testDiscoveryKeepsTeamsWhenPersonalScopeIsDeniedAndPaginatesProjects() async throws {
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[{"id":"team-a","slug":"alpha","name":"Alpha"}],"pagination":{"next":200}}"#),
            .init(path: "/v2/teams", query: ["until": "200"], json: #"{"teams":[{"id":"team-b","slug":"beta"}],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", status: 403),
            .init(path: "/v10/projects", query: ["teamId":"team-a"], json: #"{"projects":[{"id":"p1","name":"site"}],"pagination":{"next":"opaque-cursor"}}"#),
            .init(path: "/v10/projects", query: ["teamId":"team-a", "from":"opaque-cursor"], json: #"{"projects":[{"id":"p2","name":"api"}],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", query: ["teamId":"team-b"], json: #"[{"id":"p3","name":"site"}]"#)
        ])
        let result = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
        XCTAssertEqual(Set(result.projects.map(\.id)), ["team-a:p1", "team-a:p2", "team-b:p3"])
        XCTAssertEqual(result.projects.first(where: { $0.id == "team-a:p1" })?.dashboardURL?.absoluteString, "https://vercel.com/alpha/site")
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("me:") && $0.contains("Access denied") }))
        let remaining = await fixture.remaining
        XCTAssertEqual(remaining, 0)
    }

    func testDefaultAndTeamScopesDeduplicateByProjectIDUsingActualAccountOwner() async throws {
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[{"id":"team-a","slug":"alpha","name":"Alpha"}],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", json: #"{"projects":[{"id":"p1","name":"site","accountId":"team-a"},{"id":"p2","name":"site"}],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", query: ["teamId":"team-a"], json: #"{"projects":[{"id":"p1","name":"site","accountId":"team-a"},{"id":"p2","name":"site"}],"pagination":{"next":null}}"#)
        ])
        let result = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
        XCTAssertEqual(result.projects.count, 2)
        XCTAssertEqual(Set(result.projects.map(\.projectID)), ["p1", "p2"])
        for project in result.projects {
            XCTAssertEqual(project.teamID, "team-a")
            XCTAssertEqual(project.scopeName, "Alpha")
            XCTAssertEqual(project.id, "team-a:\(project.projectID)")
            XCTAssertEqual(project.dashboardURL?.absoluteString, "https://vercel.com/alpha/site")
        }
    }

    func testRateLimitStopsDiscoveryInsteadOfPollingOtherScopes() async throws {
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[{"id":"team-a","slug":"alpha"}],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", status: 429),
            .init(path: "/v10/projects", query: ["teamId":"team-a"])
        ])
        do {
            _ = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
            XCTFail("Rate limiting must stop remaining requests")
        } catch MonitoringRemoteError.http(429) {
            let remaining = await fixture.remaining
            XCTAssertEqual(remaining, 1)
        }
    }

    func testProjectMetadataKeepsCurrentProductionSeparateFromNewerFailedPreview() async throws {
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", json: #"{"projects":[{"id":"p1","name":"site","framework":"nextjs","link":{"type":"github","org":"owner","repo":"site"},"targets":{"production":{"id":"prod","readyState":"READY","createdAt":100000,"url":"prod.vercel.app","alias":["site.example.com","javascript:alert(1)","https://wrong.example.com","user@wrong.example.com"],"meta":{"githubCommitRef":"main","githubCommitSha":"abc123","githubCommitMessage":"Stable release"}}},"latestDeployments":[{"id":"older","readyState":"READY","createdAt":200000,"url":"older.vercel.app"},{"id":"preview","readyState":"ERROR","target":"preview","createdAt":300000,"url":"preview.vercel.app","meta":{"githubCommitRef":"feature","githubCommitSha":"def456","githubCommitMessage":"Try feature"}}]}],"pagination":{"next":null}}"#)
        ])
        let result = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
        let project = try XCTUnwrap(result.projects.first)
        XCTAssertEqual(project.production?.id, "prod")
        XCTAssertEqual(project.production?.state, "READY")
        XCTAssertEqual(project.production?.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(project.production?.branch, "main")
        XCTAssertEqual(project.production?.commitSHA, "abc123")
        XCTAssertEqual(project.latest?.id, "preview")
        XCTAssertEqual(project.latest?.state, "ERROR")
        XCTAssertEqual(project.latest?.branch, "feature")
        XCTAssertEqual(project.domains, ["site.example.com"])
        XCTAssertEqual(project.primaryURL?.absoluteString, "https://site.example.com")
        XCTAssertEqual(project.repository, "owner/site")
        XCTAssertEqual(project.repositoryURL?.absoluteString, "https://github.com/owner/site")
        XCTAssertEqual(project.framework, "nextjs")
    }

    func testMissingProductionMetadataDoesNotPromoteLatestReadyPreview() async throws {
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", json: #"[{"id":"p1","name":"site","targets":{"production":null},"latestDeployments":[{"uid":"preview","readyState":"READY","url":"https://user:secret@evil.example"}],"link":{"type":"github","org":"owner","repo":"../secret"}},{"id":"p2","name":"empty"}]"#)
        ])
        let result = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
        let project = try XCTUnwrap(result.projects.first { $0.projectID == "p1" })
        XCTAssertNil(project.production)
        XCTAssertEqual(project.latest?.id, "preview")
        XCTAssertNil(project.primaryURL)
        XCTAssertNil(project.repositoryURL)
        let empty = try XCTUnwrap(result.projects.first { $0.projectID == "p2" })
        XCTAssertNil(empty.production)
        XCTAssertNil(empty.latest)
        XCTAssertNil(empty.framework)
        XCTAssertNil(empty.analyticsEnabled)
        XCTAssertEqual(empty.domains, [])
        XCTAssertNil(empty.primaryURL)
    }

    func testProductionVisitPrefersValidatedCustomDomain() {
        var value = project()
        value.domains = ["site.vercel.app", "user:secret@example.com", "site.example.com"]
        XCTAssertEqual(value.productionURL?.host, "site.example.com")
        value.domains = ["site.vercel.app"]
        XCTAssertEqual(value.productionURL?.host, "site.vercel.app")
    }

    func testPreviewEndpointIsNeverPresentedAsProduction() {
        var value = project()
        value.latest = .init(id: "preview", state: "READY", target: "Preview", createdAt: nil, url: URL(string: "https://preview.vercel.app"), detail: "")
        XCTAssertEqual(value.primaryURL?.host, "preview.vercel.app")
        XCTAssertNil(value.productionURL)
    }

    func testRepeatedProjectCursorStopsWithWarningAndDeduplicates() async throws {
        let page = #"{"projects":[{"id":"p1","name":"site"}],"pagination":{"next":"same"}}"#
        let fixture = VercelFixture([
            .init(path: "/v2/user", json: #"{"user":{"username":"me"}}"#),
            .init(path: "/v2/teams", json: #"{"teams":[],"pagination":{"next":null}}"#),
            .init(path: "/v10/projects", json: page),
            .init(path: "/v10/projects", query: ["from":"same"], json: page)
        ])
        let result = try await VercelMonitoring.fetchProjects(token: "fake-test-token") { try await fixture.send($0) }
        XCTAssertEqual(result.projects.count, 1)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("limited") }))
    }

    func testDeploymentRequestsCarryProjectTeamAndCursorAndDecodeDates() async throws {
        let fixture = VercelFixture([
            .init(path: "/v7/deployments", query: ["projectId":"p1", "teamId":"team-a", "until":"123", "limit":"20"], json: #"{"deployments":[{"uid":"d1","readyState":"READY","target":"production","createdAt":100000,"url":"site.vercel.app","meta":{"githubCommitRef":"main","githubCommitMessage":"Ship it\nLong body"}},{"uid":"d2","state":"ERROR","url":null}],"pagination":{"next":99}}"#)
        ])
        let page = try await VercelMonitoring.fetchDeployments(project: project(), token: "fake-test-token", before: "123") { try await fixture.send($0) }
        XCTAssertEqual(page.nextCursor, "99")
        XCTAssertEqual(page.deployments[0].createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(page.deployments[0].detail, "main · Ship it")
        XCTAssertEqual(page.deployments[0].branch, "main")
        XCTAssertEqual(page.deployments[0].url?.host, "site.vercel.app")
        XCTAssertEqual(page.deployments[1].state, "ERROR")
        XCTAssertNil(page.deployments[1].url)
    }

    func testTrafficUsesSevenDayMillisecondsAndDoesNotConfusePageviewsWithRequests() async throws {
        let fixture = VercelFixture([
            .init(path: "/v1/query/web-analytics/visits/count", query: ["projectId":"p1", "teamId":"team-a", "since":"395200000", "until":"1000000000"], json: #"{"data":{"pageviews":120,"visitors":45},"version":1}"#),
            .init(path: "/v1/query/web-analytics/visits/aggregate", query: ["projectId":"p1", "teamId":"team-a", "since":"395200000", "until":"1000000000", "by":"day", "limit":"8"], json: #"{"data":[{"timestamp":"1970-01-11T00:00:00.000Z","pageviews":20,"visitors":10},{"timestamp":"1970-01-06T00:00:00Z","pageviews":10,"visitors":5}],"version":1}"#)
        ])
        let traffic = try await VercelMonitoring.fetchTraffic(project: project(), token: "fake-test-token", now: Date(timeIntervalSince1970: 1_000_000)) { try await fixture.send($0) }
        XCTAssertTrue(traffic.detail.contains("120 page views"))
        XCTAssertTrue(traffic.detail.contains("45 visitors"))
        XCTAssertTrue(traffic.detail.contains("requires Web Analytics instrumentation"))
        XCTAssertTrue(traffic.detail.contains("excludes untracked requests and bandwidth"))
        XCTAssertEqual(traffic.pageviews, 120)
        XCTAssertEqual(traffic.visitors, 45)
        XCTAssertFalse(traffic.seriesUnavailable)
        XCTAssertEqual(traffic.daily.map(\.pageviews), [10, 20])
        XCTAssertEqual(traffic.daily.map(\.visitors), [5, 10])
        XCTAssertEqual(traffic.daily.count, 2)
    }

    func testUnavailableDailySeriesPreservesValidCountsWithoutRetry() async throws {
        for status in [401, 403, 429] {
            let fixture = VercelFixture([
                .init(path: "/v1/query/web-analytics/visits/count", json: #"{"data":{"pageviews":120,"visitors":45}}"#),
                .init(path: "/v1/query/web-analytics/visits/aggregate", status: status)
            ])
            let traffic = try await VercelMonitoring.fetchTraffic(project: project(), token: "fake-test-token", now: Date(timeIntervalSince1970: 1_000_000)) { try await fixture.send($0) }
            XCTAssertEqual(traffic.pageviews, 120)
            XCTAssertEqual(traffic.visitors, 45)
            XCTAssertTrue(traffic.seriesUnavailable)
            XCTAssertTrue(traffic.daily.isEmpty)
            let remaining = await fixture.remaining
            XCTAssertEqual(remaining, 0)
        }
    }

    func testRateLimitedCountDoesNotRequestDailySeries() async throws {
        let fixture = VercelFixture([
            .init(path: "/v1/query/web-analytics/visits/count", status: 429),
            .init(path: "/v1/query/web-analytics/visits/aggregate")
        ])
        do {
            _ = try await VercelMonitoring.fetchTraffic(project: project(), token: "fake-test-token", now: .now) { try await fixture.send($0) }
            XCTFail("A rate-limited count must stop further analytics requests")
        } catch MonitoringRemoteError.http(429) {
            let remaining = await fixture.remaining
            XCTAssertEqual(remaining, 1)
        }
    }

    func testEmptyDailyDataDoesNotInventZeroHistoryOrInstrumentationEvidence() async throws {
        let fixture = VercelFixture([
            .init(path: "/v1/query/web-analytics/visits/count", json: #"{"data":{"pageviews":0,"visitors":0}}"#),
            .init(path: "/v1/query/web-analytics/visits/aggregate", json: #"{"data":[]}"#)
        ])
        let traffic = try await VercelMonitoring.fetchTraffic(project: project(), token: "fake-test-token", now: .now) { try await fixture.send($0) }
        XCTAssertEqual(traffic.pageviews, 0)
        XCTAssertTrue(traffic.daily.isEmpty)
        XCTAssertFalse(traffic.seriesUnavailable)
        XCTAssertNil(project().analyticsEnabled)
    }

    func testMalformedDailyDatesCountsAndDuplicatesAreRejected() {
        let start = Date(timeIntervalSince1970: 395_200)
        let end = Date(timeIntervalSince1970: 1_000_000)
        for json in [
            #"{"data":[{"timestamp":"invalid","pageviews":10,"visitors":5}]}"#,
            #"{"data":[{"timestamp":"1970-01-06T00:00:00Z","pageviews":-1,"visitors":5}]}"#,
            #"{"data":[{"timestamp":"1970-01-06T00:00:00Z","pageviews":10}]}"#,
            #"{"data":[{"timestamp":"1970-01-06T00:00:00Z","pageviews":"bad","visitors":5}]}"#,
            #"{"data":[{"timestamp":"1970-01-06T01:00:00Z","pageviews":10,"visitors":5}]}"#,
            #"{"data":[{"timestamp":"1970-01-01T00:00:00Z","pageviews":10,"visitors":5}]}"#,
            #"{"data":[{"timestamp":"1970-01-06T00:00:00Z","pageviews":10,"visitors":5},{"timestamp":"1970-01-06T00:00:00Z","pageviews":10,"visitors":5}]}"#
        ] {
            XCTAssertThrowsError(try VercelMonitoring.parseDailyTraffic(Data(json.utf8), since: start, until: end))
        }
    }

    func testDeploymentPaginationRejectsRepeatedCursor() async throws {
        let fixture = VercelFixture([.init(path: "/v7/deployments", json: #"{"deployments":[],"pagination":{"next":123}}"#)])
        do {
            _ = try await VercelMonitoring.fetchDeployments(project: project(), token: "fake-test-token", before: "123") { try await fixture.send($0) }
            XCTFail("A repeated deployment cursor must not keep loading the same page")
        } catch {
            XCTAssertTrue(error is MonitoringRemoteError)
        }
    }

    func testMalformedAndOversizedReportsAreRejectedAndRequestsStayOnVercel() throws {
        XCTAssertThrowsError(try VercelMonitoring.parseDeployments(Data("{}".utf8)))
        XCTAssertThrowsError(try VercelMonitoring.parseDeployments(Data(repeating: 32, count: 1_000_001)))
        XCTAssertThrowsError(try VercelMonitoring.makeRequest(path: "https://example.com", query: [], token: "fake-test-token"))
        XCTAssertThrowsError(try VercelMonitoring.makeRequest(path: "/v2/teams", query: [], token: "bad\r\ntoken"))
        let request = try VercelMonitoring.makeRequest(path: "/v7/deployments", query: [.init(name: "projectId", value: "p1&teamId=attacker")], token: "fake-test-token")
        XCTAssertEqual(request.url?.host, "api.vercel.com")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.count, 1)
        XCTAssertFalse(request.url!.absoluteString.contains("fake-test-token"))
    }

    private func project() -> VercelProject {
        .init(id: "team-a:p1", projectID: "p1", name: "site", scopeName: "Alpha", teamID: "team-a", dashboardURL: URL(string: "https://vercel.com/alpha/site"))
    }
}

private actor VercelFixture {
    struct Reply: Sendable {
        let path: String
        var query: [String: String] = [:]
        var json: String = "{}"
        var status: Int = 200
    }
    private var replies: [Reply]
    var remaining: Int { replies.count }
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) throws -> Data {
        guard !replies.isEmpty else { throw MonitoringRemoteError.invalidResponse }
        let reply = replies.removeFirst()
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard request.url?.host == "api.vercel.com", request.url?.scheme == "https", request.httpMethod == "GET",
              request.url?.path == reply.path, request.httpBody == nil,
              reply.query.allSatisfy({ key, value in query.contains { $0.name == key && $0.value == value } }) else {
            throw MonitoringRemoteError.invalidResponse
        }
        guard reply.status == 200 else { throw MonitoringRemoteError.http(reply.status) }
        return Data(reply.json.utf8)
    }
}
