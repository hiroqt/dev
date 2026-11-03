import XCTest
@testable import dev

final class DevModeTests: XCTestCase {
    func testCodexPermissionModesUseExpectedSandboxAndApprovalFlags() {
        XCTAssertEqual(DevModePermission.fullAccess.codexArguments, ["--sandbox", "danger-full-access", "--ask-for-approval", "never"])
        XCTAssertEqual(DevModePermission.askApproval.codexArguments, ["--sandbox", "workspace-write", "--ask-for-approval", "on-request"])
        XCTAssertTrue(DevModePermission.askMe.codexArguments.isEmpty)
    }

    func testCodexOutputIsReducedToEventTypeBeforeDisplayOrPersistence() {
        XCTAssertEqual(CodexCLIEvent.summary(from: #"{"type":"item.completed","text":"secret source body"}"#), "Codex: item.completed")
        XCTAssertEqual(CodexCLIEvent.summary(from: "not json"), "Codex event received.")
    }

    func testCodexJSONLBufferKeepsPartialLinesUntilComplete() {
        let buffer = CodexJSONLLineBuffer()
        XCTAssertTrue(buffer.append(Data(#"{"type":"thread."#.utf8)).isEmpty)
        XCTAssertEqual(buffer.append(Data(#"started","thread_id":"abc"}"#.utf8) + Data([0x0A])), [#"{"type":"thread.started","thread_id":"abc"}"#])
        XCTAssertTrue(buffer.finish().isEmpty)
    }

    @MainActor
    func testConversationRenamePermissionAndDeletePersist() throws {
        let defaults = UserDefaults.standard
        let key = "devModeTasks"
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue { defaults.set(originalValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = LocalProject(id: UUID(), name: "Example", bookmark: Data([1]))
        let conversation = DevModeTask(title: "First title", goal: "Hello", project: project, projectURL: root, memoryURL: root.appending(path: "CONTEXT.md"), permission: .askApproval)
        defaults.set(try JSONEncoder().encode([conversation]), forKey: key)

        let store = DevModeStore()
        store.selectedTaskID = conversation.id
        store.renameConversation(conversation.id, title: "Renamed chat")
        store.setPermission(.fullAccess, for: conversation.id)

        let restored = try XCTUnwrap(DevModeStore().tasks.first)
        XCTAssertEqual(restored.title, "Renamed chat")
        XCTAssertEqual(restored.permission, .fullAccess)

        store.deleteConversation(conversation.id)
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNil(store.selectedTaskID)
        XCTAssertTrue(DevModeStore().tasks.isEmpty)
    }

    @MainActor
    func testProviderConsentPersistsPerCanonicalProjectPath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = UserDefaults.standard
        let key = "devModeConsentedProjects"
        let originalValue = defaults.object(forKey: key)
        defer { defaults.set(originalValue, forKey: key) }

        let store = DevModeStore()
        store.setConsent(true, for: root)

        XCTAssertTrue(DevModeStore().hasConsent(for: root.appending(path: ".")))
        store.setConsent(false, for: root)
        XCTAssertFalse(DevModeStore().hasConsent(for: root))
    }
}
