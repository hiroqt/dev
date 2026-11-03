import Foundation

enum CodexAppServerUsageCLI {
    static func read(executable: URL) -> ProviderUsageSnapshot? {
        guard let response = request(executable: executable, method: "account/rateLimits/read") else { return nil }
        return ProviderUsageSnapshot.parseCodexRateLimits(response)
    }

    static func models(executable: URL) -> [(id: String, name: String, efforts: [String])]? {
        guard let response = request(executable: executable, method: "model/list", params: ["limit": 100]) else { return nil }
        return parseModels(response)
    }

    static func parseModels(_ response: Data) -> [(id: String, name: String, efforts: [String])]? {
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let models = result["data"] as? [[String: Any]] else { return nil }
        return models.compactMap { model in
            guard model["hidden"] as? Bool != true,
                  let id = model["model"] as? String,
                  let name = model["displayName"] as? String else { return nil }
            let efforts = (model["supportedReasoningEfforts"] as? [[String: Any]])?
                .compactMap { $0["reasoningEffort"] as? String }
                .filter { $0.range(of: "^[a-z][a-z0-9_-]*$", options: .regularExpression) != nil } ?? []
            return (id, name, efforts)
        }
    }

    private static func request(executable: URL, method: String, params: [String: Any] = [:]) -> Data? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let terminated = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in terminated.signal() }

        guard (try? process.run()) != nil else { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            _ = terminated.wait(timeout: .now() + 1)
        }

        let reader = JSONRPCLineReader(handle: output.fileHandleForReading)
        let initialize: [String: Any] = [
            "method": "initialize",
            "id": 1,
            "params": ["clientInfo": ["name": "dev", "title": "dev", "version": "1.0"]]
        ]
        guard
            write(initialize, to: input.fileHandleForWriting),
            let initializeResponse = reader.response(id: 1),
            hasResult(initializeResponse)
        else { return nil }

        let initialized: [String: Any] = ["method": "initialized", "params": [:] as [String: Any]]
        let request: [String: Any] = ["method": method, "id": 2, "params": params]
        guard
            write(initialized, to: input.fileHandleForWriting),
            write(request, to: input.fileHandleForWriting),
            let response = reader.response(id: 2)
        else { return nil }

        return response
    }

    private static func write(_ message: [String: Any], to handle: FileHandle) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return false }
        do {
            try handle.write(contentsOf: data + Data([0x0A]))
            return true
        } catch {
            return false
        }
    }

    private static func hasResult(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["result"] != nil && object["error"] == nil
    }
}

private final class JSONRPCLineReader {
    private let handle: FileHandle
    private var pending = Data()
    private var totalBytes = 0

    init(handle: FileHandle) { self.handle = handle }

    func response(id expectedID: Int) -> Data? {
        while totalBytes <= 256_000 {
            if let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let responseID = object["id"] as? Int
                else { continue }
                if responseID == expectedID {
                    return object["error"] == nil ? line : nil
                }
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return nil }
            totalBytes += chunk.count
            pending.append(chunk)
        }
        return nil
    }
}
