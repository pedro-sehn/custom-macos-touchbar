import Foundation
import IOKit.ps

struct BatteryStats {
    let percent: Int
    let isCharging: Bool
    let isPlugged: Bool
    /// Minutes remaining; nil while the estimate is still being calculated.
    let minutesRemaining: Int?
}

final class BatterySampler {
    func sample() -> BatteryStats? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // Negative values mean "not yet calculated".
            let raw = charging
                ? desc[kIOPSTimeToFullChargeKey] as? Int
                : desc[kIOPSTimeToEmptyKey] as? Int
            let minutes = (raw ?? -1) > 0 ? raw : nil

            return BatteryStats(percent: Int(round(Double(current) / Double(max) * 100)),
                                isCharging: charging,
                                isPlugged: plugged,
                                minutesRemaining: minutes)
        }
        return nil
    }
}
