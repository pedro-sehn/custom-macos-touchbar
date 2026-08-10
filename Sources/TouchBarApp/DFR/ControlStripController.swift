import AppKit

/// Keeps one always-visible button in the Control Strip and, when toggled on,
/// presents the full-width system modal bar carrying every widget.
///
/// The Control Strip item is what makes this app useful at all: a plain
/// NSTouchBar only renders while the owning app is frontmost.
final class ControlStripController: NSObject {
    private let identifier = TouchBarController.controlStripIdentifier
    private var trayItem: NSCustomTouchBarItem?
    private weak var barController: TouchBarController?

    private(set) var isPresented = false
    private var repositionWork: DispatchWorkItem?

    init(barController: TouchBarController) {
        self.barController = barController
        super.init()
    }

    // MARK: - Control Strip

    func installControlStripItem(title: String) {
        guard DFRBridge.isAvailable else {
            Log.dfr.error("DFRFoundation unavailable — Control Strip presence disabled; widgets will only appear while this app is frontmost")
            return
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = BarStyle.button(title: title, target: self, action: #selector(toggle))
        button.bezelStyle = .rounded
        item.view = button
        trayItem = item

        DFRBridge.addSystemTrayItem(item)
        DFRBridge.setControlStripPresence(identifier, present: true)
        // No close box: the Control Strip button is the way back out.
        DFRBridge.showsCloseBoxWhenFrontMost(false)

        observeSystemEvents()
    }

    func removeControlStripItem() {
        dismiss()
        DFRBridge.setControlStripPresence(identifier, present: false)
        if let trayItem { DFRBridge.removeSystemTrayItem(trayItem) }
        trayItem = nil
    }

    // MARK: - Modal bar

    @objc func toggle() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard let bar = barController?.touchBar else { return }
        guard DFRBridge.presentSystemModal(bar, trayItemIdentifier: identifier) else { return }
        isPresented = true
    }

    func dismiss() {
        guard isPresented, let bar = barController?.touchBar else { return }
        DFRBridge.dismissSystemModal(bar)
        isPresented = false
    }

    /// Called after a hot reload swapped the NSTouchBar instance out from under
    /// a live presentation.
    func representIfNeeded() {
        guard isPresented else { return }
        isPresented = false
        present()
    }

    // MARK: - Recovery

    /// Wake from sleep and display reconfiguration both drop the presented bar
    /// without telling us. Re-assert presence and presentation after each.
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(reassert),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(reassert),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reassert),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    @objc private func reassert() {
        repositionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DFRBridge.setControlStripPresence(self.identifier, present: true)
            if self.isPresented {
                self.isPresented = false
                self.present()
            }
        }
        repositionWork = work
        // The Touch Bar daemon needs a beat after wake before it accepts these.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
