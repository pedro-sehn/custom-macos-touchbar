import AppKit

/// Config `type` string → widget factory. This is the whole plugin host: adding
/// a widget kind means writing the class and adding one line here.
enum WidgetRegistry {
    typealias Factory = (_ id: String, _ options: Options) -> Widget

    static let factories: [String: Factory] = [
        // Readouts
        "clock":     { ClockWidget(id: $0, options: $1) },
        "cpu":       { CPUWidget(id: $0, options: $1) },
        "memory":    { MemoryWidget(id: $0, options: $1) },
        "battery":   { BatteryWidget(id: $0, options: $1) },
        "network":   { NetworkWidget(id: $0, options: $1) },
        "graph":     { GraphWidget(id: $0, options: $1) },
        "spacer":    { SpacerWidget(id: $0, options: $1) },
        // Interactive
        "shortcut":  { ShortcutWidget(id: $0, options: $1) },
        "media":     { MediaWidget(id: $0, options: $1) },
        "slider":    { SliderWidget(id: $0, options: $1) },
        "scrubber":  { ScrubberWidget(id: $0, options: $1) },
        "segmented": { SegmentedWidget(id: $0, options: $1) },
        "group":     { GroupWidget(id: $0, options: $1) }
    ]

    /// Unknown types are skipped, never fatal — a typo in the config should
    /// cost you one widget, not the whole bar.
    ///
    /// `idPrefix` keeps nested groups from colliding with top-level ids.
    static func build(_ configs: [WidgetConfig], idPrefix: String = "") -> [Widget] {
        var seen = Set<String>()
        return configs.enumerated().compactMap { index, config in
            guard let factory = factories[config.type] else {
                Log.config.error("unknown widget type '\(config.type, privacy: .public)', skipping")
                return nil
            }
            let base = config.id ?? "\(config.type)-\(index)"
            var id = idPrefix.isEmpty ? base : "\(idPrefix).\(base)"
            while !seen.insert(id).inserted { id += "-\(index)" }
            return factory(id, Options(raw: config.options ?? [:]))
        }
    }
}
