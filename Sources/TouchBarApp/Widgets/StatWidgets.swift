import AppKit

final class ClockWidget: TextWidget {
    private let formatter = DateFormatter()

    init(id: String, options: Options) {
        formatter.dateFormat = options.string("format", "EEE HH:mm")
        if let tz = options.string("timeZone").flatMap(TimeZone.init(identifier:)) {
            formatter.timeZone = tz
        }
        super.init(id: id)
    }

    override func render() -> String? { formatter.string(from: Date()) }
}

final class CPUWidget: TextWidget {
    private let sampler = CPUSampler()
    private let prefix: String
    private var last: Double = 0

    init(id: String, options: Options) {
        prefix = options.string("prefix", "CPU")
        super.init(id: id)
        _ = sampler.sample() // prime the delta so the first tick has a baseline
    }

    override func render() -> String? {
        if let v = sampler.sample() { last = v }
        return String(format: "%@ %3.0f%%", prefix, last * 100)
    }
}

final class MemoryWidget: TextWidget {
    private let sampler = MemorySampler()
    private let prefix: String
    private let showBytes: Bool

    init(id: String, options: Options) {
        prefix = options.string("prefix", "RAM")
        showBytes = options.bool("showBytes", false)
        super.init(id: id)
    }

    override func render() -> String? {
        guard let s = sampler.sample() else { return nil }
        if showBytes {
            return "\(prefix) \(ByteFormat.gb(s.usedBytes))/\(ByteFormat.gb(s.totalBytes))"
        }
        return String(format: "%@ %3.0f%%", prefix, s.usedFraction * 100)
    }
}

final class BatteryWidget: TextWidget {
    private let sampler = BatterySampler()
    private let showTime: Bool

    // Battery moves slowly; no reason to poll it every second.
    override var tickDivisor: Int { 10 }

    init(id: String, options: Options) {
        showTime = options.bool("showTime", false)
        super.init(id: id)
    }

    override func render() -> String? {
        guard let s = sampler.sample() else { return nil }
        let icon = s.isCharging ? "⚡" : (s.isPlugged ? "🔌" : "🔋")
        var text = "\(icon) \(s.percent)%"
        if showTime, let m = s.minutesRemaining {
            text += String(format: " %d:%02d", m / 60, m % 60)
        }
        return text
    }
}

final class NetworkWidget: TextWidget {
    private let sampler = NetSampler()
    private var last = NetRates(downBytesPerSecond: 0, upBytesPerSecond: 0)

    init(id: String, options: Options) {
        super.init(id: id)
        _ = sampler.sample() // prime the delta
    }

    override func render() -> String? {
        if let r = sampler.sample() { last = r }
        return "↓\(ByteFormat.rate(last.downBytesPerSecond)) ↑\(ByteFormat.rate(last.upBytesPerSecond))"
    }
}

/// Fixed-width blank space between groups of widgets.
final class SpacerWidget: Widget {
    let identifier: NSTouchBarItem.Identifier
    private let width: CGFloat

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        width = CGFloat(options.double("width", 16))
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        item.view = view
        return item
    }
}
