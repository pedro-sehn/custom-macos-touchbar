import Darwin
import Foundation

struct MemoryStats {
    let usedBytes: UInt64
    let totalBytes: UInt64
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

/// Memory pressure numbers from `host_statistics64(HOST_VM_INFO64)`.
///
/// "Used" here = active + wired + compressed, which tracks Activity Monitor's
/// "Memory Used" closely but not to the byte (Apple also nets out some
/// purgeable and external pages).
final class MemorySampler {
    private let pageSize = UInt64(vm_kernel_page_size)
    private let total = ProcessInfo.processInfo.physicalMemory

    func sample() -> MemoryStats? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            Log.widget.error("host_statistics64 failed: \(result)")
            return nil
        }
        let used = (UInt64(stats.active_count)
                    + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize
        return MemoryStats(usedBytes: used, totalBytes: total)
    }
}

enum ByteFormat {
    /// Compact, fixed-ish width so the bar doesn't reflow every second.
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1fG", Double(bytes) / 1_073_741_824)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let b = max(0, bytesPerSecond)
        if b < 1_000 { return String(format: "%3.0fB", b) }
        if b < 1_000_000 { return String(format: "%3.0fK", b / 1_000) }
        if b < 1_000_000_000 { return String(format: "%3.1fM", b / 1_000_000) }
        return String(format: "%3.1fG", b / 1_000_000_000)
    }
}
