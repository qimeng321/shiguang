import Foundation

/// Assemble complete TCP protocol packets before inspecting commands.
struct GameProtocolFramer {
    private var waiting = Data()
    private let maximumPacketSize = 4 * 1024 * 1024
    mutating func consume(_ data: Data, rewrite: (Data) -> Data,
                          onAnomaly: (String) -> Void = { _ in }) -> Data {
        if waiting.isEmpty && data.isEmpty { return Data() }
        waiting.append(data)
        var output = Data()
        while waiting.count >= 4 {
            let length = waiting.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let packetSize = Int(length)
            guard packetSize >= 17 && packetSize <= maximumPacketSize else {
                onAnomaly("协议包长度无效（\(packetSize)），原样透传")
                output.append(waiting)
                waiting.removeAll(keepingCapacity: true)
                return output
            }
            if waiting.count < packetSize { break }
            let frame = Data(waiting.prefix(packetSize))
            let mapped = rewrite(frame)
            if mapped.count == frame.count { output.append(mapped) }
            else {
                onAnomaly("改写后长度异常，恢复原始数据")
                output.append(frame)
            }
            waiting.removeFirst(packetSize)
        }
        return output
    }

    mutating func flushRemainder() -> Data {
        let remainder = waiting
        waiting.removeAll(keepingCapacity: true)
        return remainder
    }
    var bufferedBytes: Int { waiting.count }
}
