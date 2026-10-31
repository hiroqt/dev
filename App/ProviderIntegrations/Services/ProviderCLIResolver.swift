import Foundation

enum ProviderCLIResolver {
    static func executablePaths(in searchPaths: [URL], fileManager: FileManager = .default) -> [CodingProvider: URL] {
        Dictionary(uniqueKeysWithValues: CodingProvider.allCases.compactMap { provider in
            guard let executable = searchPaths
                .map({ $0.appending(path: provider.launchCommand) })
                .first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else { return nil }
            return (provider, executable)
        })
    }

    static func currentExecutablePaths() -> [CodingProvider: URL] {
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let commonPaths = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            home.appending(path: ".local/bin", directoryHint: .isDirectory),
            home.appending(path: ".npm-global/bin", directoryHint: .isDirectory),
            home.appending(path: ".claude/local", directoryHint: .isDirectory)
        ]
        return executablePaths(in: environmentPaths + commonPaths)
    }

    static func codexIsSignedIn(executable: URL) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["login", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        guard (try? process.run()) != nil else { return false }
        guard finished.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
