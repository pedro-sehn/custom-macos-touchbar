# TouchBarApp

Personal, config-driven Touch Bar for a 13" MacBook Pro (M1, `MacBookPro17,1`).
Runs as a menu-bar agent, keeps a button in the Control Strip at all times, and
presents a full-width bar of widgets on top of the system one.

Design rationale lives in the source comments — each non-obvious choice is
explained where it's made (private-API guards in `DFR/`, the popover-vs-
navigation call in `GroupWidget.swift`, the anchor-point workaround in
`Appearance.swift`).

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

### Language

```json
{ "language": "auto" }
```

`"auto"` (the default) follows the system. Otherwise a code: `"en"`, `"pt"`,
`"pt-BR"`, `"es"`. Region variants share a table, so `pt-BR` and `pt-PT` both
use `pt` for text while still formatting dates their own way.

This covers **app chrome only** — the menu bar, the `‹ Back` button, and
pomodoro notifications. Widget `title`, `prefix`, and `caption` are your
strings; translate them by editing your own config. The setting also sets the
locale used by `clock`, so `"format": "EEE"` yields `Mon` under `en` and `seg`
under `pt`.

Adding a language is one entry in `tables` in `Core/Localization.swift`.
Missing keys fall back to English per-key rather than rendering blank, and a
partial table is logged at startup with exactly which keys it lacks.

Not `.lproj` bundles and `NSLocalizedString`: the app is assembled by a shell
script with no Xcode build phase to compile `.strings` files.

### Widget types

**Readouts**

| type | options |
|---|---|
| `clock` | `format` (DateFormatter pattern), `timeZone` |
| `cpu` | `prefix` |
| `memory` | `prefix`, `showBytes` |
| `battery` | `showTime` |
| `network` | — |
| `crypto` | `symbol` (e.g. `BTC`), `currency` (`usd`/`brl`/`eur`), `decimals`, `width`, `staleAfter` — live market price |
| `graph` | `source` (`cpu`/`memory`/`network`), `caption`, `width`, `color`, `reactive` — live sparkline |
| `spacer` | `width` |

**Interactive**

| type | options |
|---|---|
| `shortcut` | `title`, `color`, `action` + args, plus gesture bindings (below) |
| `media` | `showTitle`, `titleWidth` — transport + now playing |
| `slider` | `label`, `min`, `max`, `target: "volume"` **or** an `action` fed the value |
| `scrubber` | `cellWidth`, `items: [{title, action, …}]` — swipe to scroll, tap to fire |
| `segmented` | `selected`, `segments: [{title, action, …}]` — sticky choice |
| `toggle` | stateful on/off — see below |
| `pomodoro` | `minutes`, `breakMinutes`, `notify` |
| `clipboard` | `capacity`, `cellWidth`, `paste` — swipeable clipboard history |
| `group` | `label`, `widgets: [...]` — collapses to one button, expands to a nested bar |

`group` is the fix for a crowded bar: `NSTouchBar` silently drops items that
don't fit the ~1085pt width, so park extras one tap deep instead. Groups nest.

#### Crypto prices

Each `crypto` widget follows one market symbol. `BTC` and `ETH` are supported;
other symbols work when the selected exchange lists that market. Defaults to
`BTC`/`usd`; choose quote currency per widget. `decimals` defaults to 2 (0–8),
`width` to 180pt, and `staleAfter` to 30 seconds (minimum 5):

```json
{ "type": "crypto", "options": { "symbol": "BTC", "currency": "usd" } },
{ "type": "crypto", "options": { "symbol": "ETH", "currency": "eur", "decimals": 2 } },
{ "type": "crypto", "options": { "symbol": "BTC", "currency": "brl", "staleAfter": 30 } }
```

Uses public, keyless Coinbase WebSocket markets for USD/EUR and Binance public
market-data WebSocket for BRL. No paid API, API key, or USDT-as-USD conversion.
Connections are shared across widgets and reconnect automatically. Prices are
exchange-specific; `~` marks a stale last price, `—` means no usable quote.
Use a `group` to keep several price readouts from crowding the main bar.

Tapping a group swaps the bar's item list and pushes onto a navigation stack
(with a `‹ Back` button) rather than using `NSPopoverTouchBarItem` — popover
items expect a Touch Bar supplied through the responder chain, and ours is
presented directly through the private system-modal API, where they never open.

### Appearance and animation

There is no API to change the Touch Bar's own background — the strip belongs to
the system, and even the private DFR surface only positions items. All colour
comes from widgets painting their own views, which is why wide widgets (graph,
pomodoro) carry most of the look.

What's animated, and where it lives:

| effect | widget | notes |
|---|---|---|
| press ripple | every button | expanding ring from the touch point, clipped to the pill |
| gradient bezel | every button | subtle top-down shading instead of a flat fill |
| squeeze | `toggle` | scales to 0.88 on state change — *down*, never up (see below) |
| smooth fill | `pomodoro` | animated across the full tick interval, not stepped |
| completion flash | `pomodoro` | pulse at each work/break transition |
| heat colour | `graph` | green → amber → red, eased 35% per sample |

