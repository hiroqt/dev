import XCTest
@testable import dev

final class DeploymentInsightsTests: XCTestCase {
    func testBranchesKeepNewestPerNamedBranchAndSortStably() {
        let branches = latestDeploymentBranches([
            release("old", branch: "main", date: 1), release("new", branch: "main", date: 3),
            release("other", branch: "feature", date: 2), release("none", branch: nil, date: 9),
            release("blank", branch: "  ", date: 10)
        ])
        XCTAssertEqual(branches.map(\.id), ["new", "other"])
    }

    private func release(_ id: String, branch: String?, date: Double) -> VercelDeployment {
        .init(id: id, state: "READY", target: "production", createdAt: Date(timeIntervalSince1970: date), url: nil, detail: "", branch: branch)
    }
}
