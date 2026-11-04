import Foundation

enum DevModeGitWorktree {
    enum Failure: LocalizedError {
        case projectIsNotGit
        case destinationInsideRepository
        case invalidBranch
        case destinationExists
        case git(String)

        var errorDescription: String? {
            switch self {
            case .projectIsNotGit: "Choose a Git project to create a worktree."
            case .destinationInsideRepository: "Choose a destination outside the existing repository so the original working tree stays clean."
            case .invalidBranch: "Enter a valid new Git branch name."
            case .destinationExists: "The chosen worktree folder already exists. Choose another parent folder or branch name."
            case .git(let message): message.isEmpty ? "Git could not create the worktree." : message
            }
        }
    }

    static func create(project: URL, parent: URL, branch: String) throws -> URL {
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { throw Failure.invalidBranch }
        let parentAccess = parent.startAccessingSecurityScopedResource()
        let projectAccess = project.startAccessingSecurityScopedResource()
        defer {
            if projectAccess { project.stopAccessingSecurityScopedResource() }
            if parentAccess { parent.stopAccessingSecurityScopedResource() }
        }
        let destination = parent.appending(path: "\(project.lastPathComponent)-\(branch.replacingOccurrences(of: "/", with: "-"))", directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.destinationExists }
        guard let root = try? run(at: project, arguments: ["rev-parse", "--show-toplevel"]) else { throw Failure.projectIsNotGit }
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
        guard parentPath != rootPath && !parentPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw Failure.destinationInsideRepository
        }
        guard (try? run(at: project, arguments: ["check-ref-format", "--branch", branch])) != nil else { throw Failure.invalidBranch }
        do { _ = try run(at: project, arguments: ["worktree", "add", "-b", branch, "--", destination.path, "HEAD"]) }
        catch { throw Failure.git(error.localizedDescription) }
        return destination
    }

    static func githubRemoteName(at project: URL) -> String? {
        guard let remote = try? run(at: project, arguments: ["remote", "get-url", "origin"]) else { return nil }
        let path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else if let components = URLComponents(string: remote),
                  ["https", "ssh"].contains(components.scheme?.lowercased() ?? ""),
                  components.host?.lowercased() == "github.com",
                  components.user == (components.scheme == "ssh" ? "git" : nil),
                  components.password == nil, components.port == nil,
                  components.query == nil, components.fragment == nil {
            path = components.path
        } else { return nil }
        var name = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        return name.split(separator: "/").count == 2 ? name : nil
    }

    static func currentBranch(at project: URL) -> String? {
        guard let branch = try? run(at: project, arguments: ["branch", "--show-current"]), !branch.isEmpty else { return nil }
        return branch
    }

    private static func run(at project: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", project.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            throw Failure.git("Git could not be started.")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.git("Git could not complete the worktree operation.") }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