Two constraints worth knowing before adding more:

- **Never scale a button up.** Growing it shoves its neighbours and can push the
  last item past the end of the bar, where `NSTouchBar` silently drops it.
- **Scale transforms need a manual centre offset.** AppKit gives layer-backed
  `NSView`s an `anchorPoint` of `(0, 0)`, so a plain `transform.scale` pivots on
  the bottom-left corner. `Appearance.scaleAboutCenter` bakes the offset into
  the transform; moving the anchor point instead loses to AppKit, which
  rewrites `position` on every layout pass.

Colours are `#RRGGBB` throughout: `color` on `shortcut`, `group`, and `graph`;
`onColor`/`offColor` on `toggle`.

#### Reactive graphs

By default a `graph` colours itself by load — green when idle, red when pegged.
Setting an explicit `color` turns that off and pins the colour:

```json
{ "type": "graph", "options": { "source": "cpu", "caption": "CPU" } },
{ "type": "graph", "options": { "source": "cpu", "color": "#4ADE80" } },
{ "type": "graph", "options": { "source": "cpu", "color": "#4ADE80", "reactive": true } }
```

The third form keeps your colour on file while running reactive, so flipping
`reactive` to `false` restores it. The colour eases toward its target rather
than snapping, so one spiky sample doesn't strobe the widget.

### Stateful toggles

Unlike `shortcut`, a `toggle` polls real state and renders it — title and tint
both change. Built-in targets:

```json
{ "type": "toggle", "options": { "target": "caffeinate", "onTitle": "☕️", "offTitle": "💤" } },
{ "type": "toggle", "options": { "target": "darkmode",   "onTitle": "🌙", "offTitle": "☀️" } }
```

`caffeinate` runs as a child process owned by the app, so it dies with the app
instead of leaking a sleep blocker. `darkmode` goes through System Events and
needs Automation consent.

Anything else supplies its own state probe — stdout of `on`/`1`/`true`/`yes`
means on:

```json
{
  "type": "toggle",
  "options": {
    "onTitle": "🔊", "offTitle": "🔇",
    "stateCommand": "[ $(osascript -e 'output muted of (get volume settings)') = false ] && echo on || echo off",
    "on":  { "action": "applescript", "script": "set volume without output muted" },
    "off": { "action": "applescript", "script": "set volume with output muted" }
  }
}
```

Optional `onColor` / `offColor` as `#RRGGBB`.

### Pomodoro

```json
{ "type": "pomodoro", "options": { "minutes": 25, "breakMinutes": 5, "notify": true } }
```

Tap starts and pauses, long-press resets. Progress fills the pill; each
transition fires a haptic and a notification. Runs on the shared ticker, so it
adds no timer of its own.

### Clipboard history

```json
{ "type": "clipboard", "options": { "capacity": 12, "cellWidth": 110, "paste": true } }
```

macOS has no pasteboard-change notification, so this polls `changeCount` once
per tick — an integer compare. Tapping an entry re-copies it and, with
`"paste": true`, synthesizes cmd+V into the frontmost app (needs Accessibility).
Wide: put it in a `group`.

### Per-app layouts

A top-level `apps` map, sibling of `widgets`, keyed by bundle identifier. The
frontmost app's layout replaces the bar; anything unlisted falls back to
`widgets`.

```json
{
  "widgets": [ { "type": "clock" } ],
  "apps": {
    "com.googlecode.iterm2": [
      { "type": "graph", "options": { "source": "cpu", "caption": "CPU" } },
      { "type": "clipboard", "options": { "capacity": 8 } }
    ],
    "company.thebrowser.Browser": [
      { "type": "shortcut", "options": { "title": "↩︎ Tab", "action": "hotkey", "keys": ["cmd", "shift", "t"] } }
    ]
  }
}
```

Find a bundle id with:

```bash
mdls -name kMDItemCFBundleIdentifier /Applications/Whatever.app
```

Every layout is built once at config load, not on each switch — building
widgets mid-activation would stutter, and the delegate must already be able to
resolve every identifier the moment the list changes. Switching apps also
unwinds group navigation, so a bar change can't strand you inside a group.

### Gestures

Any `shortcut` accepts extra action blocks. Buttons are drawn by a custom view
rather than `NSButton` — `NSButton`'s own mouse tracking swallows the touches
gesture recognizers need, and it can't render the press ripple either.

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

- **Accessibility** — needed for `hotkey` shortcuts, media buttons, and
  clipboard paste. Prompted the first time you use one.
- **Automation** — needed for now-playing titles from Music/Spotify, and for
  the `darkmode` toggle (System Events). Prompted on first use.

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
