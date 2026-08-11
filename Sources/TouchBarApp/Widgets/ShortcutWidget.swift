import AppKit

/// A tappable button. Uses a plain NSButton when only a tap is bound, and
/// swaps to GestureView as soon as any gesture is configured — NSButton's own
/// tracking would otherwise eat the touches.
final class ShortcutWidget: NSObject, Widget {
    let identifier: NSTouchBarItem.Identifier
    private let title: String
    private let tint: NSColor?
    private let tap: ActionSpec
    private let bindings: GestureView.Bindings

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        title = options.string("title", "•")
        tint = options.string("color").flatMap(NSColor.fromHex)
        tap = ActionSpec(options: options)

        var bindings = GestureView.Bindings()
        bindings.tap = tap
        bindings.longPress = ActionSpec(nested: options.raw["longPress"])
        bindings.swipeLeft = ActionSpec(nested: options.raw["swipeLeft"])
        bindings.swipeRight = ActionSpec(nested: options.raw["swipeRight"])
        bindings.pan = ActionSpec(nested: options.raw["pan"])
        self.bindings = bindings
        super.init()
    }

    /// Always GestureView, even with only a tap bound: it is what carries the
    /// press ripple and the gradient bezel. NSButton would render neither.
    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = GestureView(title: title, tint: tint, bindings: bindings)
        return item
    }
}

extension NSColor {
    /// "#RRGGBB" or "RRGGBB".
    static func fromHex(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255,
                       alpha: 1)
    }
}
