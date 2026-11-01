import XCTest
@testable import dev

final class WorkspaceTypographyTests: XCTestCase {
    func testDetailsStayReadableAtEveryFontSetting() {
        for scale in [0.85, 1.0, 1.15, 1.3] {
            for size in [9.0, 10, 12, 13, 16, 26] {
                XCTAssertGreaterThanOrEqual(WorkspaceTypography.scaledSize(size, scale: scale), 12)
            }
        }
        XCTAssertEqual(WorkspaceTypography.scaledSize(10, scale: 1.15), 13.8, accuracy: 0.001)
        XCTAssertEqual(WorkspaceTypography.scaledSize(26, scale: 1), 26)
    }
}
