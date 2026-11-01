import XCTest
@testable import dev

final class ComputerStorageTests: XCTestCase {
    func testDataAttributionRejectsTraversalIdentifiers() {
        let root = URL(fileURLWithPath: "/tmp/storage")
        for identifier in ["", ".", "..", "../secret", "a/b", "a\\b"] {
            XCTAssertNil(AppStorageScanner.dataDirectory(bundleID: identifier, under: root))
        }
        XCTAssertEqual(AppStorageScanner.dataDirectory(bundleID: "com.example.app", under: root)?.path, "/tmp/storage/com.example.app")
    }

    func testMissingDirectoryIsNotAnInaccessibleScan() {
        var budget = AppStorageScanner.Budget()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(AppStorageScanner.allocatedBytes(at: missing, budget: &budget), 0)
        XCTAssertFalse(budget.partial)
    }

    func testAllocatedScanSkipsSymlinkAndHonorsEntryLimit() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let actual = root.appendingPathComponent("payload")
        try Data(repeating: 1, count: 100_000).write(to: actual)
        let link = root.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: actual)
        var directBudget = AppStorageScanner.Budget()
        XCTAssertEqual(AppStorageScanner.allocatedBytes(at: link, budget: &directBudget), 0)
        let values = try actual.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        let expected = try XCTUnwrap(values.totalFileAllocatedSize ?? values.fileAllocatedSize)
        var budget = AppStorageScanner.Budget()
        XCTAssertEqual(AppStorageScanner.allocatedBytes(at: root, budget: &budget), Int64(expected))
        var exhausted = AppStorageScanner.Budget(remaining: 0)
        XCTAssertEqual(AppStorageScanner.allocatedBytes(at: root, budget: &exhausted), 0)
        XCTAssertTrue(exhausted.partial)
    }
}
