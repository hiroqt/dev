import XCTest
@testable import dev

final class MonitoringRemoteTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testAnthropicAnalyticsConvertsCentsAndMarksIncompleteReports() throws {
        let usage = data(#"{"data":[{"usage":{"total_tokens":1500,"requests":3}}],"has_more":true}"#)
        let cost = data(#"{"data":[{"cost":{"amount":"1234.000000","currency":"USD"}}],"has_more":false}"#)
        let result = try MonitoringRemote.parseAnthropic(usage: usage, cost: cost)
        XCTAssertTrue(result.rows[0].detail.contains(Decimal(1500).formatted()))
        XCTAssertTrue(result.rows[1].detail.contains(Decimal(string: "12.34")!.formatted(.currency(code: "USD"))))
        XCTAssertTrue(result.rows.allSatisfy(\.warning))
        XCTAssertEqual(result.rows.last?.id, "partial")
    }

    func testOpenAIAddsInputAndOutputAndAcceptsNumericOrStringDollarAmounts() throws {
        let usage = data(#"{"data":[{"results":[{"input_tokens":200,"output_tokens":50,"num_model_requests":2},{"input_tokens":30,"output_tokens":20,"num_model_requests":1}]}],"has_more":false}"#)
        let cost = data(#"{"data":[{"results":[{"amount":{"value":1.25,"currency":"usd"}},{"amount":{"value":"0.75","currency":"usd"}}]}],"has_more":false}"#)
        let result = try MonitoringRemote.parseOpenAI(usage: usage, cost: cost)
        XCTAssertTrue(result.rows[0].detail.contains("300 tokens"))
        XCTAssertTrue(result.rows[0].detail.contains("3 requests"))
        XCTAssertTrue(result.rows[1].detail.contains(Decimal(2).formatted(.currency(code: "USD"))))
        XCTAssertFalse(result.rows.contains(where: \.warning))
    }

    func testMalformedReportingDoesNotBecomeAZeroUsageSuccess() {
        let empty = data(#"{"data":[],"has_more":false}"#)
        XCTAssertThrowsError(try MonitoringRemote.parseOpenAI(usage: data("{}"), cost: empty))
        XCTAssertThrowsError(try MonitoringRemote.parseAnthropic(usage: data(#"{"data":[{"usage":{"total_tokens":-1,"requests":0}}],"has_more":false}"#), cost: empty))
        for amount in ["12junk", "NaN", "Infinity"] {
            let cost = data("{\"data\":[{\"cost\":{\"amount\":\"\(amount)\",\"currency\":\"USD\"}}],\"has_more\":false}")
            XCTAssertThrowsError(try MonitoringRemote.parseAnthropic(usage: empty, cost: cost))
        }
        XCTAssertThrowsError(try MonitoringRemote.parseAnthropic(usage: empty, cost: data(#"{"data":[{"cost":{"amount":"100","currency":"EUR"}}],"has_more":false}"#)))
    }

    func testRemoteLinksRejectCredentialsAndUnsupportedSchemes() {
        for url in ["file:///etc/passwd", "javascript:alert(1)", "https://token@example.com", "https://"] {
            XCTAssertNil(MonitoringRemote.webURL(url))
        }
    }

    func testRenderSuspensionAndLatestFailedDeployAreWarnings() throws {
        let service = MonitoringRemote.RenderService(id: "srv-1", name: "API", type: "web_service", suspended: "suspended", dashboardUrl: "https://dashboard.render.com/web/srv-1")
        let row = try MonitoringRemote.parseRenderDeployment(data(#"[{"deploy":{"status":"build_failed"},"cursor":"cursor"}]"#), service: service)
        XCTAssertTrue(row.warning)
        XCTAssertTrue(row.detail.contains("Suspended"))
        XCTAssertTrue(row.detail.contains("build_failed"))
        XCTAssertEqual(row.url?.host, "dashboard.render.com")
        XCTAssertThrowsError(try MonitoringRemote.parseRenderDeployment(data("{}"), service: service))
    }

    func testTokensErrorsAndResponseBoundsDoNotExposeSecrets() {
        for token in ["", "token\r\nHeader:value", "token value", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try MonitoringRemote.validateToken(token))
        }
        XCTAssertNoThrow(try MonitoringRemote.validateToken("token_example-123"))
        let secret = "credential-sensitive-value"
        XCTAssertFalse(MonitoringRemote.safeMessage(NSError(domain: secret, code: 1, userInfo: [NSLocalizedDescriptionKey: secret])).contains(secret))
        XCTAssertTrue(MonitoringRemote.safeMessage(MonitoringRemoteError.http(403)).contains("Access denied"))
        XCTAssertThrowsError(try MonitoringRemote.parseAnthropic(usage: Data(repeating: 32, count: 1_000_001), cost: Data("{}".utf8)))
    }
}
