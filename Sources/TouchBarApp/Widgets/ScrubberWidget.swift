import AppKit

/// A horizontally swipeable strip of cells. This is the most gesture-native
/// Touch Bar control there is: flick to scroll through more entries than the
/// bar could ever show at once, tap one to fire its action.
///
/// Good for app launchers and snippet lists — it sidesteps the width limit
/// that silently drops overflowing items from a flat bar.
final class ScrubberWidget: NSObject, Widget, NSScrubberDataSource, NSScrubberDelegate,
                            NSScrubberFlowLayoutDelegate {
    private struct Entry {
        let title: String
        let action: ActionSpec
    }

    let identifier: NSTouchBarItem.Identifier
    private let entries: [Entry]
    private let cellWidth: CGFloat
    private let itemIdentifier = NSUserInterfaceItemIdentifier("cell")

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        cellWidth = CGFloat(options.double("cellWidth", 70))
        entries = (options.raw["items"]?.arrayValue ?? []).compactMap { value in
            guard case .object(let dict) = value else { return nil }
            let opts = Options(raw: dict)
            return Entry(title: opts.string("title", "•"), action: ActionSpec(options: opts))
        }
        super.init()
    }

    func makeItem() -> NSTouchBarItem? {
        guard !entries.isEmpty else {
            Log.widget.error("scrubber \(self.identifier.rawValue, privacy: .public) has no items")
            return nil
        }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let scrubber = NSScrubber()
        scrubber.register(NSScrubberTextItemView.self, forItemIdentifier: itemIdentifier)
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.mode = .free                    // free-scrolling, not snap-to-select
        scrubber.showsArrowButtons = false
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.backgroundColor = .clear
        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 6
        scrubber.scrubberLayout = layout
        item.view = scrubber
        return item
    }

    // MARK: - NSScrubberDataSource

    func numberOfItems(for scrubber: NSScrubber) -> Int { entries.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: itemIdentifier, owner: nil)
            as? NSScrubberTextItemView ?? NSScrubberTextItemView()
        view.textField.stringValue = entries[index].title
        view.textField.font = BarStyle.font
        return view
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout,
                  sizeForItemAt itemIndex: Int) -> NSSize {
        NSSize(width: cellWidth, height: 30)
    }

    // MARK: - NSScrubberDelegate

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        guard entries.indices.contains(index) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        entries[index].action.run()
        // Leave nothing selected: these are commands, not a persistent choice.
        scrubber.selectedIndex = -1
    }
}

/// Fixed set of choices rendered as one connected control, with the current
/// pick highlighted. Unlike the scrubber, selection sticks.
final class SegmentedWidget: NSObject, Widget {
    private struct Segment {
        let title: String
        let action: ActionSpec
    }

    let identifier: NSTouchBarItem.Identifier
    private let segments: [Segment]
    private let selectedIndex: Int

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        selectedIndex = options.int("selected", 0)
        segments = (options.raw["segments"]?.arrayValue ?? []).compactMap { value in
            guard case .object(let dict) = value else { return nil }
            let opts = Options(raw: dict)
            return Segment(title: opts.string("title", "•"), action: ActionSpec(options: opts))
        }
        super.init()
    }

    func makeItem() -> NSTouchBarItem? {
        guard !segments.isEmpty else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let control = NSSegmentedControl(labels: segments.map(\.title),
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(changed(_:)))
        control.font = BarStyle.font
        if segments.indices.contains(selectedIndex) {
            control.selectedSegment = selectedIndex
        }
        item.view = control
        return item
    }

    @objc private func changed(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard segments.indices.contains(index) else { return }
        segments[index].action.run()
    }
}
