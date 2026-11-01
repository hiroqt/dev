import Foundation

struct VercelProject: Identifiable, Sendable, Decodable {
    let id: String
    let projectID: String
    let name: String
    let scopeName: String
    let teamID: String?
    let dashboardURL: URL?
    var production: VercelDeployment? = nil
    var latest: VercelDeployment? = nil
    var domains: [String] = []
    var repository: String? = nil
    var repositoryURL: URL? = nil
    var framework: String? = nil
    var analyticsEnabled: Bool? = nil

    var productionURL: URL? {
        let endpoints = domains.compactMap(VercelMonitoring.domainURL)
        return endpoints.first { !($0.host?.lowercased().hasSuffix(".vercel.app") ?? true) }
            ?? endpoints.first
            ?? production?.url.flatMap { MonitoringRemote.webURL($0.absoluteString) }
    }

    var primaryURL: URL? {
        productionURL ?? latest?.url.flatMap { MonitoringRemote.webURL($0.absoluteString) }
    }

}

struct VercelDeployment: Identifiable, Sendable, Decodable {
    let id: String
    let state: String
    let target: String
    let createdAt: Date?
    let url: URL?
    let detail: String
    var branch: String? = nil
    var commitSHA: String? = nil
}

struct VercelProjectResult: Sendable, Decodable {
    let projects: [VercelProject]
    let warnings: [String]
}

struct VercelDeploymentPage: Sendable, Decodable {
    let deployments: [VercelDeployment]
    let nextCursor: String?
}

struct VercelTraffic: Sendable {
    let detail: String
    var pageviews: Int? = nil
    var visitors: Int? = nil
    var daily: [VercelDailyTraffic] = []
    var seriesUnavailable = false
}

struct VercelDailyTraffic: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let pageviews: Int
    let visitors: Int
}

enum VercelMonitoring {
    typealias Request = @Sendable (URLRequest) async throws -> Data

    static func fetchProjects(token: String) async throws -> VercelProjectResult {
        let session = session()
        defer { session.invalidateAndCancel() }
        return try await fetchProjects(token: token) { try await read($0, session: session) }
    }

