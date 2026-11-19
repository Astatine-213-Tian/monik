import AppKit

/// An app the user picked, remembered by bundle identifier.
nonisolated struct AppIdentity: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

extension AppIdentity {
    init?(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }

    init?(applicationAt url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        self.init(bundleID: bundleID, name: name)
    }

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

enum AppExceptions {
    /// The listed app the user is working in right now, if any: the app whose
    /// menus are in the menu bar, as long as it has a window on this Space.
    /// An app that is merely open behind another one doesn't count, so the
    /// warmth comes back as soon as the user switches away, moves to a Space
    /// without the app, or closes its windows.
    ///
    /// Menu bar ownership is used instead of key focus because things that
    /// only borrow the keyboard for a moment (this app's own dropdown, a
    /// launcher, the screenshot tool) never take the menu bar, and so don't
    /// make the screen flash warm and back.
    static func appInFront(among apps: [AppIdentity]) -> AppIdentity? {
        guard !apps.isEmpty else { return nil }
        // Our own Settings window in front means the listed app is behind it.
        if NSApp.isActive, NSApp.keyWindow?.canBecomeMain == true { return nil }

        guard let front = NSWorkspace.shared.menuBarOwningApplication, !front.isHidden,
              let listed = apps.first(where: { $0.bundleID == front.bundleIdentifier }) else { return nil }
        let hasWindow = WindowList.onScreen().contains { window in
            window.owner == front.processIdentifier && window.layer >= 0 && window.alpha > 0.01
                && window.bounds.width >= 64 && window.bounds.height >= 64
        }
        return hasWindow ? listed : nil
    }

    /// Regular apps that are open right now, for the "add" menu.
    static func runningApps(excluding listed: [AppIdentity]) -> [AppIdentity] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != own }
            .compactMap(AppIdentity.init)
            .filter { !listed.contains($0) }
        return Array(Set(apps)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
