import AppKit

/// Owns the widget list, the NSTouchBar built from it, the shared ticker, and
/// navigation into and out of group widgets.
final class TouchBarController: NSObject, NSTouchBarDelegate, BarNavigating {
    static let controlStripIdentifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.controlStrip")
    private static let backIdentifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.back")

    private var widgets: [Widget] = []
    private var allWidgets: [Widget] = []
    private var itemsByIdentifier: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    private let ticker = Ticker()
    private(set) var touchBar: NSTouchBar?

    /// Identifier lists we came from, so Back can unwind more than one level.
    private var navigationStack: [[NSTouchBarItem.Identifier]] = []

    /// Called when the bar's contents change while it may be presented, so the
    /// system-modal presentation can be refreshed if it doesn't pick it up.
    var onItemsChanged: (() -> Void)?

    /// Rebuilds everything from a config. Safe to call repeatedly (hot reload).
    func rebuild(with config: AppConfig) {
        ticker.stop()
        ticker.removeAll()
        itemsByIdentifier.removeAll()
        navigationStack.removeAll()

        widgets = WidgetRegistry.build(config.widgets)
        allWidgets = Self.flatten(widgets)

        // Groups need a way back to this controller to drive navigation.
        for case let group as GroupWidget in allWidgets {
            group.navigator = self
        }

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = widgets.map(\.identifier)
        touchBar = bar

        for widget in allWidgets {
            let divisor = UInt64(max(1, widget.tickDivisor))
            ticker.add { [weak widget] count in
                guard let widget, count % divisor == 0 else { return }
                widget.tick()
            }
        }
        ticker.start(interval: config.refreshSeconds ?? 1.0)

        Log.app.notice("bar rebuilt: \(self.widgets.count) top-level, \(self.allWidgets.count) total widget(s)")
    }

    func stop() {
        ticker.stop()
        ticker.removeAll()
    }

    // MARK: - BarNavigating

    func push(_ children: [Widget]) {
        guard let bar = touchBar else { return }
        navigationStack.append(bar.defaultItemIdentifiers)
        setItems([Self.backIdentifier] + children.map(\.identifier))
    }

    func pop() {
        guard let previous = navigationStack.popLast() else { return }
        setItems(previous)
    }

    private func setItems(_ identifiers: [NSTouchBarItem.Identifier]) {
        guard let bar = touchBar else { return }
        bar.defaultItemIdentifiers = identifiers
        Log.app.notice("bar items -> \(identifiers.count) item(s)")
        onItemsChanged?()
    }

    private static func flatten(_ widgets: [Widget]) -> [Widget] {
        widgets.flatMap { [$0] + flatten($0.children) }
    }

    @objc private func back() { pop() }

    // MARK: - NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let existing = itemsByIdentifier[identifier] { return existing }

        if identifier == Self.backIdentifier {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = BarStyle.button(title: "‹ Back", target: self, action: #selector(back))
            itemsByIdentifier[identifier] = item
            return item
        }

        // Search the flattened tree: children of groups are requested too.
        guard let widget = allWidgets.first(where: { $0.identifier == identifier }),
              let item = widget.makeItem() else {
            Log.app.error("no item for \(identifier.rawValue, privacy: .public)")
            return nil
        }
        itemsByIdentifier[identifier] = item
        return item
    }
}
