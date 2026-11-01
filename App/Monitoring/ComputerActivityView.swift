import SwiftUI
import AppKit
import Foundation
import IOKit
import IOKit.ps

struct ComputerProcess: Identifiable, Sendable {
    let id: Int
    let name: String
    let cpu: Double
    let memory: Int64

    static func parse(_ output: String) -> [Self] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4, let pid = Int(fields[0]), pid > 0, pid <= Int32.max,
                  let cpu = Double(fields[1]), cpu.isFinite, cpu >= 0,
                  let kib = Int64(fields[2]), kib >= 0, kib <= Int64.max / 1024 else { return nil }
            let name = URL(fileURLWithPath: String(fields[3])).lastPathComponent
            return .init(id: pid, name: name, cpu: cpu, memory: kib * 1024)
        }
    }
}

struct ComputerBattery: Sendable {
    let charge: Int?
    let state: String
    let health: String
    let cycles: Int?

    static func read() -> Self? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let charge: Int? = if let current, let maximum, maximum > 0, current >= 0, current <= maximum {
                Int(Double(current) / Double(maximum) * 100)
            } else { nil }
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let state = charging ? "Charging" : (description[kIOPSPowerSourceStateKey] as? String ?? "Not reported")
            let health = [description[kIOPSBatteryHealthConditionKey] as? String, description[kIOPSBatteryHealthKey] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Not reported"
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            var cycles: Int?
            if service != 0 {
                cycles = (IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
                IOObjectRelease(service)
            }
            return .init(charge: charge, state: state, health: health, cycles: cycles.flatMap { $0 >= 0 ? $0 : nil })
        }
        return nil
    }
}

private final class ComputerProcessRead: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var stopped = false
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }
    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }; return stopped
    }

    func read() throws -> [ComputerProcess] {
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard !isStopped else { throw CancellationError() }
        try process.run()
        if isStopped { stop(); throw CancellationError() }
        let timeout = DispatchWorkItem { [self] in stop() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel(); stop(); try? pipe.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 64_000), !chunk.isEmpty {
            guard data.count + chunk.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.cannotLoadFromNetwork) }
        return ComputerProcess.parse(String(decoding: data, as: UTF8.self))
    }
}

struct ComputerActivityView: View {
    @State private var processes: [ComputerProcess] = []
    @State private var battery: ComputerBattery?
    @State private var query = ""
    @State private var sort = "Memory"
    @State private var error: String?
    @State private var updated: Date?
    @State private var page = 0
    @State private var quitTarget: QuitTarget?
    @State private var quitMessage: String?
    private struct QuitTarget { let pid: pid_t; let name: String; let launchDate: Date }

    private func quitCandidate(_ process: ComputerProcess) -> NSRunningApplication? {
        guard process.id != Int(ProcessInfo.processInfo.processIdentifier),
              let app = NSRunningApplication(processIdentifier: pid_t(process.id)),
              app.activationPolicy == .regular, app.launchDate != nil,
              app.executableURL?.lastPathComponent == process.name else { return nil }
        return app
    }

