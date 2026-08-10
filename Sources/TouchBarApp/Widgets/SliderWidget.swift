import AppKit

/// A draggable slider. `NSSliderTouchBarItem` gets the native Touch Bar
/// treatment — you can slide straight from the tap, no press-then-drag.
///
/// Built-in `target: "volume"` drives system output volume; anything else runs
/// the configured action with the value in `{value}` / `$VALUE`.
final class SliderWidget: NSObject, Widget {
    let identifier: NSTouchBarItem.Identifier
    private let label: String
    private let minValue: Double
    private let maxValue: Double
    private let builtin: String?
    private let action: ActionSpec
    private var slider: NSSlider?

    /// Only used to re-sync the knob with the system when we own volume.
    var tickDivisor: Int { 10 }

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        label = options.string("label", "")
        minValue = options.double("min", 0)
        maxValue = options.double("max", 100)
        builtin = options.string("target")
        action = ActionSpec(options: options)
        super.init()
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSSliderTouchBarItem(identifier: identifier)
        item.label = label.isEmpty ? nil : label
        item.slider.minValue = minValue
        item.slider.maxValue = maxValue
        item.slider.doubleValue = currentValue() ?? minValue
        item.target = self
        item.action = #selector(changed(_:))
        slider = item.slider
        return item
    }

    func tick() {
        // Keep the knob honest if the volume was changed elsewhere, but never
        // while the user is dragging it.
        guard builtin == "volume", let slider, slider.window?.firstResponder !== slider else { return }
        if let value = currentValue(), abs(value - slider.doubleValue) > 1 {
            slider.doubleValue = value
        }
    }

    @objc private func changed(_ sender: Any?) {
        guard let slider else { return }
        let value = slider.doubleValue
        switch builtin {
        case "volume":
            SystemVolume.set(percent: value)
        default:
            action.run(value: value)
        }
    }

    private func currentValue() -> Double? {
        builtin == "volume" ? SystemVolume.get() : nil
    }
}

/// System output volume over AppleScript. No private API needed — `set volume`
/// is part of Standard Additions and does not require Automation consent,
/// since the target is the system rather than another app.
enum SystemVolume {
    static func get() -> Double? {
        var error: NSDictionary?
        let result = NSAppleScript(source: "output volume of (get volume settings)")?
            .executeAndReturnError(&error)
        if error != nil { return nil }
        guard let result else { return nil }
        return Double(result.int32Value)
    }

    static func set(percent: Double) {
        let clamped = Int(min(max(percent, 0), 100))
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "set volume output volume \(clamped)")?
                .executeAndReturnError(&error)
            if let error {
                Log.widget.error("volume set failed: \(error, privacy: .public)")
            }
        }
    }
}
