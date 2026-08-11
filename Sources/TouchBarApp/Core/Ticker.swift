import Foundation

/// One timer for the whole app. Per-widget timers would multiply Touch Bar
/// redraws, and a CPU widget that burns CPU defeats itself.
final class Ticker {
    private var timer: Timer?
    private var count: UInt64 = 0
    private var handlers: [(UInt64) -> Void] = []
    private(set) var interval: TimeInterval

    /// The live tick rate, for views that pace animations to it. Set by
    /// `start()`; there is only ever one ticker.
    private(set) static var currentInterval: TimeInterval = 1.0

    init(interval: TimeInterval = 1.0) {
        self.interval = max(0.2, interval)
    }

    func add(_ handler: @escaping (UInt64) -> Void) {
        handlers.append(handler)
    }

    func removeAll() { handlers.removeAll() }

    func start(interval: TimeInterval? = nil) {
        if let interval { self.interval = max(0.2, interval) }
        Self.currentInterval = self.interval
        stop()
        let t = Timer(timeInterval: self.interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.count &+= 1
            let n = self.count
            for h in self.handlers { h(n) }
        }
        // .common so the bar keeps updating while a menu is open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
