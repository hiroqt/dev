import Foundation

enum AntigravityUsageCLI {
    static func read(executable: URL) -> ProviderUsageSnapshot? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let usage = run(executable, ["-p", "/usage", "--output-format", "json"], directory: home) else { return nil }
        let credits = run(executable, ["-p", "/credits", "--output-format", "json"], directory: home)
        return ProviderUsageSnapshot.parseAntigravity(usage: usage, credits: credits)
    }

    private static func run(_ executable: URL, _ arguments: [String], directory: URL) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments + ["--print-timeout", "15s"]
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        guard (try? process.run()) != nil else { return nil }
        guard completed.wait(timeout: .now() + 20) == .success else {
            process.terminate()
            _ = completed.wait(timeout: .now() + 1)
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return data.count <= 256_000 ? data : nil
    }
}
