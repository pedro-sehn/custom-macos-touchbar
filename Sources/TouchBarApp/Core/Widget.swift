import AppKit

/// The plugin seam. Every bar element is a Widget; the registry turns a config
/// `type` string into one of these.
protocol Widget: AnyObject {
    var identifier: NSTouchBarItem.Identifier { get }

    /// Build the AppKit item. Called once per bar rebuild.
    func makeItem() -> NSTouchBarItem?

    /// Called on the shared ticker. Must be cheap and must not touch the
    /// Touch Bar unless the rendered value actually changed.
    func tick()

    /// How many ticks to skip between refreshes. 1 = every tick.
    var tickDivisor: Int { get }

    /// Widgets nested inside this one (popover groups). The controller
    /// flattens these so children still get ticked.
    var children: [Widget] { get }
}

extension Widget {
    func tick() {}
    var tickDivisor: Int { 1 }
    var children: [Widget] { [] }
}

/// Shared look for every text-style widget: monospaced digits so numbers don't
/// jitter the layout as they change width.
enum BarStyle {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    static func label(_ text: String = "") -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = font
        f.alignment = .center
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    /// Button factory for every tappable item.
    ///
    /// Emoji titles do not render on the Touch Bar when an explicit non-emoji
    /// font is set on the button — the glyph silently drops out while the
    /// button stays live, so it looks blank but still fires. Drawing the emoji
    /// into a non-template NSImage sidesteps font fallback entirely and keeps
    /// it in colour.
    static func button(title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        if title.hasEmoji {
            button.image = emojiImage(title)
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.font = font
        }
        return button
    }

    static func emojiImage(_ text: String, pointSize: CGFloat = 17) -> NSImage {
        let string = NSAttributedString(string: text,
                                        attributes: [.font: NSFont.systemFont(ofSize: pointSize)])
        var size = string.size()
        size.width = ceil(size.width)
        size.height = ceil(size.height)
        let image = NSImage(size: size)
        image.lockFocus()
        string.draw(at: .zero)
        image.unlockFocus()
        // Template images get tinted flat by the Touch Bar; we want the colours.
        image.isTemplate = false
        return image
    }
}

extension String {
    /// True for anything with emoji presentation, including the media
    /// transport symbols (⏮ ⏯ ⏭) which are emoji-presentation by default.
    var hasEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x2100)
        }
    }
}

/// Base class for widgets that render a single line of text and only push to
/// the Touch Bar when that text changes.
class TextWidget: Widget {
    let identifier: NSTouchBarItem.Identifier
    private(set) var label: NSTextField?
    private var lastText: String?

    /// Declared on the class (not left to the protocol extension) so subclasses
    /// can actually override it.
    var tickDivisor: Int { 1 }

    init(id: String) {
        self.identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let label = BarStyle.label(render() ?? "…")
        self.label = label
        lastText = label.stringValue
        item.view = label
        return item
    }

    /// Subclasses produce the text. Returning nil keeps the previous value.
    func render() -> String? { nil }

    func tick() {
        guard let text = render(), text != lastText else { return }
        lastText = text
        label?.stringValue = text
    }
}
