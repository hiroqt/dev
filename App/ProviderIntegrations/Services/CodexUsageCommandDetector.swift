struct CodexUsageCommandDetector {
    private static let commands = [Array("/status".utf8), Array("/usage".utf8)]
    private var candidate: [UInt8] = []
    private var lineCanBeCommand = true

    mutating func consume(_ bytes: ArraySlice<UInt8>) -> Bool {
        var detected = false
        for byte in bytes {
            switch byte {
            case 0x0A, 0x0D:
                detected = detected || Self.commands.contains { $0 == candidate }
                candidate.removeAll(keepingCapacity: true)
                lineCanBeCommand = true
            case 0x08, 0x7F:
                if !candidate.isEmpty { candidate.removeLast() }
            case 0x03, 0x1B:
                candidate.removeAll(keepingCapacity: true)
                lineCanBeCommand = false
            case 0x20...0x7E:
                if candidate.isEmpty {
                    if byte == 0x2F && lineCanBeCommand {
                        candidate.append(byte)
                    } else {
                        lineCanBeCommand = false
                    }
                } else {
                    candidate.append(byte)
                    if !Self.commands.contains(where: { $0.starts(with: candidate) }) {
                        candidate.removeAll(keepingCapacity: true)
                        lineCanBeCommand = false
                    }
                }
            default:
                candidate.removeAll(keepingCapacity: true)
                lineCanBeCommand = false
            }
        }
        return detected
    }
}
