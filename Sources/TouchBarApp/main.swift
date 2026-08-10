import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory: menu-bar agent, no Dock icon, no menu bar of its own.
app.setActivationPolicy(.accessory)
app.run()
