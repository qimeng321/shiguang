import Foundation

@main struct TestGameProtocolFramer {
    static func packet(_ cmd: UInt32, _ payload: [UInt8] = []) -> Data {
        let len = UInt32(17 + payload.count)
        func u32(_ x: UInt32) -> [UInt8] {
            [UInt8((x >> 24) & 255), UInt8((x >> 16) & 255), UInt8((x >> 8) & 255), UInt8(x & 255)]
        }
        var bytes = u32(len)
        bytes.append(1)
        bytes.append(contentsOf: u32(cmd))
        bytes.append(contentsOf: u32(101))
        bytes.append(contentsOf: u32(0))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    static func main() {
        let room = packet(10002, [UInt8](repeating: 23, count: 24) + [10, 2, 3, 4, 0x6D, 0x60])
        let other = packet(9003, [1, 2, 3, 4])
        let expected = packet(10002, [UInt8](repeating: 23, count: 24) +
                              [103, 91, 210, 16, 0x59, 0xBF]) + other
        var framer = GameProtocolFramer()
        var result = Data()
        var changedCount = 0
        for byte in room + other {
            result.append(framer.consume(Data([byte]), rewrite: { message in
                guard message == room else { return message }
                changedCount += 1
                var mapped = message
                mapped.replaceSubrange(41..<47, with: [103, 91, 210, 16, 0x59, 0xBF])
                return mapped
            }))
        }
        precondition(result == expected && changedCount == 1 && framer.bufferedBytes == 0)
        var combined = GameProtocolFramer()
        precondition(combined.consume(room + other, rewrite: { $0 }) == room + other)
        var incomplete = GameProtocolFramer()
        let partial = Data(room.prefix(13))
        precondition(incomplete.consume(partial, rewrite: { $0 }).isEmpty)
        precondition(incomplete.flushRemainder() == partial)
        print("PASS: split frames, merged frames, lossless pass-through and EOF")
    }
}
