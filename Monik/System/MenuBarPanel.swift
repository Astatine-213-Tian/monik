import AppKit

/// Reaches the dropdown that SwiftUI's `MenuBarExtra` shows, which SwiftUI
/// itself offers no way to open or close from code.
///
/// From macOS 27 the system menu bar starts an "expanded interface session"
/// on the status item when its icon is clicked, and the dropdown is up for as
/// long as that session lasts. Before that, the icon was an ordinary button
/// that toggled the dropdown. Neither is public API, so every step checks
/// that the system still answers to it and otherwise does nothing.
enum MenuBarPanel {
    private static let session = NSSelectorFromString("expandedInterfaceSession")
    private static let cancel = NSSelectorFromString("cancel")

    /// Dismisses the dropdown the way clicking away from it does.
    static func close() {
        guard let item = statusItem else { return }
        if item.responds(to: session) {
            if let active = activeSession(of: item), active.responds(to: cancel) { active.perform(cancel) }
        } else if item.button?.state == .on {
            item.button?.performClick(nil)
        }
    }

    #if DEBUG
    static var isOpen: Bool {
        guard let item = statusItem else { return false }
        if item.responds(to: session) { return activeSession(of: item) != nil }
        return item.button?.state == .on
    }

    /// Shows the dropdown as a click on the icon would, so that tests can
    /// look at the real thing.
    static func open() {
        guard let item = statusItem, !isOpen else { return }
        if item.responds(to: beginSession), let implementation = item.method(for: beginSession) {
            // The argument is the time of the click that asked for it; a time
            // earlier than the last dismissal is ignored, so ask as "latest".
            typealias Begin = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
            unsafeBitCast(implementation, to: Begin.self)(item, beginSession, .greatestFiniteMagnitude)
        } else {
            item.button?.performClick(nil)
        }
    }

    private static let beginSession = NSSelectorFromString("_beginExpandedInterfaceSession:")
    #endif

    private static func activeSession(of item: NSStatusItem) -> NSObject? {
        item.perform(session)?.takeUnretainedValue() as? NSObject
    }

    /// The app has exactly one status item; AppKit keeps it on the small
    /// window that hosts the icon.
    private static var statusItem: NSStatusItem? {
        let key = NSSelectorFromString("statusItem")
        for window in NSApp.windows where window.className.contains("StatusBarWindow") && window.responds(to: key) {
            if let item = window.perform(key)?.takeUnretainedValue() as? NSStatusItem { return item }
        }
        return nil
    }
}
