# TouchBarApp

Personal, config-driven Touch Bar for a 13" MacBook Pro (M1, `MacBookPro17,1`).
Runs as a menu-bar agent, keeps a button in the Control Strip at all times, and
presents a full-width bar of widgets on top of the system one.

See [PLAN.md](PLAN.md) for the design rationale and roadmap.

## Build & run

```bash
./Scripts/bundle.sh
open ./build/TouchBarApp.app
```

No Xcode needed — SwiftPM plus a shell script that assembles the `.app`.

Logs:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.pedro.touchbarapp"' --level debug
```

## Configuration

`~/.config/touchbar-app/config.json`, seeded from `Resources/config.example.json`
on first launch. Edits are picked up within ~1s — no restart.

```json
{
  "presentOnLaunch": true,
  "refreshSeconds": 1.0,
  "controlStripTitle": "▚",
  "widgets": [ { "type": "cpu" } ]
}
```

### Widget types

**Readouts**

| type | options |
|---|---|
| `clock` | `format` (DateFormatter pattern), `timeZone` |
| `cpu` | `prefix` |
| `memory` | `prefix`, `showBytes` |
| `battery` | `showTime` |
| `network` | — |
| `graph` | `source` (`cpu`/`memory`/`network`), `caption`, `width`, `color` — live sparkline |
| `spacer` | `width` |

**Interactive**

| type | options |
|---|---|
| `shortcut` | `title`, `color`, `action` + args, plus gesture bindings (below) |
| `media` | `showTitle`, `titleWidth` — transport + now playing |
| `slider` | `label`, `min`, `max`, `target: "volume"` **or** an `action` fed the value |
| `scrubber` | `cellWidth`, `items: [{title, action, …}]` — swipe to scroll, tap to fire |
| `segmented` | `selected`, `segments: [{title, action, …}]` — sticky choice |
| `group` | `label`, `widgets: [...]` — collapses to one button, expands to a nested bar |

`group` is the fix for a crowded bar: `NSTouchBar` silently drops items that
don't fit the ~1085pt width, so park extras one tap deep instead. Groups nest.

### Gestures

Any `shortcut` accepts extra action blocks. Adding one switches it from
`NSButton` to a custom view, since `NSButton`'s own tracking eats the touches
gesture recognizers need.

```json
{
  "type": "shortcut",
  "options": {
    "title": "📸", "action": "shell", "command": "screencapture -i ~/Desktop/s.png",
    "longPress":  { "action": "shell", "command": "screencapture -W ~/Desktop/w.png" },
    "swipeLeft":  { "action": "hotkey", "keys": ["cmd", "shift", "3"] },
    "swipeRight": { "action": "open", "target": "com.apple.Preview" },
    "pan":        { "action": "shell", "command": "echo {value}" }
  }
}
```

- `longPress` — 0.45s hold, with haptic feedback
- `swipeLeft` / `swipeRight` — 24pt threshold so sloppy taps don't misfire
- `pan` — continuous, receives `0.0…1.0` across the view's width

Sliders and `pan` substitute the value into `{value}` in a command or script,
and export it as `$VALUE`.

`shortcut` actions:

- `"action": "shell"` → `"command": "screencapture -i ~/Desktop/s.png"` (runs under `zsh -lc`)
- `"action": "applescript"` → `"script": "display notification \"hi\""`
- `"action": "open"` → `"target": "com.apple.Terminal"` (bundle id, app name, or URL)
- `"action": "hotkey"` → `"keys": ["cmd", "shift", "4"]`
- `"action": "media"` → `"key": "playPause" | "next" | "previous"`

Every widget also accepts `"id"` to give it a stable identifier.

## Permissions

- **Accessibility** — only needed for `hotkey` shortcuts and media buttons.
  Prompted the first time you press one.
- **Automation** — only needed for now-playing titles from Music/Spotify.
  Prompted the first time a player is running.

Both are tied to the app's code signature. `Scripts/bundle.sh` falls back to
ad-hoc signing, which **changes identity on every rebuild and resets those
grants**. To keep them, make a self-signed Code Signing certificate in Keychain
Access named `TouchBarApp Dev` (or set `SIGN_IDENTITY=...` when running the
script).

## Notes

- Control Strip persistence uses the private `DFRFoundation` framework. Every
  private symbol is looked up at runtime and guarded; if a future macOS drops
  them, the app degrades to a focused-only Touch Bar instead of crashing.
- Now-playing is **not** built on MediaRemote — that API has been
  entitlement-gated since macOS 15.4 and returns nothing to third-party apps.
- App Sandbox is off (private frameworks + system statistics). Not
  App Store distributable, by design.
