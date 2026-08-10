import AppKit
import ApplicationServices

/// One runnable action, parsed from a config object. Shared by every widget
/// type so a slider, a scrubber cell and a long-press all trigger work the
/// same way.
struct ActionSpec {
    enum Kind {
        case shell(String)
        case appleScript(String)
        case open(String)          // bundle id, app name, or URL
        case hotkey([String])
        case media(MediaKeys.Key)
        case none
    }

    let kind: Kind

    var isNone: Bool { if case .none = kind { return true }; return false }

    init(options: Options) {
        switch options.string("action", "none") {
        case "shell":       kind = .shell(options.string("command", ""))
        case "applescript": kind = .appleScript(options.string("script", ""))
        case "open":        kind = .open(options.string("target", ""))
        case "hotkey":      kind = .hotkey(options.strings("keys") ?? [])
        case "media":
            switch options.string("key", "playPause") {
            case "next":     kind = .media(.next)
            case "previous": kind = .media(.previous)
            default:         kind = .media(.playPause)
            }
        default: kind = .none
        }
    }

    /// Parses a nested action object, e.g. a `longPress` block.
    init?(nested: JSONValue?) {
        guard case .object(let dict)? = nested else { return nil }
        self.init(options: Options(raw: dict))
    }

    /// `value` is substituted into shell commands and AppleScript as `{value}`
    /// and exported as `$VALUE`, so sliders can drive scripts.
    func run(value: Double? = nil) {
        switch kind {
        case .shell(let command):
            Self.runShell(substitute(command, value), value: value)
        case .appleScript(let source):
            Self.runAppleScript(substitute(source, value))
        case .open(let target):
            Self.open(target)
        case .hotkey(let keys):
            Self.postHotkey(keys)
        case .media(let key):
            MediaKeys.post(key)
        case .none:
            break
        }
    }

    private func substitute(_ text: String, _ value: Double?) -> String {
        guard let value else { return text }
        let rendered = value == value.rounded()
            ? String(Int(value))
            : String(format: "%.3f", value)
        return text.replacingOccurrences(of: "{value}", with: rendered)
    }

    // MARK: - Implementations

    /// Runs off the main thread so a slow command never freezes the bar.
    /// `-lc` picks up the login PATH so brew-installed tools resolve.
    private static func runShell(_ command: String, value: Double?) {
        guard !command.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            if let value {
                var env = ProcessInfo.processInfo.environment
                env["VALUE"] = String(format: "%g", value)
                process.environment = env
            }
            do {
                try process.run()
            } catch {
                Log.widget.error("shell failed: \(String(describing: error), privacy: .public)")
                return
            }
            process.waitUntilExit()   // reap; already on a background queue
        }
    }

    private static func runAppleScript(_ source: String) {
        guard !source.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                Log.widget.error("applescript failed: \(error, privacy: .public)")
            }
        }
    }

    private static func open(_ target: String) {
        guard !target.isEmpty else { return }
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: target) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if target.hasPrefix("http://") || target.hasPrefix("https://"), let url = URL(string: target) {
            workspace.open(url)
            return
        }
        let path = target.hasSuffix(".app") ? target : "/Applications/\(target).app"
        workspace.openApplication(at: URL(fileURLWithPath: path),
                                  configuration: NSWorkspace.OpenConfiguration())
    }

    /// Requires Accessibility. Prompted lazily on first use rather than at
    /// launch, so the app stays silent until a hotkey is actually pressed.
    private static func postHotkey(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
            Log.widget.error("hotkey blocked: Accessibility not granted")
            return
        }

        var flags: CGEventFlags = []
        var keyCode: CGKeyCode?
        for key in keys {
            switch key.lowercased() {
            case "cmd", "command":  flags.insert(.maskCommand)
            case "shift":           flags.insert(.maskShift)
            case "alt", "option":   flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn":              flags.insert(.maskSecondaryFn)
            default:                keyCode = KeyCodes.code(for: key)
            }
        }
        guard let keyCode else {
            Log.widget.error("hotkey has no non-modifier key: \(keys, privacy: .public)")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
