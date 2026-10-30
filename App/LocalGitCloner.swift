import Foundation

actor LocalGitCloner {
    func clone(repository: GitHubRepository, parent: URL, accessToken: String) throws -> URL {
        let destination = parent.appending(path: repository.name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            if let existing = try? addExistingClone(repository: repository, at: destination) { return existing }
            throw LocalGitError.destinationExists
        }
        guard let cloneURL = repository.safeGitHubURL?.appendingPathExtension("git") else {
            throw LocalGitError.cloneFailed("GitHub returned an unsupported repository URL.")
        }

        let helperDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: helperDirectory) }
        let askPass = helperDirectory.appending(path: "askpass")
        try "#!/bin/sh\ncase \"$1\" in *Username*) printf '%s\\n' 'x-access-token' ;; *) printf '%s\\n' \"$GITHUB_TOKEN\" ;; esac\n".write(to: askPass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askPass.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--", cloneURL.absoluteString, destination.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_ASKPASS": askPass.path,
            "GIT_TERMINAL_PROMPT": "0",
            "GITHUB_TOKEN": accessToken
        ]) { _, new in new }
        let log = helperDirectory.appending(path: "clone.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        process.standardOutput = output
        process.standardError = output
        try process.run()
        // shortcut: clone cannot be canceled while Git is running, add process termination handling when cancellation is needed.
        process.waitUntilExit()
        try output.close()

        guard process.terminationStatus == 0 else {
            let data = try Data(contentsOf: log)
            let message = String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: accessToken, with: "[redacted]")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalGitError.cloneFailed(message?.isEmpty == false ? message! : "Git could not clone this repository.")
        }
        return destination
    }

    func addExistingClone(repository: GitHubRepository, at folder: URL) throws -> URL {
        let root = try gitOutput(at: folder, arguments: ["rev-parse", "--show-toplevel"])
        guard URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL else {
            throw LocalGitError.notMatchingRepository
        }
        let remote = try gitOutput(at: folder, arguments: ["remote", "get-url", "origin"])
        guard remoteRepositoryName(remote)?.caseInsensitiveCompare(repository.fullName) == .orderedSame else {
            throw LocalGitError.notMatchingRepository
        }
        return folder
    }

    private func gitOutput(at folder: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let value = String(data: data, encoding: .utf8) else {
            throw LocalGitError.notMatchingRepository
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func remoteRepositoryName(_ remote: String) -> String? {
        let path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else if let components = URLComponents(string: remote),
                  components.scheme == "https" || components.scheme == "ssh",
                  components.host?.lowercased() == "github.com",
                  components.user == (components.scheme == "ssh" ? "git" : nil),
                  components.password == nil, components.port == nil,
                  components.query == nil, components.fragment == nil {
            path = components.path
        } else {
            return nil
        }
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = trimmedPath.hasSuffix(".git") ? String(trimmedPath.dropLast(4)) : trimmedPath
        return name.split(separator: "/").count == 2 ? name : nil
    }
}

enum LocalGitError: LocalizedError, Equatable {
    case destinationExists
    case notMatchingRepository
    case cloneFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists: "The selected folder already contains an item with this repository’s name. Use Add Folder if it is your checkout, or choose another parent folder."
        case .notMatchingRepository: "That folder is not a GitHub checkout for this repository."
        case let .cloneFailed(message): message
        }
    }
}
