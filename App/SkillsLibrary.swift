import Foundation
import Observation

struct SkillEntry: Codable, Identifiable, Hashable, Sendable {
    enum SourceState: String, Codable, Sendable {
        case available
        case unavailable
    }

    var id: UUID
    var sourceKey: String
    var name: String
    var description: String
    var tags: [String]
    var category: String
    var source: String
    var sourceURL: String?
    var sourceFolder: String?
    var storedFolder: String
    var files: [String]
    var state: SourceState
    var installCommand: String?
    var installCommandSource: String?

    var folderURL: URL { URL(fileURLWithPath: storedFolder, isDirectory: true) }
}

struct SkillCandidate: Identifiable, Hashable, Sendable {
    var id: String { url }
    let name: String
    let description: String
    let url: String
    let source: String
    let repository: String?
    let path: String?
    let ref: String?
    var installCommand: String? = nil
    var installCommandSource: String? = nil
}

struct SkillInstallCommand: Sendable {
    let tool: String
    let repository: String
    let skillName: String?
    let pluginName: String?
    let sourcePath: String?
    let original: String

    static func parse(_ value: String) -> SkillInstallCommand? {
        let lines = value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        let words = lines.flatMap { $0.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) } }
        guard !words.contains(where: { $0.contains(";") || $0.contains("|") || $0.contains("&") || $0.contains("$ (") || $0.contains("$(") || $0.contains("`") }) else { return nil }
        func github(_ value: String) -> String? {
            let normalized = value.hasPrefix("https://github.com/") ? value : "https://github.com/\(value)"
            return GitHubSkillSearchAPI.candidate(from: normalized)?.repository
        }
        var repository: String?
        var skillName: String?
        var pluginName: String?
        var sourcePath: String?
        let tool: String
        if words.first == "npx", words.contains(where: { $0 == "skills" || $0.hasPrefix("skills@") }), let add = words.firstIndex(of: "add"), words.indices.contains(add + 1) {
            tool = "Skills CLI"
            let spec = words[add + 1]
            repository = github(spec)
            if let skill = words.firstIndex(of: "--skill"), words.indices.contains(skill + 1) { skillName = words[skill + 1] }
        } else if words.first == "codex", let marketplace = words.firstIndex(of: "marketplace"), let marketplaceAdd = words[(marketplace + 1)...].firstIndex(of: "add"), words.indices.contains(marketplaceAdd + 1) {
            tool = "Codex"
            repository = github(words[marketplaceAdd + 1])
            if let pluginAdd = words[(marketplaceAdd + 2)...].firstIndex(of: "add"), words.indices.contains(pluginAdd + 1) {
                pluginName = String(words[pluginAdd + 1].split(separator: "@").first ?? "")
            }
        } else if words.first == "claude", words.contains("marketplace"), let marketplace = words.firstIndex(of: "add"), words.indices.contains(marketplace + 1) {
            tool = "Claude Code"
            repository = github(words[marketplace + 1])
            if let install = words.firstIndex(of: "install"), words.indices.contains(install + 1) {
                pluginName = String(words[install + 1].split(separator: "@").first ?? "")
            }
        } else if words.first == "copilot", let marketplace = words.firstIndex(of: "marketplace"), let marketplaceAdd = words[(marketplace + 1)...].firstIndex(of: "add"), words.indices.contains(marketplaceAdd + 1) {
            tool = "Copilot CLI"
            repository = github(words[marketplaceAdd + 1])
            if let install = words.firstIndex(of: "install"), words.indices.contains(install + 1) {
                pluginName = String(words[install + 1].split(separator: "@").first ?? "")
            }
        } else if words.first == "copilot", let install = words.firstIndex(of: "install"), words.indices.contains(install + 1) {
            tool = "Copilot CLI"
            let spec = words[install + 1]
            let components = spec.split(separator: ":", maxSplits: 1).map(String.init)
            repository = github(components[0])
            if components.count > 1 { sourcePath = components[1] }
        } else if words.first == "gemini", let install = words.firstIndex(of: "install"), words.indices.contains(install + 1) {
            tool = "Gemini CLI"
            repository = github(words[install + 1])
        } else { return nil }
        guard let repository else { return nil }
        return SkillInstallCommand(tool: tool, repository: repository, skillName: skillName, pluginName: pluginName, sourcePath: sourcePath, original: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct SkillMetadata: Sendable {
    let name: String
    let description: String
    let tags: [String]
    let documentedCommand: String?

    static func parse(_ markdown: String, fallbackName: String) -> SkillMetadata {
        var name: String?
        var description: String?
        var tags: [String] = []
        let lines = markdown.components(separatedBy: .newlines)
        let frontMatter = lines.first == "---" ? Array(lines.dropFirst().prefix { $0 != "---" }) : []
        let body = frontMatter.isEmpty ? lines : Array(lines.dropFirst(frontMatter.count + 2))
        var readingTags = false
        for line in frontMatter {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colon = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colon].lowercased()
                let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                readingTags = key == "tags"
                switch key {
                case "name": name = unquote(value)
                case "description": description = unquote(value)
                case "tags": tags.append(contentsOf: values(value))
                default: break
                }
            } else if readingTags, trimmed.hasPrefix("- ") {
                tags.append(unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if !trimmed.isEmpty {
                readingTags = false
            }
        }

        let command = lines.first(where: { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("npx skills add ") || value.hasPrefix("npx skills@latest add ")
        })?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDescription = body.joined(separator: "\n")
            .components(separatedBy: "\n\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SkillMetadata(
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName,
            description: description.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackDescription,
            tags: Array(Set(tags.filter { !$0.isEmpty })).sorted(),
            documentedCommand: command
        )
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, value.last == first, first == "'" || first == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func values(_ value: String) -> [String] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
    }
}

enum SkillCategory {
    static let all = ["Design", "Development", "Orchestration", "Token Optimization", "Research", "Writing", "Productivity", "Security", "Data", "Other"]

    static func suggestion(name: String, description: String, tags: [String]) -> String {
        let value = ([name, description] + tags).joined(separator: " ").lowercased()
        let rules: [(String, [String])] = [
            ("Design", ["design", "ui", "ux", "visual", "frontend"]),
            ("Token Optimization", ["token", "context window", "compress", "caveman"]),
            ("Orchestration", ["orchestrat", "agent", "workflow", "multi-agent", "subagent"]),
            ("Research", ["research", "search", "investigat", "source"]),
            ("Writing", ["writing", "copywriting", "content", "editorial"]),
            ("Security", ["security", "audit", "threat", "vulnerability"]),
            ("Data", ["data", "analytics", "database", "sql"]),
            ("Productivity", ["productivity", "planning", "project management"]),
            ("Development", ["code", "software", "debug", "program", "development", "graphify"])
        ]
        return rules.first(where: { rule in rule.1.contains(where: { value.contains($0) }) })?.0 ?? "Other"
    }
}

actor SkillsLibraryRepository {
    private let root: URL
    private let indexURL: URL
    private let fileManager = FileManager.default
    private var entries: [SkillEntry]

    init(root: URL? = nil) {
        let support = root ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: Bundle.main.bundleIdentifier ?? "com.arnel.dev", directoryHint: .isDirectory)
            .appending(path: "SkillsLibrary", directoryHint: .isDirectory)
        self.root = support
        self.indexURL = support.appending(path: "index.json")
        self.entries = (try? JSONDecoder().decode([SkillEntry].self, from: Data(contentsOf: support.appending(path: "index.json")))) ?? []
    }

    func load() -> [SkillEntry] { entries }

    func scanRepository(_ folder: URL, repository: String, branch: String) throws -> [SkillCandidate] {
        var found: [(URL, String)] = []
        var markdownFiles: [URL] = []
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw SkillsLibraryError.cannotReadSource
        }
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            if item.pathExtension.lowercased() == "md" { markdownFiles.append(item) }
            guard item.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame else { continue }
            let relative = String(item.path.dropFirst(folder.path.count + 1))
            let skillFolder = item.deletingLastPathComponent()
            found.append((skillFolder, relative))
        }

        var candidates: [SkillCandidate] = []
        for (skillFolder, relative) in found {
            let key = "repo:\(repository.lowercased()):\(relative.lowercased())"
            let relativeFolder = String(skillFolder.path.dropFirst(folder.path.count + 1))
            let branchCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let sourceURL = URL(string: "https://github.com/\(repository)/tree/\(branch.addingPercentEncoding(withAllowedCharacters: branchCharacters) ?? branch)/\(relativeFolder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativeFolder)")?.absoluteString
            _ = try saveFolder(skillFolder, sourceKey: key, source: "\(repository)/\(relative)", sourceURL: sourceURL, sourceFolder: skillFolder.path, installSource: repository)
        }
        candidates.append(contentsOf: markdownFiles.flatMap { advertisedLinks(in: $0, repository: repository, branch: branch) })
        let active = Set(found.map { "repo:\(repository.lowercased()):\($0.1.lowercased())" })
        for index in entries.indices where entries[index].sourceKey.hasPrefix("repo:\(repository.lowercased()):") {
            if active.contains(entries[index].sourceKey) { entries[index].state = .available }
            else { entries[index].state = .unavailable }
        }
        try persist()
        return candidates
    }

    private func advertisedLinks(in file: URL, repository: String, branch: String) -> [SkillCandidate] {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize, size <= 2_000_000,
              let markdown = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let pattern = #"\[([^\]]+)\]\((https://github\.com/[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var inSkillsSection = false
        var urls: [String] = []
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("#") {
                let heading = line.lowercased()
                inSkillsSection = heading.contains("skill")
            }
            let lower = line.lowercased()
            guard inSkillsSection || lower.contains("skill") else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in regex.matches(in: line, range: range) {
                guard let urlRange = Range(match.range(at: 2), in: line) else { continue }
                urls.append(String(line[urlRange]))
            }
        }
        return Array(Set(urls)).compactMap { value in
            guard var candidate = GitHubSkillSearchAPI.candidate(from: value) else { return nil }
            candidate = SkillCandidate(
                name: candidate.name,
                description: "Advertised in \(file.lastPathComponent)",
                url: candidate.url,
                source: "\(repository)/\(file.lastPathComponent)",
                repository: candidate.repository,
                path: candidate.path,
                ref: candidate.ref ?? branch
            )
            return candidate
        }
    }

    func importFolder(_ folder: URL) throws -> SkillEntry {
        let startedAccess = folder.startAccessingSecurityScopedResource()
        defer { if startedAccess { folder.stopAccessingSecurityScopedResource() } }
        let sourceKey = "folder:\(folder.standardizedFileURL.path)"
        return try saveFolder(folder, sourceKey: sourceKey, source: folder.path, sourceURL: nil, sourceFolder: folder.path, installSource: nil)
    }

    func importGitHubFolder(_ folder: URL, repository: String, path: String, ref: String, url: URL, installCommand: String? = nil, installCommandSource: String? = nil) throws -> SkillEntry {
        let key = "repo:\(repository.lowercased()):\(path.lowercased())"
        let skillName = path.split(separator: "/").dropLast().last.map(String.init) ?? repository
        return try saveFolder(folder, sourceKey: key, source: "\(repository)/\(path)", sourceURL: url.absoluteString, sourceFolder: nil, installSource: repository, installSkillName: skillName, installCommandOverride: installCommand, installCommandOverrideSource: installCommandSource)
    }

    func markUnavailable(_ sourceKey: String) throws {
        guard let index = entries.firstIndex(where: { $0.sourceKey == sourceKey }) else { return }
        entries[index].state = .unavailable
        try persist()
    }

    func remove(_ id: UUID) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        if fileManager.fileExists(atPath: entry.folderURL.path) { try fileManager.removeItem(at: entry.folderURL) }
        entries.removeAll { $0.id == id }
        try persist()
    }

    func setCategory(_ category: String, for id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        try persist()
    }

    private func saveFolder(_ sourceFolder: URL, sourceKey: String, source: String, sourceURL: String?, sourceFolder storedSource: String?, installSource: String?, installSkillName: String? = nil, installCommandOverride: String? = nil, installCommandOverrideSource: String? = nil) throws -> SkillEntry {
        let files = try regularFiles(in: sourceFolder)
        guard !files.isEmpty else { throw SkillsLibraryError.emptySkill }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = entries.first(where: { $0.sourceKey == sourceKey })
        let id = previous?.id ?? UUID()
        let destination = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        let staging = root.appending(path: "\(id.uuidString).staging", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        let backup = root.appending(path: "\(id.uuidString).backup", directoryHint: .isDirectory)
        do {
            for (file, relative) in files {
                let target = staging.appending(path: relative)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: file, to: target)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: backup)
                try fileManager.moveItem(at: destination, to: backup)
            }
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.removeItem(at: staging)
            if !fileManager.fileExists(atPath: destination.path), fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }

        let skillMarkdown = files.first(where: { $0.1.caseInsensitiveCompare("SKILL.md") == .orderedSame })?.0
        let markdown = skillMarkdown.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let metadata = SkillMetadata.parse(markdown, fallbackName: sourceFolder.lastPathComponent)
        let command = installCommandOverride ?? metadata.documentedCommand ?? installSource.map {
            "npx skills add \(Self.shellQuote($0)) --skill \(Self.shellQuote(installSkillName ?? sourceFolder.lastPathComponent))"
        }
        let entry = SkillEntry(
            id: id,
            sourceKey: sourceKey,
            name: metadata.name,
            description: metadata.description,
            tags: metadata.tags,
            category: previous?.category ?? SkillCategory.suggestion(name: metadata.name, description: metadata.description, tags: metadata.tags),
            source: source,
            sourceURL: sourceURL,
            sourceFolder: storedSource,
            storedFolder: destination.path,
            files: files.map(\.1).sorted(),
            state: .available,
            installCommand: command,
            installCommandSource: installCommandOverrideSource ?? (metadata.documentedCommand == nil ? (installSource == nil ? nil : "Derived from the Skills CLI") : "Documented in SKILL.md")
        )
        if let index = entries.firstIndex(where: { $0.sourceKey == sourceKey }) { entries[index] = entry }
        else { entries.append(entry) }
        try persist()
        return entry
    }

    private func regularFiles(in folder: URL) throws -> [(URL, String)] {
        let rootPath = folder.standardizedFileURL.path
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw SkillsLibraryError.cannotReadSource
        }
        var files: [(URL, String)] = []
        var totalSize = 0
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let path = item.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            guard relative.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") && $0 != ".." }) else { continue }
            guard let size = values.fileSize, (0...2_000_000).contains(size), files.count < 100,
                  totalSize + size <= 10_000_000 else { throw SkillsLibraryError.skillDownloadTooLarge }
            totalSize += size
            files.append((item, relative))
        }
        return files
    }

    private func persist() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

