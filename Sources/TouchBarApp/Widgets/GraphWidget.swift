import AppKit

/// A live sparkline. Text tells you the current number; a graph tells you
/// whether it's climbing — which is usually the question you actually had.
final class GraphWidget: NSObject, Widget {
    enum Source: String {
        case cpu, memory, network
    }

    let identifier: NSTouchBarItem.Identifier
    private let source: Source
    private let width: CGFloat
    private let caption: String
    private let color: NSColor
    /// When set, the line colour tracks the value (green → amber → red)
    /// instead of staying fixed.
    private let reactive: Bool

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let net = NetSampler()
    /// Autoscaled per-window, so network traffic stays legible across four
    /// orders of magnitude without a log axis.
    private var peak: Double = 1

    private var view: SparklineView?

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        source = Source(rawValue: options.string("source", "cpu")) ?? .cpu
        width = CGFloat(options.double("width", 90))
        caption = options.string("caption", "")
        color = options.string("color").flatMap(NSColor.fromHex) ?? NSColor.systemGreen
        reactive = options.bool("reactive", options.raw["color"] == nil)
        super.init()
        _ = sample()   // prime the delta-based samplers
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = SparklineView(color: color, caption: caption, reactive: reactive)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        self.view = view
        item.view = view
        return item
    }

    func tick() {
        guard let value = sample() else { return }
        switch source {
        case .cpu, .memory:
            view?.push(value, label: String(format: "%.0f%%", value * 100))
        case .network:
            peak = max(peak * 0.95, value, 1)   // decay so a spike doesn't flatten the rest forever
            view?.push(value / peak, label: ByteFormat.rate(value))
        }
    }

    /// Returns 0...1 for cpu/memory, raw bytes/sec for network.
    private func sample() -> Double? {
        switch source {
        case .cpu:     return cpu.sample()
        case .memory:  return memory.sample()?.usedFraction
        case .network: return net.sample().map { $0.downBytesPerSecond + $0.upBytesPerSecond }
        }
    }
}

/// Ring-buffered line chart. Redraws only when a new sample arrives.
final class SparklineView: NSView {
    private var samples: [Double] = []
    private var capacity = 60
    private let baseColor: NSColor
    private let caption: String
    private let reactive: Bool
    private var label = ""

    /// Colour eases toward its target rather than snapping, so a single spiky
    /// sample doesn't strobe the widget.
    private var displayedColor: NSColor

    init(color: NSColor, caption: String, reactive: Bool) {
        self.baseColor = color
        self.caption = caption
        self.reactive = reactive
        self.displayedColor = reactive ? Appearance.heat(0) : color
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func push(_ value: Double, label: String) {
        let clamped = min(max(value, 0), 1)
        samples.append(clamped)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        self.label = label
        if reactive {
            displayedColor = Appearance.lerp(displayedColor, Appearance.heat(clamped), 0.35)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        guard samples.count > 1 else { return }

        let inset: CGFloat = 3
        let plot = bounds.insetBy(dx: inset, dy: inset)
        let step = plot.width / CGFloat(capacity - 1)
        // Right-align: newest sample hugs the right edge until the buffer fills.
        let offset = plot.maxX - CGFloat(samples.count - 1) * step

        let line = NSBezierPath()
        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: offset, y: plot.minY))
        for (index, value) in samples.enumerated() {
            let point = NSPoint(x: offset + CGFloat(index) * step,
                                y: plot.minY + plot.height * CGFloat(value))
            index == 0 ? line.move(to: point) : line.line(to: point)
            fill.line(to: point)
        }
        fill.line(to: NSPoint(x: plot.maxX, y: plot.minY))
        fill.close()

        let color = reactive ? displayedColor : baseColor
        // Gradient under the curve reads as depth without stealing contrast
        // from the label sitting on top of it.
        NSGradient(colors: [color.withAlphaComponent(0.45), color.withAlphaComponent(0.04)])?
            .draw(in: fill, angle: 90)
        color.setStroke()
        line.lineWidth = 1.5
        line.stroke()

        let text = caption.isEmpty ? label : "\(caption) \(label)"
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: BarStyle.smallFont,
            .foregroundColor: NSColor.white
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: plot.minX + 2, y: plot.maxY - 13))
    }
}
