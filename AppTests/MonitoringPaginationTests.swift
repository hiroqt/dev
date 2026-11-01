import XCTest
@testable import dev

final class MonitoringPaginationTests: XCTestCase {
    func testEmptyAndOutOfRangePagesAreSafe() {
        let empty = MonitoringPagination(total: 0, page: 4, pageSize: 6)
        XCTAssertEqual(empty.page, 0)
        XCTAssertEqual(empty.range, 0..<0)
        XCTAssertEqual(empty.summary, "0 results")
        let shrunk = MonitoringPagination(total: 7, page: 9, pageSize: 6)
        XCTAssertEqual(shrunk.page, 1)
        XCTAssertEqual(shrunk.range, 6..<7)
        XCTAssertEqual(shrunk.summary, "7–7 of 7")
    }

    func testPagesCoverRecordsExactlyOnceAndKeepPartialLastPage() {
        let ranges = (0..<3).flatMap { Array(MonitoringPagination(total: 13, page: $0, pageSize: 6).range) }
        XCTAssertEqual(ranges, Array(0..<13))
        XCTAssertEqual(MonitoringPagination(total: 20, page: 3, pageSize: 5).range, 15..<20)
        XCTAssertEqual(MonitoringPagination(total: 40, page: 4, pageSize: 5).range, 20..<25)
    }

    func testLoadingOlderRecordsFillsPartialPagesBeforeAdvancing() {
        let partial = MonitoringPagination(total: 7, page: 1, pageSize: 5)
        XCTAssertEqual(partial.pageAfterLoading, 1)
        let filled = MonitoringPagination(total: 27, page: partial.pageAfterLoading, pageSize: 5)
        XCTAssertEqual(filled.range, 5..<10)
        let full = MonitoringPagination(total: 20, page: 3, pageSize: 5)
        XCTAssertEqual(full.pageAfterLoading, 4)
        XCTAssertEqual(MonitoringPagination(total: 21, page: full.pageAfterLoading, pageSize: 5).range, 20..<21)
    }

    func testInvalidArgumentsAndExactPageBoundary() {
        let invalid = MonitoringPagination(total: -1, page: -1, pageSize: 0)
        XCTAssertEqual(invalid.range, 0..<0)
        XCTAssertEqual(MonitoringPagination(total: 12, page: 2, pageSize: 6).page, 1)
        XCTAssertEqual(MonitoringPagination(total: 12, page: 1, pageSize: 6).pageCount, 2)
    }
}
