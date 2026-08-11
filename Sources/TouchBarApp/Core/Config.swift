import Foundation

/// Minimal heterogeneous JSON value so widget `options` can hold anything
/// without every widget needing its own Codable type in the top-level model.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var doubleValue: Double? { if case .number(let v) = self { return v }; return nil }
    var intValue: Int? { doubleValue.map(Int.init) }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
}

/// Convenience accessors over a widget's `options` dictionary.
struct Options {
    let raw: [String: JSONValue]

    func string(_ key: String, _ fallback: String) -> String { raw[key]?.stringValue ?? fallback }
    func string(_ key: String) -> String? { raw[key]?.stringValue }
    func int(_ key: String, _ fallback: Int) -> Int { raw[key]?.intValue ?? fallback }
    func double(_ key: String, _ fallback: Double) -> Double { raw[key]?.doubleValue ?? fallback }
    func bool(_ key: String, _ fallback: Bool) -> Bool { raw[key]?.boolValue ?? fallback }
    func strings(_ key: String) -> [String]? { raw[key]?.arrayValue?.compactMap(\.stringValue) }
}

struct WidgetConfig: Codable {
    let type: String
    /// Optional explicit id. Falls back to `type-<index>` so duplicates of the
    /// same widget type still get unique NSTouchBarItem identifiers.
    let id: String?
    let options: [String: JSONValue]?
}

struct AppConfig: Codable {
    var presentOnLaunch: Bool?
    var refreshSeconds: Double?
    var controlStripTitle: String?
    var widgets: [WidgetConfig]
    /// Per-app layouts keyed by bundle identifier. The frontmost app's layout
    /// replaces `widgets`; anything not listed falls back to it.
    var apps: [String: [WidgetConfig]]?

    static let `default` = AppConfig(
        presentOnLaunch: true,
        refreshSeconds: 1.0,
        controlStripTitle: "▚",
        widgets: [
            WidgetConfig(type: "clock", id: nil, options: nil),
            WidgetConfig(type: "cpu", id: nil, options: nil),
            WidgetConfig(type: "memory", id: nil, options: nil),
            WidgetConfig(type: "battery", id: nil, options: nil)
        ],
        apps: nil
    )
}

enum ConfigStore {
    /// `~/.config/touchbar-app/config.json`
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/touchbar-app/config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url) else {
            Log.config.notice("no config at \(url.path, privacy: .public), using defaults")
            return .default
        }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            Log.config.error("config parse failed, using defaults: \(String(describing: error), privacy: .public)")
            return .default
        }
    }

    /// Writes the bundled example config if the user has none yet.
    @discardableResult
    static func seedIfMissing() -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return false }
        guard let example = Bundle.main.url(forResource: "config.example", withExtension: "json"),
              let data = try? Data(contentsOf: example) else { return false }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        Log.config.notice("seeded config at \(url.path, privacy: .public)")
        return true
    }
}

/// Watches the config file and its parent directory. Editors that write
/// atomically (rename over the file) invalidate the file descriptor, so the
/// directory watch is what actually catches most saves.
final class ConfigWatcher {
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        let url = ConfigStore.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        dirSource = makeSource(path: url.deletingLastPathComponent().path)
        fileSource = makeSource(path: url.path)
    }

    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        src.setEventHandler { [weak self] in self?.fire() }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }

    private func fire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Re-arm: an atomic save replaced the inode the file source held.
            self.fileSource?.cancel()
            self.fileSource = self.makeSource(path: ConfigStore.url.path)
            self.onChange()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop() {
        fileSource?.cancel(); fileSource = nil
        dirSource?.cancel(); dirSource = nil
    }
}
