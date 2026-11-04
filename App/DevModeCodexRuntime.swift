import CoreFoundation
import Foundation

enum DevModeCodexRequestID: Hashable, Sendable {
    case integer(Int)
    case string(String)

    fileprivate var jsonValue: Any {
        switch self {
        case .integer(let value): value
        case .string(let value): value
        }
    }
}

enum DevModeCodexFrame: Equatable, Sendable {
    case response(id: DevModeCodexRequestID, result: Data)
    case failure(id: DevModeCodexRequestID?, code: Int?, message: String)
    case notification(method: String, params: Data)
    case serverRequest(id: DevModeCodexRequestID, method: String, params: Data)
}

enum DevModeCodexApprovalDecision: String, Sendable {
    case accept
    case decline
    case cancel
}

enum DevModeCodexProtocol {
    static func isSuccessfulTurnStatus(_ status: String?) -> Bool { status == "completed" }

    static func request(id: DevModeCodexRequestID, method: String, params: [String: Any]) throws -> Data {
        try encode(["id": id.jsonValue, "method": method, "params": params])
    }

    static func notification(method: String, params: [String: Any] = [:]) throws -> Data {
        try encode(["method": method, "params": params])
    }

    static func approvalResponse(id: DevModeCodexRequestID, decision: DevModeCodexApprovalDecision) throws -> Data {
        try encode(["id": id.jsonValue, "result": ["decision": decision.rawValue]])
    }

    static func resumeParams(threadID: String, model: String?, reasoningEffort: String, approvalPolicy: String, sandbox: String) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": threadID,
            "modelReasoningEffort": reasoningEffort,
            "approvalPolicy": approvalPolicy,
            "sandbox": sandbox
        ]
        if let model { params["model"] = model }
        return params
    }

    static func rejectUnsupportedRequest(id: DevModeCodexRequestID, method: String) throws -> Data {
        try encode(["id": id.jsonValue, "error": ["code": -32601, "message": "Unsupported Codex app-server request: \(method)"]])
    }

    static func frame(_ line: Data) -> DevModeCodexFrame? {
        guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let id = requestID(value["id"])
        if let error = value["error"] as? [String: Any] {
            return .failure(id: id, code: error["code"] as? Int, message: error["message"] as? String ?? "Codex app-server request failed.")
        }
        if let id {
            if let method = value["method"] as? String {
                return .serverRequest(id: id, method: method, params: data(value["params"]))
            }
            if let result = value["result"] { return .response(id: id, result: data(result)) }
            return .failure(id: id, code: nil, message: "Codex app-server returned an invalid response.")
        }
        guard let method = value["method"] as? String else { return nil }
        return .notification(method: method, params: data(value["params"]))
    }

    private static func requestID(_ value: Any?) -> DevModeCodexRequestID? {
        if let value = value as? String { return .string(value) }
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return .integer(value.intValue) }
        return nil
    }

    private static func data(_ value: Any?) -> Data {
        guard let value, let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else {
            return Data("{}".utf8)
        }
        return encoded
    }

    private static func encode(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value) + Data([0x0A])
    }
}

enum DevModeCodeReview {
    static func arguments(model: String?, effort: String) -> [String] {
        let effort = DevModeReasoningMode.resolve(effort).rawValue
        var arguments = ["-c", "model_reasoning_effort=\"\(effort)\""]
        if let model { arguments += ["--model", model] }
        return arguments + ["review", "--uncommitted"]
    }
}

@MainActor
final class DevModeCodexRuntime {
    enum Event {
        case frame(DevModeCodexFrame)
        case protocolError(String)
        case requestTimedOut(DevModeCodexRequestID)
        case terminated(Int32)
    }

    private static let maximumLineBytes = 1_048_576
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var pending = Data()
    private var requestTimeoutTasks: [DevModeCodexRequestID: Task<Void, Never>] = [:]
    private(set) var isRunning = false
    var requestTimeout: TimeInterval = 60
    var onEvent: ((Event) -> Void)?

    func start(executable: URL, currentDirectory: URL) throws {
        guard !isRunning else { return }
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = currentDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.isRunning = false
                self?.onEvent?(.terminated(process.terminationStatus))
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        try process.run()
        isRunning = true
    }

