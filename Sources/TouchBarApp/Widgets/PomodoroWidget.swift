import AppKit

/// Tap to start/pause, long-press to reset. Draws its own progress fill so the
/// countdown is readable at a glance without reading the digits.
final class PomodoroWidget: NSObject, Widget {
    private enum Phase {
        case idle, work, rest
    }

    let identifier: NSTouchBarItem.Identifier
    private let workSeconds: Double
    private let restSeconds: Double
    private let notifyOnFinish: Bool

    private var phase: Phase = .idle
    private var remaining: Double = 0
    private var isPaused = false
    private var view: PomodoroView?

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        workSeconds = options.double("minutes", 25) * 60
        restSeconds = options.double("breakMinutes", 5) * 60
        notifyOnFinish = options.bool("notify", true)
        super.init()
        remaining = workSeconds
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = PomodoroView(onTap: { [weak self] in self?.tapped() },
                                onLongPress: { [weak self] in self?.reset() })
        view.setTickInterval(Ticker.currentInterval)
        self.view = view
        item.view = view
        render()
        return item
    }

    /// Driven by the shared 1 Hz ticker rather than its own timer — a second of
    /// drift on a 25 minute timer is not worth a second timer source.
    func tick() {
        guard phase != .idle, !isPaused else { return }
        remaining -= 1
        if remaining <= 0 { advance() }
        render()
    }

    // MARK: - Transitions

    private func tapped() {
        switch phase {
        case .idle:
            phase = .work
            remaining = workSeconds
            isPaused = false
        default:
            isPaused.toggle()
        }
        haptic(.levelChange)
        render()
    }

    private func reset() {
        phase = .idle
        isPaused = false
        remaining = workSeconds
        haptic(.generic)
        render()
    }

    private func advance() {
        let finished = phase
        phase = (phase == .work) ? .rest : .work
        remaining = (phase == .work) ? workSeconds : restSeconds
        haptic(.levelChange)
        view?.flash(phase == .rest ? .systemTeal : .systemRed)
        guard notifyOnFinish else { return }
        notify(finished == .work ? "Pomodoro done — take a break"
                                 : "Break over — back to work")
    }

    private func render() {
        let total: Double
        switch phase {
        case .idle: total = workSeconds
        case .work: total = workSeconds
        case .rest: total = restSeconds
        }
        let minutes = Int(max(remaining, 0)) / 60
        let seconds = Int(max(remaining, 0)) % 60
        let icon: String
        switch phase {
        case .idle: icon = "🍅"
        case .work: icon = isPaused ? "⏸" : "🍅"
        case .rest: icon = isPaused ? "⏸" : "☕"
        }
        view?.update(progress: total > 0 ? 1 - (remaining / total) : 0,
                     text: String(format: "%@ %d:%02d", icon, minutes, seconds),
                     color: phase == .rest ? .systemTeal : .systemRed,
                     dimmed: phase == .idle || isPaused)
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func notify(_ message: String) {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: "display notification \"\(escaped)\" with title \"Pomodoro\"")?
                .executeAndReturnError(&error)
        }
    }
}

/// Progress-filled pill with centred label.
///
/// Layer-backed rather than `draw(_:)`-based: the fill is animated across the
/// full tick interval, so a once-per-second countdown reads as a smooth sweep
/// instead of a staircase. Core Animation does the interpolation on its own
/// thread, so this costs nothing extra per frame.
final class PomodoroView: NSView {
    private let fillLayer = CAGradientLayer()
    private let label = BarStyle.label("🍅")

    private var progress: Double = 0
    private var tickInterval: CFTimeInterval = 1.0

    private let onTap: () -> Void
    private let onLongPress: () -> Void

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        layer?.masksToBounds = true

        fillLayer.startPoint = CGPoint(x: 0, y: 0)
        fillLayer.endPoint = CGPoint(x: 1, y: 0)
        fillLayer.frame = .zero
        layer?.addSublayer(fillLayer)

        // Subviews render above sublayers, so the label stays legible over the fill.
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let tap = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress))
        press.minimumPressDuration = 0.45
        for recognizer in [tap, press] as [NSGestureRecognizer] {
            recognizer.allowedTouchTypes = [.direct]
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setTickInterval(_ interval: TimeInterval) { tickInterval = max(0.2, interval) }

    func update(progress: Double, text: String, color: NSColor, dimmed: Bool) {
        label.stringValue = text
        label.textColor = dimmed ? NSColor(white: 0.75, alpha: 1) : .white

        let alpha: CGFloat = dimmed ? 0.32 : 0.7
        fillLayer.colors = [
            color.withAlphaComponent(alpha * 0.75).cgColor,
            color.withAlphaComponent(alpha).cgColor
        ]

        let target = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(min(max(progress, 0), 1)),
                            height: bounds.height)
        // Jumping backwards (reset, phase change) should snap, not rewind.
        let isAdvance = progress > self.progress
        self.progress = progress
        Appearance.animate(duration: isAdvance ? tickInterval : 0) {
            fillLayer.frame = target
        }
    }

    /// Autolayout can resize us after the last update; keep the fill in step.
    override func layout() {
        super.layout()
        Appearance.animate(duration: 0) {
            fillLayer.frame = CGRect(x: 0, y: 0,
                                     width: bounds.width * CGFloat(progress),
                                     height: bounds.height)
        }
    }

    /// Flash on completion so a finished timer is noticeable without watching it.
    func flash(_ color: NSColor) {
        guard let layer else { return }
        Appearance.pulse(layer, to: color, duration: 0.5)
    }

    @objc private func handleTap() { onTap() }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onLongPress()
    }
}
