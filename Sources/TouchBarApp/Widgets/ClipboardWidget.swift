import AppKit

/// Swipeable clipboard history. Polls `NSPasteboard.changeCount` — there is no
/// change notification for the pasteboard, so polling is the only option, but
/// comparing an integer once a second costs nothing.
///
/// Tapping an entry puts it back on the pasteboard and (optionally) synthesizes
/// cmd+V into the frontmost app.
final class ClipboardWidget: NSObject, Widget, NSScrubberDataSource, NSScrubberDelegate,
                             NSScrubberFlowLayoutDelegate {
    let identifier: NSTouchBarItem.Identifier
    private let capacity: Int
    private let cellWidth: CGFloat
    private let shouldPaste: Bool

    private var entries: [String] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private weak var scrubber: NSScrubber?
    private let itemIdentifier = NSUserInterfaceItemIdentifier("clip")

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        capacity = max(1, options.int("capacity", 12))
        cellWidth = CGFloat(options.double("cellWidth", 110))
        shouldPaste = options.bool("paste", true)
        super.init()
        capture()   // seed with whatever is on the pasteboard right now
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let scrubber = NSScrubber()
        scrubber.register(NSScrubberTextItemView.self, forItemIdentifier: itemIdentifier)
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.mode = .free
        scrubber.showsArrowButtons = false
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.backgroundColor = .clear
        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 6
        scrubber.scrubberLayout = layout
        self.scrubber = scrubber
        item.view = scrubber
        return item
    }

    func tick() {
        guard NSPasteboard.general.changeCount != lastChangeCount else { return }
        capture()
        scrubber?.reloadData()
    }

    private func capture() {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    // MARK: - NSScrubberDataSource

    func numberOfItems(for scrubber: NSScrubber) -> Int { entries.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: itemIdentifier, owner: nil)
            as? NSScrubberTextItemView ?? NSScrubberTextItemView()
        // Newlines would render as a single tall blank cell.
        let preview = entries[index]
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(40)
        view.textField.stringValue = String(preview)
        view.textField.font = BarStyle.smallFont
        return view
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout,
                  sizeForItemAt itemIndex: Int) -> NSSize {
        NSSize(width: cellWidth, height: 30)
    }

    // MARK: - NSScrubberDelegate

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        guard entries.indices.contains(index) else { return }
        let text = entries[index]

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount   // don't re-capture our own write

        // Move it to the front so the most recently used stays reachable.
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        scrubber.reloadData()
        scrubber.selectedIndex = -1
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        guard shouldPaste else { return }
        // Small delay: the pasteboard write must land before the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ActionSpec(options: Options(raw: [
                "action": .string("hotkey"),
                "keys": .array([.string("cmd"), .string("v")])
            ])).run()
        }
    }
}
