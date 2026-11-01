import XCTest
@testable import dev
final class BatteryHistoryTests: XCTestCase {
    func testScreenTimeExcludesUnknownSleepAndClosedIntervals() {
        let now = Date.now
        XCTAssertEqual(BatteryHistoryMath.screenSeconds(previous: nil, now: now, awake: true), 0)
        XCTAssertEqual(BatteryHistoryMath.screenSeconds(previous: now.addingTimeInterval(-600), now: now, awake: true), 0)
        XCTAssertEqual(BatteryHistoryMath.screenSeconds(previous: now.addingTimeInterval(-60), now: now, awake: false), 0)
        XCTAssertEqual(BatteryHistoryMath.screenSeconds(previous: now.addingTimeInterval(-60), now: now, awake: true), 60)
    }
}
