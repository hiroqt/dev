import XCTest
@testable import dev

final class ProviderIntegrationsTests: XCTestCase {
    @MainActor
    func testProviderAvailabilityAndCodexSignInUseInjectedChecks() async {
        let executable = URL(fileURLWithPath: "/example/codex")
        let store = ProviderIntegrationsStore(
            detectExecutables: { [.codex: executable, .claude: URL(fileURLWithPath: "/example/claude")] },
            checkCodexSignIn: { _ in true }
        )

        await store.refreshAvailability()
        await store.refreshCodexSignIn()

        XCTAssertEqual(store.executablePaths[.codex], executable)
        XCTAssertNotNil(store.executablePaths[.claude])
        XCTAssertEqual(store.codexSignInState, .connected)
    }

    func testProviderLaunchAndUsageCommandsAreProviderSpecific() {
        XCTAssertEqual(CodingProvider.allCases.map(\.launchCommand), ["codex", "agy", "claude"])
        XCTAssertEqual(CodingProvider.allCases.map(\.usageCommand), ["/status", "/usage", "/usage"])
    }

    func testAntigravityUsageParserReadsOnlyStructuredQuotaAndCreditFields() throws {
        let usage = Data(#"{"status":"SUCCESS","num_turns":0,"command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":73,"reset_time":"2026-10-31T20:00:00Z"},{"name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.41,"reset_time":"2026-11-01T00:00:00Z"}]}]}}}"#.utf8)
        let credits = Data(#"{"status":"SUCCESS","num_turns":0,"command":{"name":"credits","data":{"remaining_credits":12,"upgrade_uri":"https://example.test"}}}"#.utf8)

        let snapshot = try XCTUnwrap(ProviderUsageSnapshot.parseAntigravity(usage: usage, credits: credits))

        XCTAssertEqual(snapshot.groups.first?.name, "Gemini Models")
        XCTAssertEqual(snapshot.groups.first?.buckets.map(\.window), [.fiveHour, .weekly])
        XCTAssertEqual(snapshot.groups.first?.buckets.map(\.remainingPercent), [73, 41])
        XCTAssertEqual(snapshot.credits, "12")

        let withoutCredits = try XCTUnwrap(ProviderUsageSnapshot.parseAntigravity(usage: usage, credits: nil))
        XCTAssertEqual(withoutCredits.groups, snapshot.groups)
        XCTAssertNil(withoutCredits.credits)
    }

    func testCodexParserUsesStructuredWindowDurationsAndDetectsPlanAndCredits() throws {
        let response = Data(#"{"id":2,"result":{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1793450000},"secondary":{"usedPercent":62,"windowDurationMins":300,"resetsAt":1793440000},"credits":{"hasCredits":true,"unlimited":false,"balance":"12.50"}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"plus","primary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1793450000},"secondary":{"usedPercent":62,"windowDurationMins":300,"resetsAt":1793440000},"credits":{"hasCredits":true,"unlimited":false,"balance":"12.50"}}}}}"#.utf8)

        let snapshot = try XCTUnwrap(ProviderUsageSnapshot.parseCodexRateLimits(response))

        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.groups.first?.buckets.map(\.window), [.weekly, .fiveHour])
        XCTAssertEqual(snapshot.groups.first?.buckets.map(\.remainingPercent), [65, 38])
        XCTAssertEqual(snapshot.credits, "12.50")
    }

    func testCodexParserIgnoresUnsupportedWindowsAndMalformedUsage() throws {
        let response = Data(#"{"result":{"rateLimits":{"limitId":"codex","planType":"pro","primary":{"usedPercent":15,"windowDurationMins":60},"secondary":{"usedPercent":120,"windowDurationMins":300}}}}"#.utf8)

        let snapshot = try XCTUnwrap(ProviderUsageSnapshot.parseCodexRateLimits(response))

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertTrue(snapshot.groups.isEmpty)
        XCTAssertNil(ProviderUsageSnapshot.parseCodexRateLimits(Data("{}".utf8)))
    }

    func testCodexUsageCommandDetectorRefreshesOnlyForExactSlashCommands() {
        var detector = CodexUsageCommandDetector()
        XCTAssertFalse(detector.consume(Array("hello /status\r".utf8)[...]))
        XCTAssertFalse(detector.consume(Array("/sta".utf8)[...]))
        XCTAssertFalse(detector.consume(Array("tus".utf8)[...]))
        XCTAssertTrue(detector.consume(Array("\r".utf8)[...]))
        XCTAssertFalse(detector.consume(Array("/status-extra\r".utf8)[...]))
        XCTAssertTrue(detector.consume(Array("/usage\r".utf8)[...]))
    }

    func testCodexAppServerAdapterPerformsStructuredReadWithInjectedCLI() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("Python 3 is unavailable for the local JSON-RPC test executable")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeCLI = root.appending(path: "codex")
        let script = #"""
        #!/usr/bin/python3
        import json
        import sys

        for line in sys.stdin:
            request = json.loads(line)
            if request.get("method") == "initialize":
                print(json.dumps({"id": request["id"], "result": {}}), flush=True)
            elif request.get("method") == "account/rateLimits/read":
                print(json.dumps({"id": request["id"], "result": {"rateLimits": {"limitId": "codex", "planType": "plus", "primary": {"usedPercent": 20, "windowDurationMins": 300}}}}), flush=True)
        """#
        try Data(script.utf8).write(to: fakeCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)

        let snapshot = try XCTUnwrap(CodexAppServerUsageCLI.read(executable: fakeCLI))

        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.groups.first?.buckets.first?.window, .fiveHour)
        XCTAssertEqual(snapshot.groups.first?.buckets.first?.remainingPercent, 80)
    }

    func testAntigravityUsageParserRejectsAgentTurnsAndMalformedValues() {
        let agentTurn = Data(#"{"status":"SUCCESS","num_turns":1,"command":{"name":"usage","data":{"groups":[]}}}"#.utf8)
        XCTAssertNil(ProviderUsageSnapshot.parseAntigravity(usage: agentTurn, credits: Data("{}".utf8)))

        let invalidQuota = Data(#"{"status":"SUCCESS","num_turns":0,"command":{"name":"usage","data":{"groups":[{"name":"Models","buckets":[{"name":"Five Hour","window":"5h","remaining_fraction":101}]}]}}}"#.utf8)
        XCTAssertNil(ProviderUsageSnapshot.parseAntigravity(usage: invalidQuota, credits: Data("{}".utf8)))
    }

    func testProviderPreferencesDefaultCodexOnAndOtherProvidersOff() {
        let suiteName = "ProviderIntegrationsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(ProviderIntegrationPreferences.isEnabled(.codex, defaults: defaults))
        XCTAssertFalse(ProviderIntegrationPreferences.isEnabled(.antigravity, defaults: defaults))
        XCTAssertFalse(ProviderIntegrationPreferences.isEnabled(.claude, defaults: defaults))

        defaults.set(false, forKey: ProviderIntegrationPreferences.globalKey(.codex))
        defaults.set(true, forKey: ProviderIntegrationPreferences.globalKey(.claude))
        XCTAssertFalse(ProviderIntegrationPreferences.isEnabled(.codex, defaults: defaults))
        XCTAssertTrue(ProviderIntegrationPreferences.isEnabled(.claude, defaults: defaults))
    }

    func testProjectProviderPreferenceDefaultsOnAndPersistsPerProject() {
        let suiteName = "ProviderIntegrationsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(ProviderIntegrationPreferences.isEnabled(.claude, projectID: "local-1", defaults: defaults))
        defaults.set(false, forKey: ProviderIntegrationPreferences.projectKey(.claude, projectID: "local-1"))

        XCTAssertFalse(ProviderIntegrationPreferences.isEnabled(.claude, projectID: "local-1", defaults: defaults))
        XCTAssertTrue(ProviderIntegrationPreferences.isEnabled(.claude, projectID: "local-2", defaults: defaults))
    }

    func testExecutableDetectionUsesOnlyExecutableCommandsInSearchPaths() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = bin.appending(path: "codex")
        let claude = bin.appending(path: "claude")
        FileManager.default.createFile(atPath: codex.path, contents: Data())
        FileManager.default.createFile(atPath: claude.path, contents: Data())
        try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codex.path)
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claude.path)

        let found = ProviderCLIResolver.executablePaths(in: [bin])

        XCTAssertEqual(found[.codex], codex)
        XCTAssertNil(found[.claude])
        XCTAssertNil(found[.antigravity])
    }
}
