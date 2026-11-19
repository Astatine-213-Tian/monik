import SwiftUI

@main
struct MonikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPopover()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // One glyph at all times; it only fades when the main switch is off.
        Image(model.prefs.isEnabled ? "MenuBarIcon" : "MenuBarIconOff")
            .accessibilityLabel("Monik")
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                openSettings.bringToFront()
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshots.runIfRequested() { return }
        DebugRemote.install()
        #endif
        AppModel.shared.start()
    }

    /// Opening the app again while it is running (from Finder, Spotlight or
    /// Launchpad) shows Settings, so the app stays reachable even when the
    /// menu bar is too crowded to show its icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}
