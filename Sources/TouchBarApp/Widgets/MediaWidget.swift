import AppKit

/// Transport buttons plus a now-playing label.
///
/// Deliberately NOT built on MediaRemote: `MRMediaRemoteGetNowPlayingInfo` has
/// been entitlement-gated since macOS 15.4 and silently returns nothing for
/// third-party apps. Music/Spotify are queried over AppleScript instead, and
/// everything else (browser tabs, etc.) is driven with synthesized media keys,
/// which work regardless of which app owns playback.
final class MediaWidget: NSObject, Widget {
    let identifier: NSTouchBarItem.Identifier
    private let showTitle: Bool
    private let titleWidth: CGFloat

    private var titleLabel: NSTextField?
    private var playButton: NSButton?
    private var lastTitle: String = ""
    private var lastPlaying: Bool?

    /// AppleScript round-trips are expensive; once every few seconds is plenty
    /// for a track title.
    var tickDivisor: Int { 5 }

    init(id: String, options: Options) {
        identifier = NSTouchBarItem.Identifier("com.pedro.touchbarapp.\(id)")
        showTitle = options.bool("showTitle", true)
        titleWidth = CGFloat(options.double("titleWidth", 160))
        super.init()
    }

    func makeItem() -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)

        let prev = BarStyle.button(title: "⏮", target: self, action: #selector(previous))
        let play = BarStyle.button(title: "⏯", target: self, action: #selector(playPause))
        let next = BarStyle.button(title: "⏭", target: self, action: #selector(nextTrack))
        playButton = play

        var views: [NSView] = [prev, play, next]
        if showTitle {
            let label = BarStyle.label("")
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true
            titleLabel = label
            views.append(label)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        item.view = stack
        return item
    }

    func tick() {
        guard showTitle else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let title = Self.nowPlayingTitle() ?? ""
            DispatchQueue.main.async {
                guard let self, title != self.lastTitle else { return }
                self.lastTitle = title
                self.titleLabel?.stringValue = title
            }
        }
    }

    // MARK: - Transport

    @objc private func playPause() { MediaKeys.post(.playPause) }
    @objc private func nextTrack() { MediaKeys.post(.next) }
    @objc private func previous() { MediaKeys.post(.previous) }

    // MARK: - Now playing

    private static let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify")
    ]

    /// Only talks to a player that is already running — this keeps the app from
    /// launching Music just to ask what's playing, and avoids an Automation
    /// permission prompt until it's genuinely needed.
    private static func nowPlayingTitle() -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for player in players where running.contains(player.bundleID) {
            let source = """
            tell application "\(player.appName)"
                if player state is playing then
                    return (name of current track) & " — " & (artist of current track)
                end if
            end tell
            return ""
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                Log.widget.error("now-playing script failed: \(error, privacy: .public)")
                continue
            }
            if let text = result?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }
}

/// System-defined media key events. These reach whatever app currently owns
/// media playback, including browsers, which AppleScript cannot do.
enum MediaKeys {
    enum Key: Int32 {
        case playPause = 16   // NX_KEYTYPE_PLAY
        case next = 17        // NX_KEYTYPE_NEXT
        case previous = 18    // NX_KEYTYPE_PREVIOUS
    }

    static func post(_ key: Key) {
        send(key, down: true)
        send(key, down: false)
    }

    private static func send(_ key: Key, down: Bool) {
        let data1 = Int((key.rawValue << 16) | (down ? 0x0A << 8 : 0x0B << 8))
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: [],
                                             timestamp: 0,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                                             data1: data1,
                                             data2: -1) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
