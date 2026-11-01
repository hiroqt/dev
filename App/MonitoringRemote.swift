import Foundation
import Security

enum MonitoringConnection: String, CaseIterable, Identifiable, Sendable {
    case vercel, render, openAI, anthropic
    var id: String { rawValue }
    var name: String {
        switch self {
        case .vercel: "Vercel"
        case .render: "Render"
        case .openAI: "OpenAI API"
        case .anthropic: "Anthropic API"
        }
    }
}

struct MonitoringRemoteRow: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let url: URL?
    let warning: Bool
}

struct MonitoringRemoteResult: Sendable {
    let rows: [MonitoringRemoteRow]
}

enum MonitoringRemoteError: LocalizedError {
    case invalidCredential, invalidResponse, responseTooLarge, http(Int), network, keychain
    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Enter a valid token without spaces or line breaks."
        case .invalidResponse: "The provider returned an unsupported response."
        case .responseTooLarge: "The provider response exceeded the monitoring size limit."
        case .http(401), .http(403): "Access denied. Check the token's reporting permissions and account scope."
        case .http(429): "Provider rate limit reached. Try refreshing later."
        case .http(let status): "Provider request failed (HTTP \(status))."
        case .network: "The provider could not be reached. Try refreshing later."
        case .keychain: "The monitoring credential could not be accessed securely in Keychain."
        }
    }
}

struct MonitoringCredentials {
    private static func query(_ connection: MonitoringConnection) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.arnel.dev.monitoring",
         kSecAttrAccount as String: connection.rawValue]
    }

    static func load(_ connection: MonitoringConnection) throws -> String? {
        var request = query(connection)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw MonitoringRemoteError.keychain }
        return token
    }

    static func save(_ token: String, for connection: MonitoringConnection) throws {
        try MonitoringRemote.validateToken(token)
        let request = query(connection)
        let data = Data(token.utf8)
        var status = SecItemUpdate(request as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = request
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MonitoringRemoteError.keychain }
    }

    static func delete(_ connection: MonitoringConnection) throws {
        let status = SecItemDelete(query(connection) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MonitoringRemoteError.keychain }
    }
}