@MainActor
@Observable
final class SkillsLibraryStore {
    private let repository: SkillsLibraryRepository
    private(set) var entries: [SkillEntry] = []
    private(set) var candidates: [SkillCandidate] = []
    private(set) var isScanning = false
    private(set) var isSearching = false
    private(set) var error: String?

    init(repository: SkillsLibraryRepository = SkillsLibraryRepository()) {
        self.repository = repository
        Task { entries = await repository.load() }
    }

    func scan(folder: URL, repository: String, branch: String) async {
        isScanning = true
        error = nil
        defer { isScanning = false }
        do {
            candidates = try await self.repository.scanRepository(folder, repository: repository, branch: branch)
            entries = await self.repository.load()
        } catch { self.error = error.localizedDescription }
    }

    func addFolder(_ folder: URL) async {
        error = nil
        do {
            _ = try await repository.importFolder(folder)
            entries = await repository.load()
        } catch { self.error = error.localizedDescription }
    }

    func searchGitHub(_ query: String, accessToken: String?) async {
        isSearching = true
        error = nil
        candidates = []
        defer { isSearching = false }
        do { candidates = try await GitHubSkillSearchAPI().search(query, accessToken: accessToken) }
        catch { self.error = error.localizedDescription }
    }

    func addGitHub(_ candidate: SkillCandidate, accessToken: String?) async {
        guard let repositoryName = candidate.repository, candidate.path != nil, let ref = candidate.ref,
              let sourceURL = URL(string: candidate.url) else {
            error = SkillsLibraryError.invalidGitHubURL.localizedDescription
            return
        }
        error = nil
        do {
            let downloaded = try await GitHubSkillSearchAPI().download(candidate, accessToken: accessToken)
            defer { try? FileManager.default.removeItem(at: downloaded.folder.deletingLastPathComponent()) }
            _ = try await repository.importGitHubFolder(downloaded.folder, repository: repositoryName, path: downloaded.skillPath, ref: ref, url: sourceURL, installCommand: candidate.installCommand, installCommandSource: candidate.installCommandSource)
            entries = await repository.load()
            candidates.removeAll { $0.id == candidate.id }
        } catch { self.error = error.localizedDescription }
    }

