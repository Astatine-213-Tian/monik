import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Panel.margin)
                .padding(.top, 12)

            // Switched off, the schedule is still there to read but steps back.
            Group {
                ScheduleChart()
                    .padding(.horizontal, Panel.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                PanelDivider()
                adjuster
                    .padding(.horizontal, Panel.margin)
                    .padding(.vertical, 10)
            }
            .opacity(model.prefs.isEnabled ? 1 : 0.4)
            .disabled(!model.prefs.isEnabled)
            .animation(.easeOut(duration: 0.2), value: model.prefs.isEnabled)

            if let conflict = model.conflictingApp {
                PanelDivider()
                conflictNotice(conflict)
                    .padding(.horizontal, Panel.margin)
                    .padding(.vertical, 9)
            }

            PanelDivider()
            VStack(spacing: 0) {
                PanelCommand(title: "Settings…", shortcut: ",") {
                    openSettings.bringToFront()
                }
                PanelCommand(title: "Quit Monik", shortcut: "q") {
                    NSApp.terminate(nil)
                }
            }
            .padding(Panel.rowInset)
        }
        .font(.system(size: 13))
        .frame(width: Panel.width)
    }

    /// Title with the main switch beside it, as in the Wi-Fi and Bluetooth
    /// panels, and one line underneath saying what the screen is doing.
    private var header: some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: $model.prefs.isEnabled) {
                Text("Monik")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(alignment: .firstTextBaseline) {
                Text(model.statusLine)
                    .lineLimit(1)
                Spacer()
                if model.prefs.isEnabled {
                    Text(kelvinLabel(model.appliedKelvin))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    /// One warm-to-cool bar per part of the day, named at the front and
    /// with its knob wearing the same icon as its stretch of the curve above.
    private var adjuster: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(Phase.allCases) { phase in
                GridRow {
                    Text(phase.title)
                    TemperatureSlider(phase: phase)
                    Text(kelvinLabel(model.prefs[phase]))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }

    private func conflictNotice(_ app: NSRunningApplication) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .frame(width: Panel.iconWidth)
            Text("\(app.localizedName ?? "Another app") is also changing your screen color.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Quit") { app.terminate() }
                .controlSize(.small)
        }
    }
}
