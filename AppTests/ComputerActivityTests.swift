import XCTest
@testable import dev

final class ComputerActivityTests: XCTestCase {
    func testProcessSnapshotParsesNamesWithoutArgumentsAndConvertsResidentMemory() {
        let rows = ComputerProcess.parse(" 42 125.5 2048 /Applications/My App.app/Contents/MacOS/My App\n 5 0.0 0 /sbin/launchd\n")
        XCTAssertEqual(rows.map(\.id), [42, 5])
        XCTAssertEqual(rows.first?.name, "My App")
        XCTAssertEqual(rows.first?.cpu, 125.5)
        XCTAssertEqual(rows.first?.memory, 2_097_152)
    }

    func testMalformedProcessCountersAreExcluded() {
        let output = "1 nan 3 /bad\n2 -1 3 /bad\n3 1 -4 /bad\n4 0 9223372036854775807 /bad\n0 0 3 /bad\n2147483648 0 3 /bad\nincomplete"
        XCTAssertTrue(ComputerProcess.parse(output).isEmpty)
    }
}
