#if DEBUG
import SwiftUI

/// Development aid: lets a script drive the running debug build, so the real
/// views can be exercised without Accessibility permission.
///
/// Post the distributed notification "com.monik.debug" with one
/// of these strings as its object. `<window>` is `menu` (the real dropdown),
/// `panel` (a copy of its content hosted off screen) or `settings`, and
/// coordinates are points from the top-left corner of that window's frame:
///
///     menu                          open (or close) the real dropdown under the menu bar icon
///     panel                         host the dropdown's content off screen
///     settings                      open Settings the way the panel's button does
///     tap <window> 120 300          click
///     drag <window> 120 300 200 300 press, move and release
///     snap <window> /tmp/out.png    render the window to a PNG
///     status                        log the current state to stderr
enum DebugRemote {
    private static var panel: NSWindow?

    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.monik.debug"), object: nil, queue: .main
        ) { notification in
            let words = (notification.object as? String ?? "").split(separator: " ").map(String.init)
            MainActor.assumeIsolated { run(words) }
        }
    }

    private static func run(_ words: [String]) {
        let numbers = words.dropFirst(2).compactMap(Double.init)
        switch words.first {
        case "menu":
            if MenuBarPanel.isOpen { MenuBarPanel.close() } else { MenuBarPanel.open() }
        case "panel":
            showPanel()
        case "settings":
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        case "tap" where numbers.count == 2:
            press(in: window(named: words[1]), from: NSPoint(x: numbers[0], y: numbers[1]), to: nil)
        case "drag" where numbers.count == 4:
            press(in: window(named: words[1]), from: NSPoint(x: numbers[0], y: numbers[1]),
                  to: NSPoint(x: numbers[2], y: numbers[3]))
        case "snap" where words.count == 3:
            snapshot(window(named: words[1]), to: URL(filePath: words[2]))
        default:
            let model = AppModel.shared
            let workspace = NSWorkspace.shared
            log("applied \(Int(model.appliedKelvin)) | enabled \(model.prefs.isEnabled) "
                + "| pause \(model.pause.map { "\($0)" } ?? "none") | \(model.statusLine) "
                + "| menu \(window(named: "menu").map { "\($0.className) \($0.frame)" } ?? "closed") open=\(MenuBarPanel.isOpen) "
                + "| settings \(window(named: "settings").map { "\($0.frame) key=\($0.isKeyWindow)" } ?? "closed") "
                + "| login \(LoginItem.isEnabled) | active \(NSApp.isActive) front \(workspace.frontmostApplication?.localizedName ?? "-") "
                + "menubar \(workspace.menuBarOwningApplication?.localizedName ?? "-")")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[debug] \(message)\n".utf8))
    }

    private static func window(named name: String) -> NSWindow? {
        if name == "panel" { return panel }
        if name == "menu" {
            return NSApp.windows.first {
                $0.isVisible && $0 !== panel && !$0.styleMask.contains(.titled) && !$0.className.contains("StatusBar")
            }
        }
        return NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && $0 !== panel }
    }

    private static func showPanel() {
        let host = NSHostingView(rootView: MenuPopover().environment(AppModel.shared))
        let window = panel ?? NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -3000, y: 200))
        window.orderFrontRegardless()
        panel = window
    }

    private static func snapshot(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        log("snap \(url.lastPathComponent) \(view.bounds.size)")
    }

    /// Queues synthetic mouse events for the window. They go through the
    /// normal event queue, so controls that run their own tracking loop
    /// (switches, sliders) see the release.
    private static func press(in window: NSWindow?, from start: NSPoint, to end: NSPoint?) {
        guard let window else { return }
        func local(_ point: NSPoint) -> NSPoint { NSPoint(x: point.x, y: window.frame.height - point.y) }

        var steps: [(NSEvent.EventType, NSPoint)] = [(.leftMouseDown, local(start))]
        if let end {
            for step in 1...8 {
                let t = CGFloat(step) / 8
                steps.append((.leftMouseDragged, local(NSPoint(x: start.x + (end.x - start.x) * t,
                                                               y: start.y + (end.y - start.y) * t))))
            }
        }
        steps.append((.leftMouseUp, local(end ?? start)))

        for (index, step) in steps.enumerated() {
            guard let event = NSEvent.mouseEvent(
                with: step.0,
                location: step.1,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(index) * 0.01,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: index,
                clickCount: 1,
                pressure: step.0 == .leftMouseUp ? 0 : 1
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }
}
#endif
