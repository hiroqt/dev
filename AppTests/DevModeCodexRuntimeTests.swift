import Foundation
import XCTest
@testable import dev

final class DevModeCodexRuntimeTests: XCTestCase {
    func testNativeCodeReviewUsesUncommittedChangesAndSelectedEffort() {
        XCTAssertEqual(DevModeCodeReview.arguments(model: "gpt-test", effort: "low"), ["-c", "model_reasoning_effort=\"low\"", "--model", "gpt-test", "review", "--uncommitted"])
        XCTAssertEqual(DevModeCodeReview.arguments(model: nil, effort: "max"), ["-c", "model_reasoning_effort=\"max\"", "review", "--uncommitted"])
        XCTAssertEqual(DevModeCodeReview.arguments(model: nil, effort: "low\"\npermissions=\"danger-full-access"), ["-c", "model_reasoning_effort=\"low\"", "review", "--uncommitted"])
    }

    func testThreadAndTurnRequestsCarryTaskSettings() throws {
        let start = try DevModeCodexProtocol.request(
            id: .integer(4),
            method: "thread/start",
            params: ["cwd": "/tmp/project", "model": "gpt-test", "modelReasoningEffort": "low", "approvalPolicy": "on-request", "sandbox": "workspace-write"]
        )
        let turn = try DevModeCodexProtocol.request(
            id: .integer(5),
            method: "turn/start",
            params: ["threadId": "thread-1", "input": [["type": "text", "text": "Fix the bug"]]]
        )

        let startMessage = try XCTUnwrap(json(start))
        XCTAssertEqual(startMessage["method"] as? String, "thread/start")
        XCTAssertEqual((startMessage["params"] as? [String: Any])?["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual((startMessage["params"] as? [String: Any])?["modelReasoningEffort"] as? String, "low")

        let turnMessage = try XCTUnwrap(json(turn))
        XCTAssertEqual(turnMessage["method"] as? String, "turn/start")
        let params = try XCTUnwrap(turnMessage["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(((params["input"] as? [[String: String]])?.first)?["text"], "Fix the bug")
    }

    func testResumeRequestReappliesSelectedPermissionAndModel() throws {
        let params = DevModeCodexProtocol.resumeParams(threadID: "thread-1", model: "gpt-test", reasoningEffort: "high", approvalPolicy: "on-request", sandbox: "read-only")

        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["model"] as? String, "gpt-test")
        XCTAssertEqual(params["modelReasoningEffort"] as? String, "high")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(params["sandbox"] as? String, "read-only")
    }

    func testTurnSuccessRequiresCompletedStatus() {
        XCTAssertTrue(DevModeCodexProtocol.isSuccessfulTurnStatus("completed"))
        XCTAssertFalse(DevModeCodexProtocol.isSuccessfulTurnStatus("failed"))
        XCTAssertFalse(DevModeCodexProtocol.isSuccessfulTurnStatus("interrupted"))
        XCTAssertFalse(DevModeCodexProtocol.isSuccessfulTurnStatus(nil))
    }

    func testProcessOutputRedactsCommonCredentialFormats() {
        let output = "Authorization: Bearer abc.def token=ghp_123456789012345678901234567890123456 sk-abcdefghijklmnopqrstuvwxyz012345"
        let redacted = DevModeProcessOutput.redact(output)

        XCTAssertFalse(redacted.contains("abc.def"))
        XCTAssertFalse(redacted.contains("ghp_123456789012345678901234567890123456"))
        XCTAssertFalse(redacted.contains("sk-abcdefghijklmnopqrstuvwxyz012345"))
        XCTAssertTrue(redacted.contains("[redacted]"))
    }

    func testApprovalServerRequestsAreDeliveredWithoutAutoApproval() throws {
        let raw = Data(#"{"id":22,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","command":["rm","-rf","target"],"cwd":"/tmp/project","reason":"cleanup"}}"#.utf8)

        guard case let .serverRequest(id, method, params) = DevModeCodexProtocol.frame(raw) else {
            return XCTFail("Expected an approval server request")
        }
        XCTAssertEqual(id, .integer(22))
        XCTAssertEqual(method, "item/commandExecution/requestApproval")
        XCTAssertEqual((try XCTUnwrap(json(params))["reason"] as? String), "cleanup")
    }

    func testApprovalAnswerSupportsExplicitAcceptDeclineAndCancel() throws {
        for decision in [DevModeCodexApprovalDecision.accept, .decline, .cancel] {
            let response = try DevModeCodexProtocol.approvalResponse(id: .integer(22), decision: decision)
            let message = try XCTUnwrap(json(response))
            XCTAssertEqual(message["id"] as? Int, 22)
            XCTAssertEqual((message["result"] as? [String: String])?["decision"], decision.rawValue)
        }
    }

    func testUnknownServerRequestCanBeRejectedAndIDsMayBeStrings() throws {
        let id = DevModeCodexRequestID.string("server-request-1")
        let rejection = try DevModeCodexProtocol.rejectUnsupportedRequest(id: id, method: "unknown/request")
        let message = try XCTUnwrap(json(rejection))
        XCTAssertEqual(message["id"] as? String, "server-request-1")
        XCTAssertEqual((message["error"] as? [String: Any])?["code"] as? Int, -32601)

        let raw = Data(#"{"id":"server-request-1","method":"item/fileChange/requestApproval","params":{"threadId":"thread-1"}}"#.utf8)
        guard case let .serverRequest(parsedID, method, _) = DevModeCodexProtocol.frame(raw) else {
            return XCTFail("Expected a file approval request")
        }
        XCTAssertEqual(parsedID, id)
        XCTAssertEqual(method, "item/fileChange/requestApproval")
    }

    func testMalformedFramesAreRejected() {
        XCTAssertNil(DevModeCodexProtocol.frame(Data("not-json".utf8)))
        XCTAssertNil(DevModeCodexProtocol.frame(Data(#"{"jsonrpc":"2.0"}"#.utf8)))
    }

    private func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
