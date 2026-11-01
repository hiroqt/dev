import SwiftUI
import Charts
import CoreGraphics

struct BatteryHistoryPoint: Codable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let charge: Int
    let charging: Bool
    let screenSeconds: Double
}

enum BatteryHistoryMath {
    static func screenSeconds(previous: Date?, now: Date, awake: Bool) -> Double {
        guard awake, let previous else { return 0 }
        let elapsed = now.timeIntervalSince(previous)
        return elapsed > 0 && elapsed <= 90 ? elapsed : 0
    }
}

private actor BatteryHistoryFile {
    static let shared = BatteryHistoryFile()
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "dev/Monitoring/battery.json")
    func read() -> [BatteryHistoryPoint] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
              let data = try? Data(contentsOf: url), let points = try? JSONDecoder().decode([BatteryHistoryPoint].self, from: data) else { return [] }
        return points.filter { (0...100).contains($0.charge) && $0.screenSeconds.isFinite && (0...90).contains($0.screenSeconds) && $0.date > Date.now.addingTimeInterval(-7 * 86400) && $0.date <= .now }.sorted { $0.date < $1.date }
    }
    func save(_ points: [BatteryHistoryPoint]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(points).write(to: url, options: .atomic)
    }
}

struct BatteryHistoryView: View {
    @State private var points: [BatteryHistoryPoint] = []
    @State private var days = 1
    @State private var saveError = false
    private var visible: [BatteryHistoryPoint] { points.filter { $0.date > Date.now.addingTimeInterval(-Double(days) * 86400) } }
    private var hours: [(date: Date, minutes: Double)] {
        let calendar = Calendar.current
        return Dictionary(grouping: visible, by: { calendar.dateInterval(of: .hour, for: $0.date)?.start ?? $0.date })
            .map { (date: $0.key, minutes: $0.value.reduce(0) { $0 + $1.screenSeconds } / 60) }.sorted { $0.date < $1.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Battery history", selection: $days) { Text("Last 24 hours").tag(1); Text("Last 7 days").tag(7) }.pickerStyle(.segmented)
            if let last = points.last(where: \.charging) {
                Text("Last observed charging: \(last.charge)% · \(last.date.formatted(date: .abbreviated, time: .shortened))").workspaceFont(.caption).foregroundStyle(.secondary)
            }
            Text("Battery level").workspaceFont(.headline)
            Chart(visible) { point in
                BarMark(x: .value("Time", point.date), y: .value("Charge", point.charge), width: 3)
                    .foregroundStyle(point.charging ? Color.green : Color.green.opacity(0.65))
            }.chartYScale(domain: 0...100).frame(height: 130)
            Text("Screen-on usage · sampled minutes per hour").workspaceFont(.headline)
            Chart(hours, id: \.date) { hour in
                BarMark(x: .value("Hour", hour.date, unit: .hour), y: .value("Minutes", min(60, hour.minutes))).foregroundStyle(.blue)
            }.chartYScale(domain: 0...60).frame(height: 110)
            Text("Collected each minute while Computer is open. Screen-on estimates use this Mac’s main display; sleep, closed-tab and earlier history are gaps. Green indicates charge; brighter bars indicate charging. Seven days stay locally.")
                .workspaceFont(.caption).foregroundStyle(.secondary)
            if points.isEmpty { Text("Waiting for the first battery sample…").workspaceFont(.caption).foregroundStyle(.secondary) }
            if saveError { Text("Battery history could not be saved.").workspaceFont(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity)
        .task {
            points = await BatteryHistoryFile.shared.read()
            var previous: Date?
            while !Task.isCancelled {
                let now = Date.now
                let battery = await Task.detached(priority: .utility) { ComputerBattery.read() }.value
                guard !Task.isCancelled else { return }
                if let charge = battery?.charge {
                    points.removeAll { $0.date < now.addingTimeInterval(-7 * 86400) }
                    points.append(.init(date: now, charge: charge, charging: battery?.state == "Charging", screenSeconds: BatteryHistoryMath.screenSeconds(previous: previous, now: now, awake: CGDisplayIsAsleep(CGMainDisplayID()) == 0)))
                    points = Array(points.suffix(10_080))
                    do { try await BatteryHistoryFile.shared.save(points); saveError = false } catch { saveError = true }
                }
                previous = now
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
}
