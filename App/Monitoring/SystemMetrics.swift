import Foundation
import Darwin

struct SystemCounters: Sendable {
    let date: Date
    let memoryUsed: Double
    let memoryTotal: Double
    let swapUsed: Double
    let diskFree: Double
    let cpuBusy: UInt64
    let cpuTotal: UInt64
    let received: UInt64
    let sent: UInt64

    static func read() -> Self? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var cpu = host_cpu_load_info()
        count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard cpuResult == KERN_SUCCESS else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 else { return nil }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Double(sysconf(_SC_PAGESIZE))
        let disk = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        guard let (received, sent) = networkCounters() else { return nil }
        let ticks = cpu.cpu_ticks
        let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
        return Self(date: .now, memoryUsed: min(used, total), memoryTotal: total, swapUsed: Double(swap.xsu_used), diskFree: disk, cpuBusy: busy, cpuTotal: busy + UInt64(ticks.2), received: received, sent: sent)
    }

    private static func networkCounters() -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0, size < 10_000_000 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 6, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { bytes in
            var offset = 0
            var received: UInt64 = 0
            var sent: UInt64 = 0
            while offset + 4 <= size {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return nil }
                if bytes[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                    let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil,
                       String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix("en") {
                        received += message.ifm_data.ifi_ibytes
                        sent += message.ifm_data.ifi_obytes
                    }
                }
                offset += length
            }
            return (received, sent)
        }
    }

}

struct MonitoringSample: Codable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let memoryUsed: Double
    let memoryTotal: Double
    let swapUsed: Double
    let diskFree: Double
    let cpuPercent: Double?
    let download: Double?
    let upload: Double?

    init(current: SystemCounters, previous: SystemCounters?) {
        date = current.date
        memoryUsed = current.memoryUsed
        memoryTotal = current.memoryTotal
        swapUsed = current.swapUsed
        diskFree = current.diskFree
        let elapsed = previous.map { current.date.timeIntervalSince($0.date) } ?? 0
        if let previous, elapsed > 0, elapsed < 30 {
            cpuPercent = current.cpuTotal > previous.cpuTotal && current.cpuBusy >= previous.cpuBusy
                ? min(100, 100 * Double(current.cpuBusy - previous.cpuBusy) / Double(current.cpuTotal - previous.cpuTotal)) : nil
            download = Self.rate(current.received, previous.received, elapsed: elapsed)
            upload = Self.rate(current.sent, previous.sent, elapsed: elapsed)
        } else {
            cpuPercent = nil
            download = nil
            upload = nil
        }
    }

    static func rate(_ current: UInt64, _ previous: UInt64, elapsed: Double) -> Double? {
        guard current >= previous, elapsed > 0 else { return nil }
        return Double(current - previous) / elapsed
    }
}
