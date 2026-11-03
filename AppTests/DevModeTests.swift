import XCTest
@testable import dev

final class DevModeTests: XCTestCase {
    func testSlashCommandSuggestionsFilterWhileTyping() {
        XCTAssertEqual(CodexSlashCommands.matches("/he").first, "/help")
        XCTAssertEqual(CodexSlashCommands.matches("/sta"), ["/status", "/statusline"])
        XCTAssertEqual(CodexSlashCommands.matches("/comp"), ["/compact"])
        XCTAssertEqual(CodexSlashCommands.matches("/sttaus"), ["/status"])
        XCTAssertTrue(CodexSlashCommands.matches("hello").isEmpty)
        XCTAssertTrue(CodexSlashCommands.matches("/unknown").isEmpty)
    }

    func testModelCatalogUsesVisibleModelsOnly() {
        let response = Data(#"{"result":{"data":[{"model":"gpt-a","displayName":"GPT A","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"}]},{"model":"gpt-b","displayName":"GPT B","hidden":true}]}}"#.utf8)
        XCTAssertEqual(CodexAppServerUsageCLI.parseModels(response)?.map { $0.id }, ["gpt-a"])
        XCTAssertEqual(CodexAppServerUsageCLI.parseModels(response)?.first?.efforts, ["low", "high"])
    }

    @MainActor
    func testSlashCommandStaysInConversationWithoutStartingExec() throws {
        let defaults = UserDefaults.standard
        let key = "devModeTasks"
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue { defaults.set(originalValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let project = LocalProject(id: UUID(), name: "Example", bookmark: Data([1]))
        let root = FileManager.default.temporaryDirectory
        let memory = root.appending(path: "CONTEXT.md")
        let task = DevModeTask(title: "Question", goal: "Question", project: project, projectURL: root, memoryURL: memory, permission: .askApproval)
        defaults.set(try JSONEncoder().encode([task]), forKey: key)

        let store = DevModeStore()
        XCTAssertEqual(store.recordSlashCommand("/status", to: task), task.id)
        XCTAssertEqual(store.selectedTask?.messages.map(\.content), ["Question", "/status"])
        XCTAssertEqual(store.selectedTask?.status, .queued)
        store.appendCommandResult("Choose a model", to: task.id, kind: "model", options: [.init(id: "gpt-a", title: "GPT A", efforts: ["low", "high"])])
        let messageID = try XCTUnwrap(store.selectedTask?.messages.last?.id)
        store.selectModel("unknown", for: task.id, messageID: messageID)
        XCTAssertNil(store.selectedTask?.model)
        store.selectModel("gpt-a", for: task.id, messageID: messageID)
        XCTAssertNil(store.selectedTask?.model)
        XCTAssertEqual(store.selectedTask?.messages.last?.commandKind, "effort")
        store.selectModelEffort("invalid", for: task.id, messageID: messageID)
        XCTAssertNil(store.selectedTask?.modelEffort)
        store.selectModelEffort("high", for: task.id, messageID: messageID)
        XCTAssertEqual(DevModeStore().selectedTask?.model, "gpt-a")
        XCTAssertEqual(DevModeStore().selectedTask?.modelEffort, "high")
        XCTAssertEqual(store.selectedTask?.messages.last?.commandKind, "notice")
        XCTAssertNil(store.selectedTask?.messages.last?.commandOptions)
        XCTAssertEqual(store.selectedTask?.messages.last?.content, "You're using **GPT A** with **high** effort. Use `/model` to change it.")
        XCTAssertFalse(store.selectedTask?.messages.contains(where: { $0.id == messageID }) ?? true)
        store.appendCommandResult("Choose a model", to: task.id, kind: "model", options: [.init(id: "gpt-b", title: "GPT B", efforts: ["medium"])])
        let changeID = try XCTUnwrap(store.selectedTask?.messages.last?.id)
        store.selectModel("gpt-b", for: task.id, messageID: changeID)
        XCTAssertEqual(store.selectedTask?.model, "gpt-a")
        store.selectModelEffort("medium", for: task.id, messageID: changeID)
        XCTAssertEqual(store.selectedTask?.model, "gpt-b")
        XCTAssertEqual(store.selectedTask?.modelEffort, "medium")
    }

    func testCodexPermissionModesUseExpectedSandboxAndApprovalFlags() {
        XCTAssertEqual(DevModePermission.fullAccess.codexArguments, ["--sandbox", "danger-full-access", "--ask-for-approval", "never"])
        XCTAssertEqual(DevModePermission.askApproval.codexArguments, ["--sandbox", "workspace-write", "--ask-for-approval", "on-request"])
        XCTAssertTrue(DevModePermission.askMe.codexArguments.isEmpty)
    }

    @MainActor
    func testCodexShowsOneFinalReplyAfterInterimMessages() throws {
        let defaults = UserDefaults.standard
        let key = "devModeTasks"
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue { defaults.set(originalValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = LocalProject(id: UUID(), name: "Example", bookmark: Data([1]))
        let conversation = DevModeTask(title: "Question", goal: "Question", project: project, projectURL: root, memoryURL: root.appending(path: "CONTEXT.md"), permission: .askApproval)
        defaults.set(try JSONEncoder().encode([conversation]), forKey: key)

        let store = DevModeStore()
        store.receiveCodexEvent(#"{"type":"item.completed","item":{"type":"agent_message","text":"I read the README."}}"#, for: conversation.id)
        XCTAssertEqual(store.tasks[0].messages.count, 1)
        XCTAssertEqual(store.activityText[conversation.id], "I read the README.")
        store.receiveCodexEvent(#"{"type":"item.completed","item":{"type":"agent_message","text":"The project is a SwiftUI app."}}"#, for: conversation.id)
        XCTAssertEqual(store.tasks[0].messages.count, 1)
        store.receiveCodexEvent(#"{"type":"turn.completed"}"#, for: conversation.id)
        XCTAssertEqual(store.tasks[0].messages.map(\.content), ["Question", "The project is a SwiftUI app."])
        XCTAssertNil(store.activityText[conversation.id])
        XCTAssertEqual(DevModeStore().tasks[0].messages.count, 2)

        defaults.set(try JSONEncoder().encode([conversation]), forKey: key)
        let failedStore = DevModeStore()
        failedStore.receiveCodexEvent(#"{"type":"item.completed","item":{"type":"agent_message","text":"I read the README."}}"#, for: conversation.id)
        failedStore.receiveCodexEvent(#"{"type":"turn.failed"}"#, for: conversation.id)
        XCTAssertEqual(failedStore.tasks[0].messages.count, 1)
        XCTAssertNil(failedStore.activityText[conversation.id])

        defaults.set(try JSONEncoder().encode([conversation]), forKey: key)
        let unconfirmedStore = DevModeStore()
        unconfirmedStore.receiveCodexEvent(#"{"type":"item.completed","item":{"type":"agent_message","text":"I read the README."}}"#, for: conversation.id)
        unconfirmedStore.finish(conversation.id, status: .completed)
        XCTAssertEqual(unconfirmedStore.tasks[0].messages.count, 1)
        XCTAssertEqual(unconfirmedStore.tasks[0].status, .interrupted)
        unconfirmedStore.receiveCodexEvent(#"{"type":"turn.completed"}"#, for: conversation.id)
        XCTAssertEqual(unconfirmedStore.tasks[0].messages.map(\.content), ["Question", "I read the README."])
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