    static func fetchProjects(token: String, request: Request) async throws -> VercelProjectResult {
        try MonitoringRemote.validateToken(token)
        var scopes: [(id: String?, name: String, slug: String?)] = [(nil, "Personal account", nil)]
        var warnings: [String] = []
        do {
            let user = try decode(UserResponse.self, await request(makeRequest(path: "/v2/user", query: [], token: token)))
            scopes[0] = (nil, user.user.username, user.user.username)
        } catch is CancellationError { throw CancellationError() }
        catch MonitoringRemoteError.http(429) { throw MonitoringRemoteError.http(429) }
        catch { warnings.append("Personal account details unavailable; team discovery will continue.") }
        var cursor: String?
        var teamIDs: Set<String> = []
        var seenTeamCursors: Set<String> = []
        do {
            for pageIndex in 0..<10 {
                try Task.checkCancellation()
                var query = [URLQueryItem(name: "limit", value: "100")]
                if let cursor { query.append(.init(name: "until", value: cursor)) }
                let page = try decode(TeamsPage.self, await request(makeRequest(path: "/v2/teams", query: query, token: token)))
                for team in page.teams where teamIDs.insert(team.id).inserted {
                    guard scopes.count <= 100 else { break }
                    scopes.append((team.id, team.name ?? team.slug, team.slug))
                }
                cursor = page.pagination?.next?.value
                guard let next = cursor else { break }
                if pageIndex == 9 || scopes.count > 100 || !seenTeamCursors.insert(next).inserted {
                    warnings.append("Team discovery was limited; some accessible teams may be missing.")
                    break
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch MonitoringRemoteError.http(429) { throw MonitoringRemoteError.http(429) }
        catch { warnings.append("Team discovery unavailable. \(MonitoringRemote.safeMessage(error))") }

        var projects: [String: (value: VercelProject, ownership: Int)] = [:]
        var projectRequestCount = 0
        for scope in scopes {
            guard projectRequestCount < 100 else {
                warnings.append("Discovery reached the 100-request limit; additional project scopes were not checked.")
                break
            }
            var cursor: String?
            var seenCursors: Set<String> = []
            do {
                for pageIndex in 0..<10 {
                    try Task.checkCancellation()
                    guard projectRequestCount < 100 else {
                        warnings.append("\(scope.name): discovery reached the 100-request limit; more projects may exist.")
                        break
                    }
                    projectRequestCount += 1
                    var query = [URLQueryItem(name: "limit", value: "100")]
                    if let teamID = scope.id { query.append(.init(name: "teamId", value: teamID)) }
                    if let cursor { query.append(.init(name: "from", value: cursor)) }
                    let page = try decode(ProjectsPage.self, await request(makeRequest(path: "/v10/projects", query: query, token: token)))
                    for project in page.projects {
                        let owner = project.accountId.flatMap { accountID in scopes.first { $0.id == accountID } }
                        let resolvedScope = owner ?? scope
                        let ownership = owner != nil ? 2 : scope.id != nil ? 1 : 0
                        if let existing = projects[project.id], existing.ownership >= ownership { continue }
                        let id = "\(resolvedScope.id ?? "personal"):\(project.id)"
                        let dashboard = resolvedScope.slug.flatMap { dashboardURL(scope: $0, project: project.name) }
                        let production = project.targets?.production.flatMap { deployment($0, target: "Production") }
                        let latestDTO = project.latestDeployments?.reduce(nil as Deployment?) { latest, candidate in
                            guard let latest else { return candidate }
                            return (candidate.createdAt ?? candidate.created ?? -.infinity) > (latest.createdAt ?? latest.created ?? -.infinity) ? candidate : latest
                        }
                        let latest = latestDTO.flatMap { deployment($0) }
                        let domains = (project.targets?.production?.alias ?? []).compactMap { domainURL($0)?.host }
                        let repository = project.link?.repository
                        let value = VercelProject(id: id, projectID: project.id, name: project.name, scopeName: resolvedScope.name, teamID: resolvedScope.id, dashboardURL: dashboard,
                            production: production, latest: latest, domains: domains, repository: repository,
                            repositoryURL: project.link?.repositoryURL, framework: project.framework)
                        projects[project.id] = (value, ownership)
                    }
                    cursor = page.pagination?.next?.value
                    guard let next = cursor else { break }
                    if pageIndex == 9 || projects.count >= 5_000 || !seenCursors.insert(next).inserted {
                        warnings.append("\(scope.name): project discovery was limited; more projects may exist.")
                        break
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch MonitoringRemoteError.http(429) { throw MonitoringRemoteError.http(429) }
            catch { warnings.append("\(scope.name): project discovery unavailable. \(MonitoringRemote.safeMessage(error))") }
            if projects.count >= 5_000 {
                warnings.append("Discovery reached the 5,000-project limit; additional scopes were not checked.")
                break
            }
        }
        let sorted = projects.values.map(\.value).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return .init(projects: sorted, warnings: warnings)
    }

    static func fetchDeployments(project: VercelProject, token: String, before: String? = nil) async throws -> VercelDeploymentPage {
        let session = session()
        defer { session.invalidateAndCancel() }
        return try await fetchDeployments(project: project, token: token, before: before) { try await read($0, session: session) }
    }

    static func fetchDeployments(project: VercelProject, token: String, before: String? = nil, request: Request) async throws -> VercelDeploymentPage {
        var query = [URLQueryItem(name: "projectId", value: project.projectID), .init(name: "limit", value: "20")]
        if let teamID = project.teamID { query.append(.init(name: "teamId", value: teamID)) }
        if let before {
            guard before.count <= 4096 else { throw MonitoringRemoteError.invalidResponse }
            query.append(.init(name: "until", value: before))
        }
        let response = try await request(makeRequest(path: "/v7/deployments", query: query, token: token))
        let page = try parseDeployments(response)
        guard before == nil || page.nextCursor != before else { throw MonitoringRemoteError.invalidResponse }
        return page
    }

    static func fetchTraffic(project: VercelProject, token: String) async throws -> VercelTraffic {
        let session = session()
        defer { session.invalidateAndCancel() }
        return try await fetchTraffic(project: project, token: token, now: .now) { try await read($0, session: session) }
    }

    static func fetchTraffic(project: VercelProject, token: String, now: Date, request: Request) async throws -> VercelTraffic {
        var query = [URLQueryItem(name: "projectId", value: project.projectID),
                     .init(name: "since", value: String(Int64(now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970 * 1000))),
                     .init(name: "until", value: String(Int64(now.timeIntervalSince1970 * 1000)))]
        if let teamID = project.teamID { query.append(.init(name: "teamId", value: teamID)) }
        let response = try await request(makeRequest(path: "/v1/query/web-analytics/visits/count", query: query, token: token))
        let page = try decode(TrafficResponse.self, response)
        guard page.data.pageviews >= 0, page.data.visitors >= 0 else { throw MonitoringRemoteError.invalidResponse }
        var result = VercelTraffic(detail: "Last 7 days · \(page.data.pageviews.formatted()) page views · \(page.data.visitors.formatted()) visitors. Production browser analytics; requires Web Analytics instrumentation. This excludes untracked requests and bandwidth.", pageviews: Int(page.data.pageviews), visitors: Int(page.data.visitors))
        query += [.init(name: "by", value: "day"), .init(name: "limit", value: "8")]
        do {
            let series = try await request(makeRequest(path: "/v1/query/web-analytics/visits/aggregate", query: query, token: token))
            result.daily = try parseDailyTraffic(series, since: now.addingTimeInterval(-7 * 86_400), until: now)
        } catch is CancellationError { throw CancellationError() }
        catch { result.seriesUnavailable = true }
        return result
    }

    static func parseDailyTraffic(_ data: Data, since: Date, until: Date) throws -> [VercelDailyTraffic] {
        let response = try decode(DailyTrafficResponse.self, data)
        guard response.data.count <= 8 else { throw MonitoringRemoteError.invalidResponse }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let firstDay = calendar.startOfDay(for: since)
        let lastDay = calendar.startOfDay(for: until)
        var days: Set<Date> = []
        return try response.data.map { row in
            guard let date = fractional.date(from: row.timestamp) ?? standard.date(from: row.timestamp),
                  date == calendar.startOfDay(for: date), date >= firstDay, date <= lastDay,
                  days.insert(date).inserted, row.pageviews >= 0, row.visitors >= 0 else { throw MonitoringRemoteError.invalidResponse }
            return VercelDailyTraffic(date: date, pageviews: row.pageviews, visitors: row.visitors)
        }.sorted { $0.date < $1.date }
    }

    static func parseDeployments(_ data: Data) throws -> VercelDeploymentPage {
        let page = try decode(DeploymentsResponse.self, data)
        let deployments = try page.deployments.map { dto in
            guard let value = deployment(dto) else { throw MonitoringRemoteError.invalidResponse }
            return value
        }
        return .init(deployments: deployments, nextCursor: page.pagination?.next?.value)
    }

    private static func deployment(_ value: Deployment, target: String? = nil) -> VercelDeployment? {
        guard let id = value.id ?? value.uid, !id.isEmpty else { return nil }
        let timestamp = value.createdAt ?? value.created
        let date = timestamp.flatMap { $0.isFinite && $0 >= 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        let meta = value.meta ?? [:]
        let branch = meta["githubCommitRef"] ?? meta["gitlabCommitRef"] ?? meta["bitbucketCommitRef"] ?? meta["gitCommitRef"]
        let sha = meta["githubCommitSha"] ?? meta["gitlabCommitSha"] ?? meta["bitbucketCommitSha"] ?? meta["gitCommitSha"]
        let message = meta["githubCommitMessage"] ?? meta["gitlabCommitMessage"] ?? meta["bitbucketCommitMessage"] ?? meta["gitCommitMessage"]
        let detail = [branch, message?.split(whereSeparator: \.isNewline).first.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        let url = value.url.flatMap { $0.contains("://") ? MonitoringRemote.webURL($0) : domainURL($0) }
        return .init(id: id, state: value.readyState ?? value.state ?? "Unknown", target: target ?? value.target ?? "Preview", createdAt: date, url: url, detail: detail, branch: branch, commitSHA: sha)
    }

    static func domainURL(_ domain: String) -> URL? {
        guard domain.count <= 253, !domain.isEmpty,
              domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                      && label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
              }) else { return nil }
        return MonitoringRemote.webURL("https://\(domain)")
    }

    private static func dashboardURL(scope: String, project: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "vercel.com"
        components.path = "/\(scope)/\(project)"
        return components.url
    }

    static func makeRequest(path: String, query: [URLQueryItem], token: String) throws -> URLRequest {
        try MonitoringRemote.validateToken(token)
        guard ["/v2/user", "/v2/teams", "/v10/projects", "/v7/deployments", "/v1/query/web-analytics/visits/count", "/v1/query/web-analytics/visits/aggregate"].contains(path) else { throw MonitoringRemoteError.invalidResponse }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.vercel.com"
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw MonitoringRemoteError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: VercelNoRedirects(), delegateQueue: nil)
    }

    private static func read(_ request: URLRequest, session: URLSession) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw MonitoringRemoteError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw MonitoringRemoteError.http(http.statusCode) }
            guard response.expectedContentLength <= 1_000_000 else { throw MonitoringRemoteError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1_000_000 else { throw MonitoringRemoteError.responseTooLarge }
                data.append(byte)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as MonitoringRemoteError { throw error }
        catch { throw MonitoringRemoteError.network }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 1_000_000 else { throw MonitoringRemoteError.responseTooLarge }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw MonitoringRemoteError.invalidResponse }
    }

    private struct Cursor: Decodable {
        let value: String
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self), !string.isEmpty, string.count <= 4096 { value = string }
            else { value = String(try container.decode(Int64.self)) }
        }
    }
    private struct Pagination: Decodable { let next: Cursor? }
    private struct UserResponse: Decodable { let user: User; struct User: Decodable { let username: String } }
    private struct Team: Decodable { let id: String; let slug: String; let name: String? }
    private struct TeamsPage: Decodable { let teams: [Team]; let pagination: Pagination? }
    private struct Project: Decodable {
        let id: String
        let name: String
        let accountId: String?
        let targets: Targets?
        let latestDeployments: [Deployment]?
        let link: RepositoryLink?
        let framework: String?
    }
    private struct Targets: Decodable { let production: Deployment? }
    private struct RepositoryLink: Decodable {
        let type: String?
        let org: String?
        let repo: String?
        var repository: String? {
            guard ["github", "github-limited"].contains(type ?? ""), let org, let repo,
                  !org.isEmpty, !repo.isEmpty else { return nil }
            return "\(org)/\(repo)"
        }
        var repositoryURL: URL? {
            guard let org, let repo, repository != nil,
                  [org, repo].allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) } }),
                  org != ".", org != "..", repo != ".", repo != ".." else { return nil }
            return MonitoringRemote.webURL("https://github.com/\(org)/\(repo)")
        }
    }
    private struct ProjectsPage: Decodable {
        let projects: [Project]
        let pagination: Pagination?
        enum CodingKeys: CodingKey { case projects, pagination }
        init(from decoder: any Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                projects = try container.decode([Project].self, forKey: .projects)
                pagination = try container.decodeIfPresent(Pagination.self, forKey: .pagination)
            } else {
                projects = try decoder.singleValueContainer().decode([Project].self)
                pagination = nil
            }
        }
    }
    private struct DeploymentsResponse: Decodable {
        let deployments: [Deployment]
        let pagination: Pagination?
    }
    private struct Deployment: Decodable {
        let id: String?
        let uid: String?
        let readyState: String?
        let state: String?
        let target: String?
        let createdAt: Double?
        let created: Double?
        let url: String?
        let meta: [String: String]?
        let alias: [String]?
    }
    private struct TrafficResponse: Decodable {
        let data: Counts
        struct Counts: Decodable { let pageviews: Int64; let visitors: Int64 }
    }
    private struct DailyTrafficResponse: Decodable {
        let data: [Row]
        struct Row: Decodable { let timestamp: String; let pageviews: Int; let visitors: Int }
    }
}

private final class VercelNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
