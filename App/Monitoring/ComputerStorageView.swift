import Foundation
import SwiftUI

struct AppStorageRecord: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleBytes: Int64
    let cacheBytes: Int64
    let supportBytes: Int64
    var measuredBytes: Int64 { bundleBytes + cacheBytes + supportBytes }
}

struct AppStorageReport: Sendable {
    let apps: [AppStorageRecord]
    let partial: Bool
    let date: Date
}

enum AppStorageScanner {
    struct Budget {
        var remaining = 100_000
        var deadline = Date.now.addingTimeInterval(20)
        var partial = false
        mutating func permit() -> Bool {
            guard !Task.isCancelled, remaining > 0, Date.now < deadline else { partial = true; return false }
            remaining -= 1
            return true
        }
    }

    static func allocatedBytes(at root: URL, budget: inout Budget) -> Int64 {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let rootValues: URLResourceValues
        do { rootValues = try root.resourceValues(forKeys: keys) }
        catch {
            if !isMissing(error) { budget.partial = true }
            return 0
        }
        guard rootValues.isSymbolicLink != true else { budget.partial = true; return 0 }
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in enumerationFailed = true; return true }) else { budget.partial = true; return 0 }
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            guard budget.permit() else { break }
            if enumerator.level > 24 { enumerator.skipDescendants(); budget.partial = true; continue }
            guard let values = try? url.resourceValues(forKeys: keys) else { budget.partial = true; enumerator.skipDescendants(); continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true {
                if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize { total += Int64(max(0, size)) }
                else { budget.partial = true }
            }
        }
        budget.partial = budget.partial || enumerationFailed
        return total
    }

    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
    }

    static func dataDirectory(bundleID: String, under root: URL) -> URL? {
        guard !bundleID.isEmpty, bundleID != ".", bundleID != "..", !bundleID.contains("/"), !bundleID.contains("\\"), bundleID.utf8.count < 256 else { return nil }
        return root.appendingPathComponent(bundleID, isDirectory: true)
    }

    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AppStorageReport {
        let manager = FileManager.default
        var budget = Budget()
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appending(path: "Applications")]
        roots.append(URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true))
        var rows: [AppStorageRecord] = []
        var seenPaths: Set<String> = []
        var attributedIDs: Set<String> = []
        for root in roots {
            guard budget.permit() else { break }
            let children: [URL]
            do { children = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) }
            catch { if !isMissing(error) { budget.partial = true }; continue }
            for url in children.sorted(by: { $0.path < $1.path }) where url.pathExtension.lowercased() == "app" {
                guard budget.permit() else { break }
                guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false, seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
                let bundle = Bundle(url: url)
                let identifier = bundle?.bundleIdentifier
                let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let appBytes = allocatedBytes(at: url, budget: &budget)
                var cache: Int64 = 0
                var support: Int64 = 0
                if let identifier, attributedIDs.insert(identifier).inserted {
                    if let directory = dataDirectory(bundleID: identifier, under: home.appending(path: "Library/Caches")) { cache = allocatedBytes(at: directory, budget: &budget) }
                    if let directory = dataDirectory(bundleID: identifier, under: home.appending(path: "Library/Application Support")) { support = allocatedBytes(at: directory, budget: &budget) }
                }
                rows.append(.init(id: url.path, name: name, bundleBytes: appBytes, cacheBytes: cache, supportBytes: support))
            }
        }
        return .init(apps: rows.sorted { $0.measuredBytes == $1.measuredBytes ? $0.id < $1.id : $0.measuredBytes > $1.measuredBytes }, partial: budget.partial, date: .now)
    }
}

struct ComputerStorageView: View {
    @State private var report: AppStorageReport?
    @State private var scanning = false
    @State private var revision = 0
    @State private var query = ""
    @State private var page = 0
    @State private var sort = "Measured size"

    private var rows: [AppStorageRecord] {
        let filtered = (report?.apps ?? []).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return sort == "Name" ? filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : filtered
    }

    var body: some View {
        let pagination = MonitoringPagination(total: rows.count, page: page, pageSize: 8)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("App storage", systemImage: "internaldrive").workspaceFont(.headline)
                Spacer()
                Button(scanning ? "Cancel scan" : report == nil ? "Scan app storage" : "Scan again") { revision = scanning ? 0 : revision + 1 }
            }
            Text("Find large app bundles and directly matched local data. Read-only; nothing is deleted.").workspaceFont(.subheadline).foregroundStyle(.secondary)
            if scanning { ProgressView("Measuring allocated storage…") }
            if let report {
                HStack {
                    TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $sort) { Text("Measured size").tag("Measured size"); Text("Name").tag("Name") }.frame(maxWidth: 200)
                }
                ForEach(Array(rows[pagination.range])) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(row.name).workspaceFont(.subheadline, weight: .semibold); Spacer(); Text(bytes(row.measuredBytes)).monospacedDigit() }
                        Text("App \(bytes(row.bundleBytes)) · Cache \(bytes(row.cacheBytes)) · Support \(bytes(row.supportBytes))").workspaceFont(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                    Divider()
                }
                if rows.isEmpty { Text("No matching apps measured.").foregroundStyle(.secondary) }
                HStack {
                    Text("\(pagination.summary) · \(report.date.formatted(date: .omitted, time: .shortened))").workspaceFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous") { page = pagination.page - 1 }.disabled(pagination.page == 0)
                    Button("Next") { page = pagination.page + 1 }.disabled(pagination.page + 1 >= pagination.pageCount)
                }
                if report.partial { Label("Scan incomplete: limits or inaccessible files affected results.", systemImage: "exclamationmark.triangle").workspaceFont(.caption).foregroundStyle(.orange) }
            }
            Text("Measured allocation only, not total app impact. Scans /Applications, its Utilities folder and ~/Applications; data attribution requires an exact bundle ID folder in your user Caches or Application Support. Containers, shared data, alternate folders, other users, snapshots and purgeable storage are excluded. APFS clones/hard links may share blocks; app rows are not a physical disk total. Scans stop after 20 seconds or 100,000 entries.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
        }
        .monitoringCard()
        .onDisappear { revision = 0; scanning = false }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: sort) { _, _ in page = 0 }
        .task(id: revision) {
            guard revision > 0 else { scanning = false; return }
            scanning = true
            let worker = Task.detached(priority: .utility) { AppStorageScanner.scan() }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            report = result
            page = 0
            scanning = false
        }
    }

    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
