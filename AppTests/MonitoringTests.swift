import XCTest
@testable import dev

final class MonitoringTests: XCTestCase {
    func testNativeSystemSamplerReturnsPlausibleCounters() throws {
        let counters = try XCTUnwrap(SystemCounters.read())
        XCTAssertGreaterThan(counters.memoryTotal, 0)
        XCTAssertGreaterThanOrEqual(counters.memoryUsed, 0)
        XCTAssertLessThanOrEqual(counters.memoryUsed, counters.memoryTotal)
        XCTAssertGreaterThanOrEqual(counters.cpuTotal, counters.cpuBusy)
        XCTAssertGreaterThan(counters.diskFree, 0)
    }

    func testCounterResetsAndSleepAreNotNetworkSpikes() {
        XCTAssertNil(MonitoringSample.rate(10, 100, elapsed: 5))
        XCTAssertNil(MonitoringSample.rate(100, 10, elapsed: 0))
        XCTAssertEqual(MonitoringSample.rate(110, 10, elapsed: 5), 20)
        let first = counters(date: Date(timeIntervalSince1970: 100), busy: 10, total: 20, bytes: 100)
        let later = counters(date: Date(timeIntervalSince1970: 105), busy: 20, total: 40, bytes: 200)
        let sample = MonitoringSample(current: later, previous: first)
        XCTAssertEqual(sample.cpuPercent, 50)
        XCTAssertEqual(sample.download, 20)
        let afterSleep = counters(date: Date(timeIntervalSince1970: 500), busy: 30, total: 60, bytes: 500)
        XCTAssertNil(MonitoringSample(current: afterSleep, previous: later).download)
        XCTAssertNil(MonitoringSample(current: first, previous: nil).cpuPercent)
    }

    @MainActor
    func testUptimeTargetsRequireExplicitCredentialFreeHTTPS() {
        XCTAssertNotNil(MonitoringStore.uptimeURL(" https://example.com/health "))
        for input in ["http://example.com", "https://user:secret@example.com", "file:///tmp/test", "https://example.com?token=secret", "https://example.com#secret", "https://"] {
            XCTAssertNil(MonitoringStore.uptimeURL(input), input)
        }
    }

    func testUptimeDistinguishesServerFailuresFromSuccess() {
        XCTAssertTrue(UptimeObservation(targetID: UUID(), date: .now, status: 204, milliseconds: 12).healthy)
        XCTAssertFalse(UptimeObservation(targetID: UUID(), date: .now, status: 503, milliseconds: 12).healthy)
        XCTAssertFalse(UptimeObservation(targetID: UUID(), date: .now, status: nil, milliseconds: nil).healthy)
    }

    func testHistoryPrunesOldDataAndRejectsOlderWrites() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let old = counters(date: now.addingTimeInterval(-8 * 86_400), busy: 1, total: 2, bytes: 1)
        let recent = counters(date: now, busy: 2, total: 4, bytes: 2)
        var history = MonitoringHistory(samples: [MonitoringSample(current: old, previous: nil), MonitoringSample(current: recent, previous: nil)])
        history.prune(now: now)
        XCTAssertEqual(history.samples.map(\.date), [now])
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "history.json")
        let writer = MonitoringHistoryWriter()
        try await writer.save(history, to: file, revision: 2)
        try await writer.save(MonitoringHistory(), to: file, revision: 1)
        let saved = try JSONDecoder().decode(MonitoringHistory.self, from: Data(contentsOf: file))
        XCTAssertEqual(saved.samples.count, 1)
    }

    private func counters(date: Date, busy: UInt64, total: UInt64, bytes: UInt64) -> SystemCounters {
        SystemCounters(date: date, memoryUsed: 100, memoryTotal: 200, swapUsed: 0, diskFree: 1_000, cpuBusy: busy, cpuTotal: total, received: bytes, sent: bytes)
    }
}
