import Foundation
import Observation

struct UptimeTarget: Codable, Identifiable, Sendable {
    let id: UUID
    let url: URL
}

struct UptimeObservation: Codable, Identifiable, Sendable {
    var id: String { "\(targetID)-\(date.timeIntervalSince1970)" }
    let targetID: UUID
    let date: Date
    let status: Int?
    let milliseconds: Double?
    var healthy: Bool { status.map { (200..<300).contains($0) } ?? false }
}

struct MonitoringHistory: Codable, Sendable {
    var samples: [MonitoringSample] = []
    var targets: [UptimeTarget] = []
    var observations: [UptimeObservation] = []

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        samples.removeAll { $0.date < cutoff }
        observations.removeAll { $0.date < cutoff }
    }
}

@MainActor
@Observable
final class MonitoringStore {
    private var history = MonitoringHistory()
    private(set) var current: MonitoringSample?
    private(set) var systemError: String?
    private(set) var historyError: String?
    private(set) var connectionErrors: [MonitoringConnection: String] = [:]
    private(set) var connectionDates: [MonitoringConnection: Date] = [:]
    private(set) var remoteRows: [MonitoringConnection: [MonitoringRemoteRow]] = [:]
    private(set) var vercelProjects: [VercelProject] = []
    private(set) var vercelWarnings: [String] = []
    private(set) var vercelDeployments: [String: [VercelDeployment]] = [:]
    private(set) var vercelNextCursors: [String: String] = [:]
    private(set) var vercelDeploymentDates: [String: Date] = [:]
    private(set) var vercelProjectErrors: [String: String] = [:]
    private(set) var vercelLoading: Set<String> = []
    private(set) var vercelTraffic: [String: VercelTraffic] = [:]
    private(set) var refreshing = false
    private(set) var connected: Set<MonitoringConnection> = []
    private let writer = MonitoringHistoryWriter()
    private var persistRevision = 0
    private var credentialRevisions: [MonitoringConnection: Int] = [:]
    private var refreshAgain = false
    private var previous: SystemCounters?
    private var started = false
    private let historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "dev/Monitoring/history.json")

    var samples: [MonitoringSample] { history.samples }
    var targets: [UptimeTarget] { history.targets }
    var observations: [UptimeObservation] { history.observations }

    func run() async {
        guard !started else { return }
        started = true
        defer { started = false }
        let file = historyURL
        do {
            let loaded = try await Task.detached(priority: .utility) { () -> MonitoringHistory in
                guard FileManager.default.fileExists(atPath: file.path) else { return MonitoringHistory() }
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 64_000_000 else { throw CocoaError(.fileReadTooLarge) }
                return try JSONDecoder().decode(MonitoringHistory.self, from: Data(contentsOf: file))
            }.value
            history = loaded
            history.targets = Array(history.targets.filter { Self.uptimeURL($0.url.absoluteString) != nil }.prefix(20))
            history.prune(now: .now)
        } catch { historyError = "Saved monitoring history could not be read. New samples remain available in this session." }
        for connection in MonitoringConnection.allCases {
            do { if try MonitoringCredentials.load(connection) != nil { connected.insert(connection) } }
            catch { connectionErrors[connection] = "Keychain access failed. Reconnect to retry." }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.sampleSystem() }
            group.addTask { await self.runProbes() }
            group.addTask { await self.runConnections() }
            await group.waitForAll()
        }
    }

    private func sampleSystem() async {
        while !Task.isCancelled {
            if let counters = await Task.detached(priority: .utility, operation: SystemCounters.read).value {
                current = MonitoringSample(current: counters, previous: previous)
                previous = counters
                systemError = nil
                if let current, current.date.timeIntervalSince(history.samples.last?.date ?? .distantPast) >= 60 {
                    history.samples.append(current)
                    history.prune(now: .now)
                    await persist()
                }
            } else { systemError = "Mac metrics unavailable. Last values may be stale." }
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
        }
    }

    private func runProbes() async {
        while !Task.isCancelled {
            await probeTargets()
            do { try await Task.sleep(for: .seconds(60)) } catch { break }
        }
    }

    private func runConnections() async {
        while !Task.isCancelled {
            await refreshRemote()
            do { try await Task.sleep(for: .seconds(300)) } catch { break }
        }
    }

    static func uptimeURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    func addTarget(_ text: String) async -> Bool {
        guard let url = Self.uptimeURL(text), !history.targets.contains(where: { $0.url == url }), history.targets.count < 20 else { return false }
        history.targets.append(UptimeTarget(id: UUID(), url: url))
        await persist()
        await probeTargets()
        return true
    }

    func removeTarget(_ target: UptimeTarget) async {
        history.targets.removeAll { $0.id == target.id }
        history.observations.removeAll { $0.targetID == target.id }
        await persist()
    }

    func connect(_ connection: MonitoringConnection, token: String) async {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains(where: { $0.isNewline }) else {
            connectionErrors[connection] = "Enter a valid token."
            return
        }
        do {
            try MonitoringCredentials.save(cleaned, for: connection)
            connected.insert(connection)
            credentialRevisions[connection, default: 0] += 1
            remoteRows[connection] = nil
            connectionDates[connection] = nil
            if connection == .vercel { clearVercel() }
            connectionErrors[connection] = nil
            await refreshRemote()
        } catch { connectionErrors[connection] = "Could not save this credential in Keychain." }
    }

    func disconnect(_ connection: MonitoringConnection) {
        do {
            try MonitoringCredentials.delete(connection)
            connected.remove(connection)
            if connection == .vercel { clearVercel() }
            credentialRevisions[connection, default: 0] += 1
            remoteRows[connection] = nil
            connectionDates[connection] = nil
            connectionErrors[connection] = nil
        } catch { connectionErrors[connection] = "Could not remove this credential from Keychain." }
    }

    func refreshRemote() async {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            for connection in MonitoringConnection.allCases where connected.contains(connection) {
                let revision = credentialRevisions[connection, default: 0]
                do {
                    guard let token = try MonitoringCredentials.load(connection) else { continue }
                    if connection == .vercel {
                        let result = try await VercelMonitoring.fetchProjects(token: token)
                        guard connected.contains(connection), credentialRevisions[connection, default: 0] == revision else { continue }
                        vercelProjects = result.projects
                        vercelWarnings = result.warnings
                    } else {
                        let result = try await MonitoringRemote.fetch(connection, token: token)
                        guard connected.contains(connection), credentialRevisions[connection, default: 0] == revision else { continue }
                        remoteRows[connection] = result.rows
                    }
                    connectionDates[connection] = .now
                    connectionErrors[connection] = nil
                } catch {
                    guard connected.contains(connection), credentialRevisions[connection, default: 0] == revision else { continue }
                    connectionErrors[connection] = "\(MonitoringRemote.safeMessage(error)) Previous data, if any, is stale."
                }
            }
        } while refreshAgain && !Task.isCancelled
    }

    private func clearVercel() {
        vercelProjects = []
        vercelWarnings = []
        vercelDeployments = [:]
        vercelNextCursors = [:]
        vercelDeploymentDates = [:]
        vercelProjectErrors = [:]
        vercelTraffic = [:]
        vercelLoading = []
    }

    func loadVercelDeployments(_ project: VercelProject, more: Bool = false) async {
        guard connected.contains(.vercel), !vercelLoading.contains(project.id) else { return }
        let cursor = more ? vercelNextCursors[project.id] : nil
        if more && cursor == nil { return }
        let revision = credentialRevisions[.vercel, default: 0]
        vercelLoading.insert(project.id)
        defer { if credentialRevisions[.vercel, default: 0] == revision { vercelLoading.remove(project.id) } }
        do {
            guard let token = try MonitoringCredentials.load(.vercel) else { return }
            let page = try await VercelMonitoring.fetchDeployments(project: project, token: token, before: cursor)
            guard connected.contains(.vercel), credentialRevisions[.vercel, default: 0] == revision else { return }
            if more {
                let existing = vercelDeployments[project.id] ?? []
                let ids = Set(existing.map(\.id))
                vercelDeployments[project.id] = existing + page.deployments.filter { !ids.contains($0.id) }
            } else {
                vercelDeployments[project.id] = page.deployments
                vercelDeploymentDates[project.id] = .now
            }
            vercelNextCursors[project.id] = page.nextCursor
            vercelProjectErrors[project.id] = nil
            if !more {
                do {
                    let traffic = try await VercelMonitoring.fetchTraffic(project: project, token: token)
                    guard connected.contains(.vercel), credentialRevisions[.vercel, default: 0] == revision else { return }
                    vercelTraffic[project.id] = traffic
                } catch {
                    guard connected.contains(.vercel), credentialRevisions[.vercel, default: 0] == revision else { return }
                    vercelTraffic[project.id] = .init(detail: "Web Analytics unavailable. Verify instrumentation, permissions and plan access, or open Vercel Observability.")
                }
            }
        } catch {
            guard connected.contains(.vercel), credentialRevisions[.vercel, default: 0] == revision else { return }
            vercelProjectErrors[project.id] = "\(MonitoringRemote.safeMessage(error)) Previous history, if any, is stale."
        }
    }

    private func probeTargets() async {
        let targets = history.targets
        let results = await withTaskGroup(of: UptimeObservation.self, returning: [UptimeObservation].self) { group in
            for target in targets {
                group.addTask {
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 10
                    config.timeoutIntervalForResource = 15
                    config.httpCookieStorage = nil
                    config.urlCredentialStorage = nil
                    config.urlCache = nil
                    config.httpShouldSetCookies = false
                    let session = URLSession(configuration: config, delegate: MonitoringProbeDelegate(), delegateQueue: nil)
                    defer { session.invalidateAndCancel() }
                    var request = URLRequest(url: target.url)
                    request.httpMethod = "HEAD"
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    let start = ContinuousClock.now
                    do {
                        let (_, response) = try await session.data(for: request)
                        let duration = start.duration(to: .now)
                        let ms = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
                        return UptimeObservation(targetID: target.id, date: .now, status: (response as? HTTPURLResponse)?.statusCode, milliseconds: ms)
                    } catch { return UptimeObservation(targetID: target.id, date: .now, status: nil, milliseconds: nil) }
                }
            }
            var results: [UptimeObservation] = []
            for await result in group { results.append(result) }
            return results
        }
        history.observations += results.filter { result in history.targets.contains { $0.id == result.targetID } }
        history.prune(now: .now)
        if !results.isEmpty { await persist() }
    }

    private func persist() async {
        guard historyError == nil else { return }
        let snapshot = history
        let file = historyURL
        persistRevision += 1
        let revision = persistRevision
        do {
            try await writer.save(snapshot, to: file, revision: revision)
        } catch { historyError = "Monitoring history could not be saved. New data remains in memory." }
    }
}

private final class MonitoringProbeDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.user == nil && request.url?.password == nil ? request : nil)
    }
}

actor MonitoringHistoryWriter {
    private var lastRevision = 0

    func save(_ history: MonitoringHistory, to file: URL, revision: Int) throws {
        guard revision > lastRevision else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        lastRevision = revision
    }
}
