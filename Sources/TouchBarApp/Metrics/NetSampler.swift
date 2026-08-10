import Darwin
import Foundation

struct NetRates {
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
}

/// Byte counters off `getifaddrs` AF_LINK entries, differenced over time.
///
/// Counters are 32-bit in `if_data` and wrap; a negative delta is treated as a
/// wrap and reported as zero rather than a nonsense spike.
final class NetSampler {
    private var prevIn: UInt64 = 0
    private var prevOut: UInt64 = 0
    private var prevAt: CFAbsoluteTime = 0

    /// Interface name prefixes to count. Loopback and virtual bridges excluded.
    private let prefixes = ["en", "pdp_ip", "utun", "awdl0"]

    func sample() -> NetRates? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return nil }
        defer { freeifaddrs(head) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard prefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            totalIn &+= UInt64(data.pointee.ifi_ibytes)
            totalOut &+= UInt64(data.pointee.ifi_obytes)
        }

        let now = CFAbsoluteTimeGetCurrent()
        defer { prevIn = totalIn; prevOut = totalOut; prevAt = now }
        guard prevAt > 0 else { return nil }
        let dt = now - prevAt
        guard dt > 0.05 else { return nil }

        let down = totalIn >= prevIn ? Double(totalIn - prevIn) / dt : 0
        let up = totalOut >= prevOut ? Double(totalOut - prevOut) / dt : 0
        return NetRates(downBytesPerSecond: down, upBytesPerSecond: up)
    }
}
