import ServiceManagement

/// Registers the app itself to open when the user logs in.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns a message for the user if the change didn't take.
    static func setEnabled(_ enabled: Bool) -> String? {
        guard enabled != isEnabled else { return nil }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Couldn’t change the login item. Move the app to your Applications folder and try again."
        }
    }
}
