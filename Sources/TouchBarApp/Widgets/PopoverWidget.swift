import AppKit

/// Navigation target for group widgets.
protocol BarNavigating: AnyObject {
    func push(_ widgets: [Widget])
    func pop()
}

/// A group that collapses to a single button and swaps the bar's contents for
/// its children when tapped, with a Back button to return.
///
/// Deliberately NOT `NSPopoverTouchBarItem`: popover items expect a Touch Bar
/// supplied through the responder chain, and ours is presented directly via the
/// private system-modal API — the popover simply never opens there. Driving the
/// item list ourselves works regardless of how the bar got on screen.
///
/// This is also the answer to a crowded bar: NSTouchBar silently drops items
/// that overflow the ~1085pt width, so extras go one tap deep instead.
final class GroupWidget: NSObject, Widget {
    let identifier: NSTouchBarItem.Identifier
    private let label: String
    private let tint: NSColor?
    private let childWidgets: [Widget]

    weak var navigator: BarNavigating?

    var children: [Widget] { childWidgets }

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        label = options.string("label", "•••")
        tint = options.string("color").flatMap(NSColor.fromHex)

        // Nested widgets use the same schema as the top level, so groups can
        // hold anything a bar can hold — including other groups.
        let nested = options.raw["widgets"]?.arrayValue ?? []
        let configs: [WidgetConfig] = nested.compactMap { value in
            guard case .object(let dict) = value else { return nil }
            let opts = Options(raw: dict)
            guard let type = opts.string("type") else { return nil }
            let childOptions: [String: JSONValue]?
            if case .object(let o)? = dict["options"] { childOptions = o } else { childOptions = nil }
            return WidgetConfig(type: type, id: opts.string("id"), options: childOptions)
        }
        childWidgets = WidgetRegistry.build(configs, idPrefix: id)
        super.init()
    }

    func makeItem() -> NSTouchBarItem? {
        guard !childWidgets.isEmpty else {
            Log.widget.error("group \(self.identifier.rawValue, privacy: .public) has no widgets")
            return nil
        }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = BarStyle.button(title: label, target: self, action: #selector(open))
        if let tint { button.bezelColor = tint }
        item.view = button
        return item
    }

    @objc private func open() {
        guard let navigator else {
            Log.widget.error("group \(self.identifier.rawValue, privacy: .public) has no navigator")
            return
        }
        Log.widget.notice("group \(self.identifier.rawValue, privacy: .public) opened with \(self.childWidgets.count) child(ren)")
        navigator.push(childWidgets)
    }
}