    func initialize(requestID: Int = 1, clientVersion: String = "1.0") throws {
        try sendRequest(
            id: .integer(requestID),
            method: "initialize",
            params: ["clientInfo": ["name": "dev", "title": "dev", "version": clientVersion]]
        )
    }

    func sendInitialized() throws {
        try send(DevModeCodexProtocol.notification(method: "initialized"))
    }

    func sendRequest(id: DevModeCodexRequestID, method: String, params: [String: Any]) throws {
        try send(DevModeCodexProtocol.request(id: id, method: method, params: params))
        requestTimeoutTasks[id]?.cancel()
        requestTimeoutTasks[id] = Task { [weak self, requestTimeout] in
            guard requestTimeout > 0 else { return }
            try? await Task.sleep(for: .seconds(requestTimeout))
            guard !Task.isCancelled else { return }
            self?.requestTimeoutTasks[id] = nil
            self?.onEvent?(.requestTimedOut(id))
        }
    }

    func startThread(id: Int, cwd: URL, model: String? = nil, reasoningEffort: String? = nil, approvalPolicy: String, sandbox: String) throws {
        var params: [String: Any] = ["cwd": cwd.path, "approvalPolicy": approvalPolicy, "sandbox": sandbox]
        if let model { params["model"] = model }
        if let reasoningEffort { params["modelReasoningEffort"] = reasoningEffort }
        try sendRequest(id: .integer(id), method: "thread/start", params: params)
    }

    func resumeThread(id: Int, threadID: String, model: String?, reasoningEffort: String, approvalPolicy: String, sandbox: String) throws {
        let params = DevModeCodexProtocol.resumeParams(threadID: threadID, model: model, reasoningEffort: reasoningEffort, approvalPolicy: approvalPolicy, sandbox: sandbox)
        try sendRequest(id: .integer(id), method: "thread/resume", params: params)
    }

    func startTurn(id: Int, threadID: String, prompt: String, reasoningEffort: String? = nil) throws {
        var params: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": prompt]]]
        if let reasoningEffort { params["modelReasoningEffort"] = reasoningEffort }
        try sendRequest(id: .integer(id), method: "turn/start", params: params)
    }

    func answerApproval(id: DevModeCodexRequestID, decision: DevModeCodexApprovalDecision) throws {
        try send(DevModeCodexProtocol.approvalResponse(id: id, decision: decision))
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        requestTimeoutTasks.values.forEach { $0.cancel() }
        requestTimeoutTasks.removeAll()
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        isRunning = false
    }

    private func send(_ data: Data) throws {
        guard isRunning else { throw CocoaError(.fileWriteUnknown) }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let frame = DevModeCodexProtocol.frame(line) else {
                onEvent?(.protocolError("Codex app-server sent an invalid JSON-RPC frame."))
                continue
            }
            if case let .response(id, _) = frame {
                requestTimeoutTasks[id]?.cancel()
                requestTimeoutTasks[id] = nil
            } else if case let .failure(id?, _, _) = frame {
                requestTimeoutTasks[id]?.cancel()
                requestTimeoutTasks[id] = nil
            }
            if case let .serverRequest(id, method, _) = frame,
               !["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method) {
                try? send(DevModeCodexProtocol.rejectUnsupportedRequest(id: id, method: method))
            }
            onEvent?(.frame(frame))
        }
        guard pending.count <= Self.maximumLineBytes else {
            pending.removeAll(keepingCapacity: false)
            onEvent?(.protocolError("Codex app-server sent a JSON-RPC line larger than 1 MB."))
            stop()
            return
        }
    }
}

enum DevModeProcessOutput {
    static func redact(_ text: String) -> String {
        let patterns = [
            #"(?i)(authorization\s*:\s*bearer\s+)[^\s,;]+"#,
            #"(?i)(\b)(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})\b"#,
            #"(?i)(\b(?:token|api[_-]?key|secret|password)\s*[:=]\s*)[\"']?[^\s,;\"']+"#
        ]
        return patterns.reduce(text) { value, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
            let range = NSRange(value.startIndex..., in: value)
            return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "$1[redacted]")
        }
    }
}
