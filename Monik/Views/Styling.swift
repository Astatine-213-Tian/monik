import SwiftUI

extension Color {
    /// The chart's color for a temperature: amber when warm, sky blue at
    /// daylight. More saturated than the real white point so the difference
    /// between 2700K and 3400K is visible on a thin line.
    static func temperature(_ kelvin: Double) -> Color {
        let stops: [(kelvin: Double, rgb: SIMD3<Double>)] = [
            (2700, SIMD3(1.00, 0.45, 0.17)),
            (3400, SIMD3(1.00, 0.60, 0.22)),
            (4300, SIMD3(1.00, 0.75, 0.36)),
            (5400, SIMD3(0.98, 0.86, 0.60)),
            (6500, SIMD3(0.40, 0.70, 1.00)),
        ]
        let kelvin = min(max(kelvin, stops[0].kelvin), stops[stops.count - 1].kelvin)
        let upper = stops.firstIndex { $0.kelvin >= kelvin } ?? stops.count - 1
        let lower = max(upper - 1, 0)
        let span = stops[upper].kelvin - stops[lower].kelvin
        let t = span > 0 ? (kelvin - stops[lower].kelvin) / span : 0
        let rgb = stops[lower].rgb + (stops[upper].rgb - stops[lower].rgb) * t
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}

extension Color {
    /// The night bar and its bedtime and wake knobs. A fixed color rather
    /// than the system indigo: inside the menu bar dropdown, system colors
    /// are blended for vibrancy and disappear on a white knob.
    static let night = Color(red: 0.38, green: 0.36, blue: 0.88)
}

// MARK: - Menu bar panel building blocks
//
// These follow the system's own menu bar panels (Wi-Fi, Sound, Battery):
// 13 pt text, 14 pt margins, and rows that highlight edge to edge like menu
// items.

enum Panel {
    static let width: CGFloat = 320
    static let margin: CGFloat = 14
    /// Rows highlight in a rounded rectangle inset this far from the edge.
    static let rowInset: CGFloat = 6
    static let iconWidth: CGFloat = 20
}

struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, Panel.margin)
    }
}

/// A full-width row that highlights on hover, like an item in a system menu.
struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Panel.margin - Panel.rowInset)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.09 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

/// A command row with its keyboard shortcut shown at the trailing edge.
struct PanelCommand: View {
    let title: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text("⌘\(String(shortcut.character).uppercased())")
                    .foregroundStyle(.tertiary)
            }
        }
        .keyboardShortcut(shortcut)
        .buttonStyle(PanelRowButtonStyle())
    }
}

/// An app icon at list size.
struct AppIconView: View {
    let app: AppIdentity
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: app.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

extension OpenSettingsAction {
    /// Opens Settings in front of whatever app is active and closes the
    /// dropdown. A menu bar app has no Dock icon to click, so a Settings
    /// window that opened behind another app would be hard to find.
    func bringToFront() {
        NSApp.activate()
        self()
        DispatchQueue.main.async {
            MenuBarPanel.close()
            focusSettings(checks: 3)
        }
    }

    /// While the dropdown is up this app has the keyboard; closing it can
    /// hand the keyboard back to the app the user came from, which would
    /// leave Settings on screen but greyed out. Look again for a moment and
    /// take the focus back if that happened.
    private func focusSettings(checks: Int) {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
           !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate()
            window.orderFrontRegardless()
            window.makeKey()
        }
        guard checks > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focusSettings(checks: checks - 1) }
    }
}

extension Notification.Name {
    /// Posted when something outside the views wants the Settings window.
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}
