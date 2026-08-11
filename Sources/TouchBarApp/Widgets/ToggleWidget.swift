import AppKit

/// A button that reflects real system state instead of just firing and
/// forgetting. Polls its state, then renders on/off with distinct titles and
/// tints.
///
/// Built-in targets handle their own state; anything else can supply a
/// `stateCommand` whose stdout starting with "on"/"1"/"true" means on.
final class ToggleWidget: NSObject, Widget {
    private enum Target {
        case caffeinate
        case darkMode
        case custom(state: String, on: ActionSpec, off: ActionSpec)
    }

    let identifier: NSTouchBarItem.Identifier
    private let target: Target
    private let onTitle: String
    private let offTitle: String
    private let onColor: NSColor
    private let offColor: NSColor

    private var isOn = false
    private var button: NSButton?
    /// Owned child process for `caffeinate` — cleaner than shelling out to
    /// pgrep, and it dies with the app instead of leaking a sleep blocker.
    private var caffeinateProcess: Process?

    var tickDivisor: Int { 5 }

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        onTitle = options.string("onTitle", "●")
        offTitle = options.string("offTitle", options.string("onTitle", "○"))
        onColor = options.string("onColor").flatMap(NSColor.fromHex) ?? .systemGreen
        offColor = options.string("offColor").flatMap(NSColor.fromHex) ?? NSColor(white: 0.22, alpha: 1)

        switch options.string("target", "custom") {
        case "caffeinate": target = .caffeinate
        case "darkmode", "darkMode": target = .darkMode
        default:
            target = .custom(state: options.string("stateCommand", ""),
                             on: ActionSpec(nested: options.raw["on"]) ?? ActionSpec(options: Options(raw: [:])),
                             off: ActionSpec(nested: options.raw["off"]) ?? ActionSpec(options: Options(raw: [:])))
        }
        super.init()
    }

    deinit {
        caffeinateProcess?.terminate()
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = BarStyle.button(title: offTitle, target: self, action: #selector(toggle))
        self.button = button
        item.view = button
        refreshState()
        return item
    }

    func tick() { refreshState() }

    @objc private func toggle() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        let next = !isOn
        switch target {
        case .caffeinate:
            next ? startCaffeinate() : stopCaffeinate()
        case .darkMode:
            setDarkMode(next)
        case .custom(_, let on, let off):
            (next ? on : off).run()
        }
        // Optimistic: the next poll corrects us if the action didn't take.
        apply(next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshState() }
    }

    // MARK: - State

    private func refreshState() {
        switch target {
        case .caffeinate:
            apply(caffeinateProcess?.isRunning == true)
        case .darkMode:
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let on = Self.darkModeEnabled()
                DispatchQueue.main.async { self?.apply(on) }
            }
        case .custom(let command, _, _):
            guard !command.isEmpty else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let on = Self.shellSaysOn(command)
                DispatchQueue.main.async { self?.apply(on) }
            }
        }
    }

    private func apply(_ on: Bool) {
        guard let button else { isOn = on; return }
        guard on != isOn || button.title.isEmpty else { return }
        let changed = on != isOn
        isOn = on
        let title = on ? onTitle : offTitle
        if title.hasEmoji {
            button.image = BarStyle.emojiImage(title)
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.title = title
        }
        button.bezelColor = on ? onColor : offColor

        // Bounce only on a real transition, not on the first render or on a
        // poll that confirms what we already showed.
        guard changed else { return }
        button.wantsLayer = true
        if let layer = button.layer { Appearance.bump(layer) }
    }

    private static func shellSaysOn(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["on", "1", "true", "yes"].contains(output)
    }

    // MARK: - Built-ins

    private func startCaffeinate() {
        stopCaffeinate()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]
        do {
            try process.run()
            caffeinateProcess = process
        } catch {
            Log.widget.error("caffeinate failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    private static func darkModeEnabled() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private func setDarkMode(_ on: Bool) {
        // System Events is the only supported way to flip appearance; this is
        // what triggers the Automation prompt the first time.
        let source = """
        tell application "System Events" to tell appearance preferences \
        to set dark mode to \(on ? "true" : "false")
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                Log.widget.error("dark mode toggle failed: \(error, privacy: .public)")
            }
        }
    }
}