    func addGitHubURL(_ value: String, accessToken: String?) async {
        guard let candidate = GitHubSkillSearchAPI.candidate(from: value) else {
            error = SkillsLibraryError.invalidGitHubURL.localizedDescription
            return
        }
        if candidate.path != nil {
            await addGitHub(candidate, accessToken: accessToken)
        } else if let repository = candidate.repository {
            isSearching = true
            error = nil
            candidates = []
            defer { isSearching = false }
            do {
                candidates = try await GitHubSkillSearchAPI().repositorySkills(repository, ref: candidate.ref, accessToken: accessToken)
                if candidates.isEmpty { error = SkillsLibraryError.noSkillsInRepository.localizedDescription }
            }
            catch { self.error = error.localizedDescription }
        }
    }

    func resolveInstallCommand(_ value: String, accessToken: String?) async {
        guard let command = SkillInstallCommand.parse(value) else {
            error = SkillsLibraryError.invalidInstallCommand.localizedDescription
            candidates = []
            return
        }
        isSearching = true
        error = nil
        candidates = []
        defer { isSearching = false }
        do {
            var found = try await GitHubSkillSearchAPI().repositorySkills(command.repository, pluginName: command.pluginName, sourcePath: command.sourcePath, accessToken: accessToken)
            if let name = command.skillName {
                found = found.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
            candidates = found.map { candidate in
                var candidate = candidate
                candidate.installCommand = command.original
                candidate.installCommandSource = "Provided for \(command.tool)"
                return candidate
            }
            if candidates.isEmpty { error = SkillsLibraryError.noSkillsInRepository.localizedDescription }
        } catch { self.error = error.localizedDescription }
    }

    func setCategory(_ category: String, for entry: SkillEntry) async {
        // The entry is replaced in the repository using the category setter below.
        do {
            try await repository.setCategory(category, for: entry.id)
            entries = await repository.load()
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ entry: SkillEntry) async {
        do {
            try await repository.remove(entry.id)
            entries = await repository.load()
        } catch { self.error = error.localizedDescription }
    }

    func repositoryUnavailable(_ sourceKey: String) async {
        do {
            try await repository.markUnavailable(sourceKey)
            entries = await repository.load()
        } catch { self.error = error.localizedDescription }
    }
}

enum SkillsLibraryError: LocalizedError {
    case cannotReadSource
    case emptySkill
    case invalidGitHubURL
    case invalidGitHubResponse
    case invalidInstallCommand
    case pluginNotFound
    case truncatedGitHubTree
    case noSkillsInRepository
    case githubSignInRequired
    case skillDownloadTooLarge

    var errorDescription: String? {
        switch self {
        case .cannotReadSource: "The selected skill source could not be read."
        case .emptySkill: "The selected skill folder contains no readable files."
        case .invalidGitHubURL: "Use a GitHub repository or skill folder URL."
        case .invalidGitHubResponse: "GitHub returned skill data the app could not read."
        case .invalidInstallCommand: "Paste a supported install command that points to a GitHub repository or marketplace."
        case .pluginNotFound: "That plugin was not found in the repository marketplace. Include its marketplace add command."
        case .truncatedGitHubTree: "GitHub’s file listing was incomplete, so the skill was not copied."
        case .noSkillsInRepository: "No SKILL.md files were found in this repository."
        case .githubSignInRequired: "Sign in to GitHub before searching for skills."
        case .skillDownloadTooLarge: "This skill exceeds the file count or size limits and was not copied."
        }
    }
}

struct GitHubSkillSearchAPI: Sendable {
    private let transport: any GitHubHTTPTransport

    init(transport: any GitHubHTTPTransport = URLSessionGitHubTransport()) { self.transport = transport }

    func search(_ query: String, accessToken: String? = nil) async throws -> [SkillCandidate] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty, terms.count <= 180 else { return [] }
        guard let accessToken, !accessToken.isEmpty else { throw SkillsLibraryError.githubSignInRequired }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/search/code"
        components.queryItems = [URLQueryItem(name: "q", value: "\(terms) filename:SKILL.md"), URLQueryItem(name: "per_page", value: "30")]
        guard let url = components.url else { throw SkillsLibraryError.invalidGitHubURL }
        let response = try await transport.send(request(url, token: accessToken))
        guard response.statusCode == 200, let data = try? JSONDecoder().decode(CodeSearchResponse.self, from: response.data) else {
            throw SkillsLibraryError.invalidGitHubResponse
        }
        return data.items.compactMap { item in
            guard let htmlURL = item.htmlURL, htmlURL.scheme == "https", htmlURL.host == "github.com" else { return nil }
            let name = item.path.split(separator: "/").dropLast().last.map(String.init) ?? item.name
            return SkillCandidate(
                name: name,
                description: item.repository.description ?? "",
                url: htmlURL.absoluteString,
                source: "\(item.repository.fullName)/\(item.path)",
                repository: item.repository.fullName,
                path: item.path,
                ref: item.repository.defaultBranch
            )
        }
    }

    func repositorySkills(_ repository: String, ref: String? = nil, pluginName: String? = nil, sourcePath: String? = nil, accessToken: String? = nil) async throws -> [SkillCandidate] {
        guard Self.isValidRepository(repository) else { throw SkillsLibraryError.invalidGitHubURL }
        let branch: String
        if let ref {
            branch = ref
        } else {
            var repositoryURL = URLComponents()
            repositoryURL.scheme = "https"
            repositoryURL.host = "api.github.com"
            repositoryURL.path = "/repos/\(repository)"
            guard let url = repositoryURL.url else { throw SkillsLibraryError.invalidGitHubURL }
            let response = try await transport.send(request(url, token: accessToken))
            guard response.statusCode == 200,
                  let metadata = try? JSONDecoder().decode(RepositoryMetadata.self, from: response.data) else {
                throw SkillsLibraryError.invalidGitHubResponse
            }
            branch = metadata.defaultBranch
        }

        let tree = try await loadTree(repository: repository, ref: branch, token: accessToken)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encodedRef = branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? branch
        var skillRoot = sourcePath.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        if let pluginName {
            guard let manifest = tree.tree.first(where: { $0.type == "blob" && $0.path.hasSuffix("marketplace.json") }) else {
                throw SkillsLibraryError.pluginNotFound
            }
            let data = try await blobData(repository: repository, sha: manifest.sha, token: accessToken)
            guard let catalog = try? JSONDecoder().decode(PluginMarketplace.self, from: data),
                  let plugin = catalog.plugins.first(where: { $0.name == pluginName }),
                  !plugin.source.hasPrefix("http"), plugin.source.split(separator: "/").allSatisfy({ $0 != ".." }) else {
                throw SkillsLibraryError.pluginNotFound
            }
            let parts = plugin.source.split(separator: "/").map(String.init).filter { $0 != "." }
            guard parts.allSatisfy({ $0 != ".." && !$0.hasPrefix(".") }) else { throw SkillsLibraryError.pluginNotFound }
            skillRoot = parts.joined(separator: "/")
        }
        return tree.tree.compactMap { item in
            guard item.type == "blob", item.mode != "120000",
                  item.path.lowercased().hasSuffix("/skill.md") || item.path.caseInsensitiveCompare("SKILL.md") == .orderedSame,
                  item.path.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") && $0 != "." && $0 != ".." }),
                  Self.isValidSHA(item.sha) else { return nil }
            if let skillRoot, !skillRoot.isEmpty, item.path != skillRoot, !item.path.hasPrefix(skillRoot + "/") { return nil }
            var sourceURL = URLComponents()
            sourceURL.scheme = "https"
            sourceURL.host = "github.com"
            let encodedPath = item.path.split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
                .joined(separator: "/")
            sourceURL.percentEncodedPath = "/\(repository)/blob/\(encodedRef)/\(encodedPath)"
            guard let url = sourceURL.url else { return nil }
            let name = item.path.split(separator: "/").dropLast().last.map(String.init) ?? repository
            return SkillCandidate(name: name, description: "", url: url.absoluteString, source: "\(repository)/\(item.path)", repository: repository, path: item.path, ref: branch)
        }
    }

    private func blobData(repository: String, sha: String, token: String?) async throws -> Data {
        guard Self.isValidSHA(sha) else { throw SkillsLibraryError.invalidGitHubResponse }
        var components = URLComponents()
        components.scheme = "https"; components.host = "api.github.com"; components.path = "/repos/\(repository)/git/blobs/\(sha)"
        guard let url = components.url else { throw SkillsLibraryError.invalidGitHubURL }
        let response = try await transport.send(request(url, token: token))
        guard response.statusCode == 200, response.data.count <= 3_000_000,
              let blob = try? JSONDecoder().decode(GitBlobResponse.self, from: response.data), blob.encoding == "base64",
              let data = Data(base64Encoded: blob.content.filter { !$0.isWhitespace }) else { throw SkillsLibraryError.invalidGitHubResponse }
        return data
    }

    static func candidate(from value: String) -> SkillCandidate? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.user == nil, components.password == nil,
              !components.path.split(separator: "/").isEmpty else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        guard segments.count >= 2 else { return nil }
        let repositoryName = segments[1].lowercased().hasSuffix(".git") ? String(segments[1].dropLast(4)) : segments[1]
        let repository = "\(segments[0])/\(repositoryName)"
        guard !repositoryName.isEmpty, Self.isValidRepository(repository) else { return nil }
        guard segments.count >= 3, segments[2] == "tree" || segments[2] == "blob" else {
            return SkillCandidate(name: repository, description: "", url: value, source: repository, repository: repository, path: nil, ref: nil)
        }
        guard segments.count >= 4 else { return nil }
        let ref = segments[3]
        let path = segments.dropFirst(4).joined(separator: "/")
        guard !path.isEmpty else {
            return SkillCandidate(name: repository, description: "", url: value, source: repository, repository: repository, path: nil, ref: ref)
        }
        if segments[2] == "blob" && !path.lowercased().hasSuffix("skill.md") { return nil }
        let skillPath = segments[2] == "blob" ? path : path + "/SKILL.md"
        return SkillCandidate(name: skillPath.split(separator: "/").dropLast().last.map(String.init) ?? repository, description: "", url: value, source: "\(repository)/\(path)", repository: repository, path: skillPath, ref: ref)
    }

