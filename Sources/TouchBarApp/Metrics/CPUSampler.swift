import Darwin
import Foundation

/// Aggregate CPU load from `host_statistics(HOST_CPU_LOAD_INFO)`.
///
/// Deliberately not `host_processor_info`: that allocates a per-core array the
/// caller must `vm_deallocate`, and we only ever display the aggregate. Fewer
/// moving parts, no leak surface at 1 Hz.
final class CPUSampler {
    private var prev: host_cpu_load_info?

    /// Busy fraction 0...1 since the previous call. nil on the first call.
    func sample() -> Double? {
        guard let now = read() else { return nil }
        defer { prev = now }
        guard let old = prev else { return nil }

        let user = Double(now.cpu_ticks.0 &- old.cpu_ticks.0)
        let system = Double(now.cpu_ticks.1 &- old.cpu_ticks.1)
        let idle = Double(now.cpu_ticks.2 &- old.cpu_ticks.2)
        let nice = Double(now.cpu_ticks.3 &- old.cpu_ticks.3)

        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total
    }

    private func read() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            Log.widget.error("host_statistics(HOST_CPU_LOAD_INFO) failed: \(result)")
            return nil
        }
        return info
    }
}