enum MonitoringRemote {
    static func fetch(_ connection: MonitoringConnection, token: String) async throws -> MonitoringRemoteResult {
        try validateToken(token)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: MonitoringNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        switch connection {
        case .vercel:
            let result = try await VercelMonitoring.fetchProjects(token: token)
            return .init(rows: result.projects.map { .init(id: $0.id, title: $0.name, detail: $0.scopeName, url: $0.dashboardURL, warning: false) }
                + result.warnings.enumerated().map { .init(id: "warning-\($0.offset)", title: "Partial discovery", detail: $0.element, url: nil, warning: true) })
        case .render:
            let data = try await read("https://api.render.com/v1/services", query: [.init(name: "limit", value: "20")], connection: connection, token: token, session: session)
            let services = try decode([RenderServiceEnvelope].self, data).map(\.service)
            var rows: [MonitoringRemoteRow] = []
            for service in services {
                try Task.checkCancellation()
                guard service.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }), !service.id.isEmpty else { throw MonitoringRemoteError.invalidResponse }
                do {
                    let deploys = try await read("https://api.render.com/v1/services/\(service.id)/deploys", query: [.init(name: "limit", value: "1")], connection: connection, token: token, session: session)
                    rows.append(try parseRenderDeployment(deploys, service: service))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    rows.append(.init(id: service.id, title: service.name, detail: "Latest deployment unavailable. \(safeMessage(error))", url: webURL(service.dashboardUrl), warning: true))
                }
            }
            if services.count == 20 { rows.append(partial("Showing the first 20 accessible Render services; more may exist.")) }
            return .init(rows: rows)
        case .openAI, .anthropic:
            let end = Date()
            let start = end.addingTimeInterval(-7 * 24 * 60 * 60)
            if connection == .openAI {
                let query = [URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))), .init(name: "end_time", value: String(Int(end.timeIntervalSince1970))), .init(name: "bucket_width", value: "1d"), .init(name: "limit", value: "31")]
                async let usage = read("https://api.openai.com/v1/organization/usage/completions", query: query, connection: connection, token: token, session: session)
                async let cost = read("https://api.openai.com/v1/organization/costs", query: query, connection: connection, token: token, session: session)
                return try await parseOpenAI(usage: usage, cost: cost)
            }
            let query = [URLQueryItem(name: "starting_at", value: start.ISO8601Format()), .init(name: "ending_at", value: end.ISO8601Format()), .init(name: "limit", value: "100")]
            async let usage = read("https://api.anthropic.com/v1/organizations/analytics/usage", query: query, connection: connection, token: token, session: session)
            async let cost = read("https://api.anthropic.com/v1/organizations/analytics/cost", query: query, connection: connection, token: token, session: session)
            return try await parseAnthropic(usage: usage, cost: cost)
        }
    }

    static func validateToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 4096,
              token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw MonitoringRemoteError.invalidCredential }
    }

    static func safeMessage(_ error: any Error) -> String {
        (error as? MonitoringRemoteError)?.localizedDescription ?? MonitoringRemoteError.network.localizedDescription
    }

    private static func read(_ endpoint: String, query: [URLQueryItem], connection: MonitoringConnection, token: String, session: URLSession) async throws -> Data {
        guard var components = URLComponents(string: endpoint), components.scheme == "https",
              ["api.vercel.com", "api.render.com", "api.openai.com", "api.anthropic.com"].contains(components.host ?? "") else { throw MonitoringRemoteError.invalidResponse }
        components.queryItems = query
        guard let url = components.url else { throw MonitoringRemoteError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if connection == .anthropic {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("analytics-usage-cost-2026-08-24", forHTTPHeaderField: "anthropic-beta")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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

    static func parseRenderDeployment(_ data: Data, service: RenderService) throws -> MonitoringRemoteRow {
        let deployment = try decode([RenderDeployEnvelope].self, data).first?.deploy
        let status = deployment?.status ?? "No deployment"
        let suspended = service.suspended == "suspended"
        return .init(id: service.id, title: service.name, detail: "\(suspended ? "Suspended · " : "")\(status) · \(service.type)",
                     url: webURL(service.dashboardUrl), warning: suspended || status.contains("failed") || status == "canceled")
    }

    static func parseOpenAI(usage: Data, cost: Data) throws -> MonitoringRemoteResult {
        let usage = try decode(OpenAIUsage.self, usage)
        let cost = try decode(OpenAICost.self, cost)
        let results = usage.data.flatMap(\.results)
        let tokens = try results.reduce(Decimal.zero) { sum, value in
            guard value.input_tokens >= 0, value.output_tokens >= 0, value.num_model_requests >= 0 else { throw MonitoringRemoteError.invalidResponse }
            return sum + Decimal(value.input_tokens) + Decimal(value.output_tokens)
        }
        let requests = results.reduce(Decimal.zero) { $0 + Decimal($1.num_model_requests) }
        let dollars = try cost.data.flatMap(\.results).reduce(Decimal.zero) { sum, value in
            guard value.amount.currency.lowercased() == "usd" else { throw MonitoringRemoteError.invalidResponse }
            return sum + value.amount.value.value
        }
        return reporting(tokens: tokens, requests: requests, dollars: dollars, partial: usage.has_more || cost.has_more,
                         note: "Completions tokens and requests; organization API costs. Subscription quotas are separate.")
    }

    static func parseAnthropic(usage: Data, cost: Data) throws -> MonitoringRemoteResult {
        let usage = try decode(AnthropicUsage.self, usage)
        let cost = try decode(AnthropicCost.self, cost)
        let tokens = try usage.data.reduce(Decimal.zero) { sum, row in
            guard row.usage.total_tokens >= 0, row.usage.requests >= 0 else { throw MonitoringRemoteError.invalidResponse }
            return sum + Decimal(row.usage.total_tokens)
        }
        let requests = usage.data.reduce(Decimal.zero) { $0 + Decimal($1.usage.requests) }
        let dollars = try cost.data.reduce(Decimal.zero) { sum, row in
            guard row.cost.currency == "USD" else { throw MonitoringRemoteError.invalidResponse }
            return sum + row.cost.amount.value / 100
        }
        return reporting(tokens: tokens, requests: requests, dollars: dollars, partial: usage.has_more || cost.has_more,
                         note: "Organization analytics, after discounts and before credits. Provider data may lag up to 24 hours.")
    }

    private static func reporting(tokens: Decimal, requests: Decimal, dollars: Decimal, partial isPartial: Bool, note: String) -> MonitoringRemoteResult {
        var rows = [MonitoringRemoteRow(id: "usage", title: "API usage · Last 7 days", detail: "\(tokens.formatted()) tokens · \(requests.formatted()) requests", url: nil, warning: isPartial),
                    .init(id: "cost", title: "API cost · Last 7 days", detail: "\(dollars.formatted(.currency(code: "USD"))) · \(note)", url: nil, warning: isPartial)]
        if isPartial { rows.append(partial("Partial report: the provider has more pages. Displayed totals include only the first page.")) }
        return .init(rows: rows)
    }

    private static func partial(_ detail: String) -> MonitoringRemoteRow {
        .init(id: "partial", title: "Partial results", detail: detail, url: nil, warning: true)
    }

    static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 1_000_000 else { throw MonitoringRemoteError.responseTooLarge }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw MonitoringRemoteError.invalidResponse }
    }

    struct RenderService: Decodable {
        let id: String
        let name: String
        let type: String
        let suspended: String?
        let dashboardUrl: String?
    }
    private struct RenderServiceEnvelope: Decodable { let service: RenderService }
    private struct RenderDeployEnvelope: Decodable { let deploy: Deploy; struct Deploy: Decodable { let status: String } }
    private struct Page<Row: Decodable>: Decodable { let data: [Row]; let has_more: Bool }
    private struct Bucket<Row: Decodable>: Decodable { let results: [Row] }
    private typealias OpenAIUsage = Page<Bucket<OpenAIUsageRow>>
    private struct OpenAIUsageRow: Decodable { let input_tokens: Int64; let output_tokens: Int64; let num_model_requests: Int64 }
    private typealias OpenAICost = Page<Bucket<OpenAICostRow>>
    private struct OpenAICostRow: Decodable { let amount: Amount; struct Amount: Decodable { let value: Number; let currency: String } }
    private typealias AnthropicUsage = Page<AnthropicUsageRow>
    private struct AnthropicUsageRow: Decodable { let usage: Usage; struct Usage: Decodable { let total_tokens: Int64; let requests: Int64 } }
    private typealias AnthropicCost = Page<AnthropicCostRow>
    private struct AnthropicCostRow: Decodable { let cost: Cost; struct Cost: Decodable { let amount: Number; let currency: String } }
    private struct Number: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self), string.count <= 128,
               string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
               let number = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN {
                value = number
            } else {
                value = try container.decode(Decimal.self)
            }
            guard !value.isNaN else { throw MonitoringRemoteError.invalidResponse }
        }
    }
}

private final class MonitoringNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
