import AppKit

/// Bridge to the private DFRFoundation framework plus the unexported
/// NSTouchBar/NSTouchBarItem class methods that let a background app own
/// Control Strip real estate.
///
/// Everything here is best-effort: a missing symbol logs and returns false so
/// the app degrades to a plain focused-only Touch Bar instead of crashing on a
/// future macOS that drops these.
enum DFRBridge {
    private static let handle: UnsafeMutableRawPointer? = {
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let h = dlopen(path, RTLD_NOW) else {
            Log.dfr.error("dlopen DFRFoundation failed: \(String(cString: dlerror()), privacy: .public)")
            return nil
        }
        return h
    }()

    static var isAvailable: Bool { handle != nil && presenceFn != nil }

    private typealias SetPresenceFn = @convention(c) (NSString, ObjCBool) -> Void
    private typealias SetCloseBoxFn = @convention(c) (ObjCBool) -> Void

    private static let presenceFn: SetPresenceFn? = {
        guard let h = handle,
              let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else {
            Log.dfr.error("missing DFRElementSetControlStripPresenceForIdentifier")
            return nil
        }
        return unsafeBitCast(sym, to: SetPresenceFn.self)
    }()

    private static let setCloseBox: SetCloseBoxFn? = {
        guard let h = handle,
              let sym = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return nil }
        return unsafeBitCast(sym, to: SetCloseBoxFn.self)
    }()

    // MARK: - Control Strip presence

    @discardableResult
    static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, present: Bool) -> Bool {
        guard let fn = presenceFn else { return false }
        fn(identifier.rawValue as NSString, ObjCBool(present))
        return true
    }

    static func showsCloseBoxWhenFrontMost(_ shows: Bool) {
        setCloseBox?(ObjCBool(shows))
    }

    // MARK: - System tray items (NSTouchBarItem class methods)

    @discardableResult
    static func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        perform(on: NSTouchBarItem.self, selector: "addSystemTrayItem:", with: item)
    }

    @discardableResult
    static func removeSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        perform(on: NSTouchBarItem.self, selector: "removeSystemTrayItem:", with: item)
    }

    // MARK: - System modal bar (NSTouchBar class methods)

    /// Selector names have drifted across macOS releases ("FunctionBar" was the
    /// pre-10.14 spelling), so try each until one sticks.
    private static let presentSelectors = [
        "presentSystemModalTouchBar:systemTrayItemIdentifier:",
        "presentSystemModalFunctionBar:systemTrayItemIdentifier:"
    ]
    private static let dismissSelectors = [
        "dismissSystemModalTouchBar:",
        "dismissSystemModalFunctionBar:"
    ]

    @discardableResult
    static func presentSystemModal(_ touchBar: NSTouchBar,
                                   trayItemIdentifier: NSTouchBarItem.Identifier) -> Bool {
        let cls: AnyObject = NSTouchBar.self
        for name in presentSelectors {
            let sel = NSSelectorFromString(name)
            guard cls.responds(to: sel) else { continue }
            _ = cls.perform(sel, with: touchBar, with: trayItemIdentifier.rawValue as NSString)
            return true
        }
        Log.dfr.error("no usable presentSystemModalTouchBar selector")
        return false
    }

    @discardableResult
    static func dismissSystemModal(_ touchBar: NSTouchBar) -> Bool {
        let cls: AnyObject = NSTouchBar.self
        for name in dismissSelectors {
            let sel = NSSelectorFromString(name)
            guard cls.responds(to: sel) else { continue }
            _ = cls.perform(sel, with: touchBar)
            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func perform(on cls: AnyClass, selector name: String, with arg: Any?) -> Bool {
        let obj: AnyObject = cls
        let sel = NSSelectorFromString(name)
        guard obj.responds(to: sel) else {
            Log.dfr.error("class method \(name, privacy: .public) unavailable")
            return false
        }
        _ = obj.perform(sel, with: arg)
        return true
    }
}
