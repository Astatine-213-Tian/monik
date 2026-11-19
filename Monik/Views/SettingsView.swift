import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Schedule", systemImage: "sun.horizon") {
                ScheduleSettings()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Tab("Exceptions", systemImage: "pause.circle") {
                ExceptionsSettings()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 500)
    }
}

// MARK: - Schedule

struct ScheduleSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                ScheduleChart(plotHeight: 120)
                    .padding(.vertical, 6)
            }

            Section("Color Temperature") {
                ForEach(Phase.allCases) { phase in
                    LabeledContent(phase.title) {
                        HStack(spacing: 10) {
                            TemperatureSlider(phase: phase, height: 22)
                                .frame(width: 260)
                            Text(kelvinLabel(model.prefs[phase]))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }

            // The same two times as the knobs on the chart, for typing exactly.
            Section {
                timeField(.wake, \.wakeMinutes)
                timeField(.bedtime, \.bedtimeMinutes)
            }

            SunSettings()

            Section {
                Picker("Transitions", selection: $model.prefs.transition) {
                    ForEach(TransitionSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A plain time field: click a component, then type or use the arrow keys.
    private func timeField(_ kind: Timeline.Event.Kind, _ keyPath: WritableKeyPath<Preferences, Int>) -> some View {
        LabeledContent {
            TimeField(selection: time(keyPath))
                .fixedSize()
                .accessibilityLabel(kind.title)
        } label: {
            Label {
                Text(kind.title)
            } icon: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(Color.night)
                    .frame(width: 22)
            }
        }
    }

    private func date(for minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: model.now) ?? model.now
    }

    private func time(_ keyPath: WritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding {
            date(for: model.prefs[keyPath: keyPath])
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            model.prefs[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

// MARK: - Exceptions

struct ExceptionsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Disable for full-screen apps", isOn: $model.prefs.disableForFullScreen)
            } footer: {
                Text("Colors return to normal while the app in front is in full screen, and warm up again when you leave it.")
            }

            Section {
                ForEach(model.prefs.exceptionApps) { app in
                    HStack(spacing: 10) {
                        AppIconView(app: app, size: 24)
                        Text(app.name)
                        Spacer()
                        if model.pause == .app(app) {
                            Text("In front now")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button("Remove \(app.name)", systemImage: "minus.circle.fill") {
                            model.setException(app, enabled: false)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }

                if model.prefs.exceptionApps.isEmpty {
                    Text("No apps yet")
                        .foregroundStyle(.secondary)
                }

                AddAppMenu()
            } header: {
                Text("Disable for Specific Apps")
            } footer: {
                Text("The screen returns to its normal color while one of these apps is in front, and warms up again as soon as you switch to another app.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Offers the apps that are open right now, plus a file picker for the rest.
private struct AddAppMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(AppExceptions.runningApps(excluding: model.prefs.exceptionApps)) { app in
                Button {
                    model.setException(app, enabled: true)
                } label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: menuIcon(for: app))
                    }
                }
            }
            Divider()
            Button("Choose from Applications…", action: chooseApplication)
        } label: {
            Label("Add App", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func menuIcon(for app: AppIdentity) -> NSImage {
        let icon = app.icon.copy() as? NSImage ?? app.icon
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for app in panel.urls.compactMap(AppIdentity.init(applicationAt:)) {
            model.setException(app, enabled: true)
        }
    }
}

// MARK: - Sunrise and sunset

/// Where the sun's times on the chart come from.
private struct SunSettings: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        Section {
            LabeledContent("Location") {
                HStack(spacing: 8) {
                    if model.location.state == .working {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(summary)
                    Button("Use Current Location", systemImage: "location.fill") {
                        model.location.useCurrentLocation()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Use Current Location")
                }
            }

            HStack {
                TextField("Find a place", text: $query, prompt: Text("City, postcode or 43.3, 5.4"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if case .failed(let message) = model.location.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Sunrise and Sunset")
        } footer: {
            if model.prefs.coordinate == nil {
                Text("No location set, so the sun is assumed to rise at 7 AM and set at 7 PM.")
            }
        }
    }

    private var summary: String {
        guard let coordinate = model.prefs.coordinate else { return "Not set" }
        return model.prefs.locationName ?? coordinate.formatted
    }

    private func search() {
        let text = query
        Task { await model.location.search(text) }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        loginItemError = LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: $model.prefs.automaticallyCheckForUpdates)
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.updates.isChecking {
                        ProgressView().controlSize(.small)
                    }
                    Button("Check for Updates") {
                        Task { await model.updates.checkForUpdates() }
                    }
                    .disabled(model.updates.isChecking)
                }
                if let release = model.updates.availableRelease {
                    LabeledContent("Monik \(release.versionLabel) is available") {
                        Link("Download", destination: release.downloadURL)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                if model.updates.state == .failed {
                    Text("Couldn’t check for updates. Try again later.")
                } else if model.updates.state == .upToDate {
                    Text("You’re up to date.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