    func download(_ candidate: SkillCandidate, accessToken: String?) async throws -> (folder: URL, skillPath: String) {
        guard let repository = candidate.repository, let path = candidate.path, let ref = candidate.ref else {
            throw SkillsLibraryError.invalidGitHubURL
        }
        let skillPath = path.lowercased().hasSuffix("skill.md")
            ? path.split(separator: "/").dropLast().joined(separator: "/")
            : path
        guard Self.isValidRepository(repository),
              path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw SkillsLibraryError.invalidGitHubURL
        }
        let tree = try await loadTree(repository: repository, ref: ref, token: accessToken)
        let prefix = skillPath.isEmpty ? "" : skillPath + "/"
        let files = tree.tree.filter { item in
            item.type == "blob" && item.mode != "120000" && item.path.hasPrefix(prefix)
                && item.path.split(separator: "/").allSatisfy { !$0.hasPrefix(".") && $0 != "." && $0 != ".." }
                && (item.sha.count == 40 || item.sha.count == 64) && item.sha.allSatisfy(\.isHexDigit)
        }
        let sizes = files.compactMap(\.size)
        guard files.count <= 100, sizes.count == files.count,
              sizes.allSatisfy({ (0...2_000_000).contains($0) }), sizes.reduce(0, +) <= 10_000_000 else {
            throw SkillsLibraryError.skillDownloadTooLarge
        }
        guard files.contains(where: { $0.path.caseInsensitiveCompare(path) == .orderedSame }) else {
            throw SkillsLibraryError.invalidGitHubURL
        }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let skillFolder = temporaryRoot.appending(path: "skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        do {
            for file in files {
                try Task.checkCancellation()
                var blobURL = URLComponents()
                blobURL.scheme = "https"
                blobURL.host = "api.github.com"
                blobURL.path = "/repos/\(repository)/git/blobs/\(file.sha)"
                guard let requestURL = blobURL.url else { throw SkillsLibraryError.invalidGitHubURL }
                let blobResponse = try await transport.send(request(requestURL, token: accessToken))
                guard blobResponse.statusCode == 200, blobResponse.data.count <= 3_000_000,
                      let blob = try? JSONDecoder().decode(GitBlobResponse.self, from: blobResponse.data),
                      blob.encoding == "base64",
                      let data = Data(base64Encoded: blob.content.filter { !$0.isWhitespace }) else {
                    throw SkillsLibraryError.invalidGitHubResponse
                }
                guard data.count == file.size else { throw SkillsLibraryError.invalidGitHubResponse }
                let relative = String(file.path.dropFirst(prefix.count))
                let destination = skillFolder.appending(path: relative)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryRoot)
            throw error
        }
        return (skillFolder, skillPath)
    }

    private func request(_ url: URL, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(GitHubAPIClient.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func loadTree(repository: String, ref: String, token: String?) async throws -> GitTreeResponse {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: allowed) ?? ref
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/repos/\(repository)/git/trees/\(encodedRef)"
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        guard let url = components.url else { throw SkillsLibraryError.invalidGitHubURL }
        let response = try await transport.send(request(url, token: token))
        guard response.statusCode == 200, response.data.count <= 5_000_000,
              let tree = try? JSONDecoder().decode(GitTreeResponse.self, from: response.data) else {
            throw SkillsLibraryError.invalidGitHubResponse
        }
        guard !tree.truncated else { throw SkillsLibraryError.truncatedGitHubTree }
        return tree
    }

    private static func isValidRepository(_ repository: String) -> Bool {
        let parts = repository.split(separator: "/")
        return parts.count == 2 && parts.allSatisfy {
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
        }
    }

    private static func isValidSHA(_ sha: String) -> Bool {
        (sha.count == 40 || sha.count == 64) && sha.allSatisfy(\.isHexDigit)
    }

    private struct RepositoryMetadata: Decodable {
        let defaultBranch: String
        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }
    private struct PluginMarketplace: Decodable {
        let plugins: [Plugin]
        struct Plugin: Decodable { let name: String; let source: String }
    }

    private struct CodeSearchResponse: Decodable { let items: [CodeSearchItem] }
    private struct CodeSearchItem: Decodable {
        let name: String
        let path: String
        let htmlURL: URL?
        let repository: Repo
        enum CodingKeys: String, CodingKey { case name, path, repository; case htmlURL = "html_url" }
        struct Repo: Decodable {
            let fullName: String
            let defaultBranch: String
            let description: String?
            enum CodingKeys: String, CodingKey { case description; case fullName = "full_name"; case defaultBranch = "default_branch" }
        }
    }
    private struct GitTreeResponse: Decodable { let truncated: Bool; let tree: [TreeEntry] }
    private struct TreeEntry: Decodable { let path: String; let mode: String; let type: String; let sha: String; let size: Int? }
    private struct GitBlobResponse: Decodable { let encoding: String; let content: String }
}
