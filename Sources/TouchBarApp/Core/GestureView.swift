import AppKit

/// A button-like Touch Bar view that understands tap, long-press, and
/// horizontal swipe/pan.
///
/// Not an NSButton: NSButton runs its own mouse tracking, which swallows the
/// touches that gesture recognizers need. Drawing the bezel ourselves is the
/// price of getting gestures at all.
final class GestureView: NSView {
    struct Bindings {
        var tap: ActionSpec?
        var longPress: ActionSpec?
        var swipeLeft: ActionSpec?
        var swipeRight: ActionSpec?
        /// Continuous horizontal drag. Receives 0...1 across the view's width.
        var pan: ActionSpec?
    }

    private let bindings: Bindings
    private let tint: NSColor?
    private var title: String
    private var image: NSImage?
    private var isPressed = false

    /// Ignore jitter: below this a pan is really just a sloppy tap.
    private let swipeThreshold: CGFloat = 24

    init(title: String, tint: NSColor?, bindings: Bindings) {
        self.bindings = bindings
        self.tint = tint
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        if title.hasEmoji { image = BarStyle.emojiImage(title) }
        installRecognizers()
        setContentSize()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setTitle(_ newTitle: String) {
        guard newTitle != title else { return }
        title = newTitle
        image = newTitle.hasEmoji ? BarStyle.emojiImage(newTitle) : nil
        setContentSize()
        needsDisplay = true
    }

    private func setContentSize() {
        let width: CGFloat
        if let image {
            width = image.size.width + 28
        } else {
            let size = NSAttributedString(string: title, attributes: [.font: BarStyle.font]).size()
            width = max(40, ceil(size.width) + 24)
        }
        translatesAutoresizingMaskIntoConstraints = false
        for c in constraints where c.firstAttribute == .width { removeConstraint(c) }
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    // MARK: - Recognizers

    private func installRecognizers() {
        let tap = NSClickGestureRecognizer(target: self, action: #selector(handleTap))
        let press = NSPressGestureRecognizer(target: self, action: #selector(handlePress))
        press.minimumPressDuration = 0.45
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan))

        for recognizer in [tap, press, pan] as [NSGestureRecognizer] {
            // Without .direct the Touch Bar's touches never reach the recognizer.
            recognizer.allowedTouchTypes = [.direct]
            addGestureRecognizer(recognizer)
        }
    }

    @objc private func handleTap() {
        flash()
        bindings.tap?.run()
    }

    @objc private func handlePress(_ recognizer: NSPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        guard let longPress = bindings.longPress else { return }
        haptic()
        longPress.run()
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        // Continuous mode wins if bound: report position across the width.
        if let pan = bindings.pan {
            guard recognizer.state == .changed || recognizer.state == .ended else { return }
            let x = recognizer.location(in: self).x
            pan.run(value: Double(min(max(x / max(bounds.width, 1), 0), 1)))
            return
        }

        guard recognizer.state == .ended else { return }
        let dx = recognizer.translation(in: self).x
        guard abs(dx) >= swipeThreshold else { return }
        haptic()
        (dx < 0 ? bindings.swipeLeft : bindings.swipeRight)?.run()
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func flash() {
        isPressed = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.isPressed = false
            self?.needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        let base = tint ?? NSColor(white: 0.22, alpha: 1)
        (isPressed ? base.highlight(withLevel: 0.3) ?? base : base).setFill()
        path.fill()

        if let image {
            let origin = NSPoint(x: (bounds.width - image.size.width) / 2,
                                 y: (bounds.height - image.size.height) / 2)
            image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: BarStyle.font,
                .foregroundColor: NSColor.white
            ]
            let string = NSAttributedString(string: title, attributes: attributes)
            let size = string.size()
            string.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                    y: (bounds.height - size.height) / 2))
        }
    }
}