    private var filtered: [ComputerProcess] {
        processes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id).contains(query) }
            .sorted {
                let lhs = sort == "CPU" ? $0.cpu : Double($0.memory)
                let rhs = sort == "CPU" ? $1.cpu : Double($1.memory)
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    batteryPanel.frame(width: 300)
                    Divider()
                    BatteryHistoryView().frame(minWidth: 380, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 20) { batteryPanel; Divider(); BatteryHistoryView() }
            }.monitoringCard()
            taskManager
        }
        .task {
            while !Task.isCancelled {
                let reader = ComputerProcessRead()
                let task = Task.detached(priority: .utility) { (try reader.read(), ComputerBattery.read()) }
                do {
                    let result = try await withTaskCancellationHandler { try await task.value } onCancel: { reader.stop(); task.cancel() }
                    guard !Task.isCancelled else { return }
                    processes = result.0; battery = result.1; updated = .now; self.error = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "Process snapshot unavailable. Existing rows may be stale."
                }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .confirmationDialog("Quit \(quitTarget?.name ?? "app")?", isPresented: Binding(get: { quitTarget != nil }, set: { if !$0 { quitTarget = nil } }), titleVisibility: .visible) {
            Button("Quit app", role: .destructive) {
                guard let target = quitTarget,
                      let app = NSRunningApplication(processIdentifier: target.pid),
                      app.activationPolicy == .regular,
                      app.launchDate == target.launchDate,
                      target.pid != ProcessInfo.processInfo.processIdentifier else {
                    quitMessage = "App identity changed. Refresh and try again."; quitTarget = nil; return
                }
                quitMessage = app.terminate() ? "Quit requested for \(target.name); the app may ask to save work." : "The app did not accept the quit request."
                quitTarget = nil
            }
            Button("Cancel", role: .cancel) { quitTarget = nil }
        } message: {
            Text("PID \(quitTarget?.pid ?? 0). This requests a normal quit; the app may ask you to save work. No force quit is used.")
        }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: sort) { _, _ in page = 0 }
    }

    private var batteryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Battery health & power", systemImage: "battery.100percent").workspaceFont(.headline)
            if let battery {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 16) {
                    batteryMetric("Charge", battery.charge.map { "\($0)%" } ?? "Not reported")
                    batteryMetric("Power", battery.state)
                    batteryMetric("Condition", battery.health)
                    batteryMetric("Cycle count", battery.cycles.map(String.init) ?? "Not reported")
                }
                Text("Reported by macOS. Charge is remaining battery, not maximum-capacity health. Per-process energy impact is available in Activity Monitor.").workspaceFont(.caption).foregroundStyle(.secondary)
            } else {
                Text(updated == nil ? "Reading battery information…" : "No internal battery reported by macOS.").workspaceFont(.subheadline).foregroundStyle(.secondary)
            }
            Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
        }
    }

    private func batteryMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).workspaceFont(.caption).foregroundStyle(.secondary)
            Text(value).workspaceFont(.headline)
        }
    }

    private var taskManager: some View {
        let pagination = MonitoringPagination(total: filtered.count, page: page, pageSize: 10)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Task manager", systemImage: "list.bullet.rectangle").workspaceFont(.headline)
                Spacer()
                Text("\(processes.count) processes").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Search process or PID", text: $query).textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $sort) { Text("Memory").tag("Memory"); Text("CPU").tag("CPU") }.frame(width: 160)
            }
            if let quitMessage { Text(quitMessage).workspaceFont(.caption).foregroundStyle(.secondary) }
            if let error { Label(error, systemImage: "exclamationmark.triangle").workspaceFont(.caption).foregroundStyle(.orange) }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { Text("Process"); Text("PID"); Text("CPU"); Text("Memory"); Text("Action") }.workspaceFont(.caption).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(filtered[pagination.range])) { process in
                    GridRow {
                        Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(process.id)).foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", process.cpu))
                        Text(ByteCountFormatter.string(fromByteCount: process.memory, countStyle: .memory))
                        if let app = quitCandidate(process), let launchDate = app.launchDate {
                            Button("Quit…") { quitTarget = .init(pid: app.processIdentifier, name: app.localizedName ?? process.name, launchDate: launchDate) }
                                .accessibilityLabel("Quit \(app.localizedName ?? process.name), PID \(process.id)")
                        } else { Text("—").foregroundStyle(.secondary) }
                    }.workspaceFont(.subheadline).monospacedDigit()
                }
            }
            HStack {
                Text(pagination.summary).workspaceFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Previous") { page = pagination.page - 1 }.disabled(pagination.page == 0)
                Button("Next") { page = pagination.page + 1 }.disabled(pagination.page + 1 >= pagination.pageCount)
            }
            Text("CPU is the process lifetime average (100% = one core); memory is resident RAM, not disk storage. Refreshes every five seconds while this tab is visible.").workspaceFont(.caption).foregroundStyle(.secondary)
            if let updated { Text("Snapshot \(updated.formatted(date: .omitted, time: .standard))").workspaceFont(.caption).foregroundStyle(.secondary) }
        }.monitoringCard()
    }
}
