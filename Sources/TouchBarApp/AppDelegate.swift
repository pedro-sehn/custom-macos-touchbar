import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let barController = TouchBarController()
    private var stripController: ControlStripController!
    private var statusItem: NSStatusItem?
    private var watcher: ConfigWatcher?
    private var config = AppConfig.default

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("launched")

        ConfigStore.seedIfMissing()
        config = ConfigStore.load()

        stripController = ControlStripController(barController: barController)
        barController.rebuild(with: config)
        stripController.installControlStripItem(title: config.controlStripTitle ?? "▚")

        if config.presentOnLaunch ?? true {
            stripController.present()
        }

        watcher = ConfigWatcher { [weak self] in self?.reloadConfig() }
        installStatusItem()
        observeFrontmostApp()
    }

    /// Drives per-app layouts. Also fires once now, since the app that was
    /// already frontmost at launch never sends an activation notification.
    private func observeFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        barController.showLayout(
            forBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    @objc private func frontmostAppChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        barController.showLayout(forBundleIdentifier: app?.bundleIdentifier)
    }

    func applicationWillTerminate(_ notification: Notification) {
        barController.stop()
        stripController?.removeControlStripItem()
    }

    // MARK: - Config

    @objc func reloadConfig() {
        config = ConfigStore.load()
        barController.rebuild(with: config)
        barController.showLayout(
            forBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        // The presented bar still points at the old NSTouchBar instance.
        stripController.representIfNeeded()
        Log.config.notice("config reloaded")
    }

    @objc private func editConfig() {
        ConfigStore.seedIfMissing()
        NSWorkspace.shared.open(ConfigStore.url)
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "▚"
        item.button?.toolTip = "TouchBarApp"

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Touch Bar", action: #selector(toggleBar), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        menu.addItem(withTitle: "Edit Config…", action: #selector(editConfig), keyEquivalent: ",")
        let launchItem = NSMenuItem(title: "Launch at Login",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleBar() { stripController.toggle() }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            Log.app.error("launch-at-login toggle failed: \(String(describing: error), privacy: .public)")
        }
    }
}
