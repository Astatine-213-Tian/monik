import AppKit

/// Answers one question: is the Space in front right now a full-screen one?
enum SpaceInspector {
    /// macOS has no public API for the kind of the current Space, so this
    /// reads it from the window server (SkyLight), the same source Mission
    /// Control uses. The symbols are looked up at run time; if a future macOS
    /// drops them, the window-geometry check below still works.
    private struct WindowServer {
        typealias Connection = @convention(c) () -> Int32
        typealias ManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        typealias ActiveDisplay = @convention(c) (Int32) -> Unmanaged<CFString>?

        let connection: Connection
        let managedSpaces: ManagedSpaces
        let activeDisplay: ActiveDisplay?

        init?() {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
                  let connection = dlsym(handle, "CGSMainConnectionID"),
                  let spaces = dlsym(handle, "CGSCopyManagedDisplaySpaces") else { return nil }
            self.connection = unsafeBitCast(connection, to: Connection.self)
            self.managedSpaces = unsafeBitCast(spaces, to: ManagedSpaces.self)
            self.activeDisplay = dlsym(handle, "CGSCopyActiveMenuBarDisplayIdentifier")
                .map { unsafeBitCast($0, to: ActiveDisplay.self) }
        }
    }

    private static let windowServer = WindowServer()
    private static let fullScreenSpaceType = 4

    static func isFullScreenActive() -> Bool {
        currentSpaceIsFullScreen() ?? false || frontmostAppCoversDisplay()
    }

    /// Looks at the Space showing on the display that owns the menu bar,
    /// i.e. the one the user is working on.
    private static func currentSpaceIsFullScreen() -> Bool? {
        guard let server = windowServer else { return nil }
        let connection = server.connection()
        guard let displays = server.managedSpaces(connection)?.takeRetainedValue() as? [[String: Any]],
              !displays.isEmpty else { return nil }

        let active = server.activeDisplay?(connection)?.takeRetainedValue() as String?
        let display = displays.first { $0["Display Identifier"] as? String == active } ?? displays[0]
        guard let space = display["Current Space"] as? [String: Any],
              let type = space["type"] as? Int else { return nil }
        return type == fullScreenSpaceType
    }

    /// Catches games and players that cover a whole display, menu bar
    /// included, without moving to a full-screen Space. They do it with a
    /// window above the normal level; an ordinary window that merely fills
    /// the screen (possible when the menu bar auto-hides) doesn't count.
    private static func frontmostAppCoversDisplay() -> Bool {
        // The app that owns the menu bar, so that opening our own dropdown
        // over a game doesn't count as leaving it.
        guard let app = NSWorkspace.shared.menuBarOwningApplication else { return false }
        let displays = NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                .map(CGDisplayBounds)
        }
        return WindowList.onScreen().contains { window in
            window.owner == app.processIdentifier && window.layer > 0 && window.alpha > 0.9
                && displays.contains(window.bounds)
        }
    }
}

/// Windows currently visible on any display, front to back. Only geometry and
/// ownership are read, which needs no Screen Recording permission.
enum WindowList {
    struct Window {
        var owner: pid_t
        var layer: Int
        var alpha: Double
        var bounds: CGRect
    }

    static func onScreen() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            return Window(owner: owner, layer: layer, alpha: alpha, bounds: bounds)
        }
    }
}
