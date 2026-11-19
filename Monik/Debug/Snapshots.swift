#if DEBUG
import SwiftUI

/// Development aid: `Monik --snapshot <folder>` renders the
/// main views to PNG files and quits, without touching the displays.
enum Snapshots {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 else { return false }
        let folder = URL(filePath: arguments[flag + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let views: [(String, AnyView)] = [
            ("popover", AnyView(MenuPopover())),
            ("settings-schedule", AnyView(ScheduleSettings().frame(width: 500))),
            ("settings-exceptions", AnyView(ExceptionsSettings().frame(width: 500))),
            ("settings-general", AnyView(GeneralSettings().frame(width: 500))),
        ]

        var windows: [(String, NSWindow)] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view) in views {
                let host = NSHostingView(rootView: view.environment(AppModel.shared))
                let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.setContentSize(host.fittingSize)
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderFrontRegardless()
                windows.append(("\(name)-\(appearance == .aqua ? "light" : "dark")", window))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, window) in windows {
                guard let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?
                    .write(to: folder.appending(path: "\(name).png"))
            }
            exit(0)
        }
        return true
    }
}
#endif
