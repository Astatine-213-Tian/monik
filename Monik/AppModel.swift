import AppKit
import Observation
import QuartzCore

/// Why the screen is left at its normal color although the app is on.
enum PauseReason: Equatable {
    case app(AppIdentity)
    case fullScreen(appName: String?)
}

/// The single source of truth: owns the settings, decides what color the
/// displays should be right now and keeps them there.
@Observable
final class AppModel {
    static let shared = AppModel()

    var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            refresh()
        }
    }

    private(set) var now = Date()
    /// The temperature on screen at this instant, including fades.
    private(set) var appliedKelvin = ColorTemperature.neutral
    private(set) var pause: PauseReason?
    private(set) var isPreviewing = false
    /// Another running app that also rewrites the gamma tables.
    private(set) var conflictingApp: NSRunningApplication?

    let location = LocationService()

    @ObservationIgnored private let gamma = GammaController()
    @ObservationIgnored private var previewKelvin: Double?
    @ObservationIgnored private var previewHeld = false
    @ObservationIgnored private var previewExpiry: DispatchWorkItem?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var fadeTimer: Timer?
    @ObservationIgnored private var lastFadeStep: CFTimeInterval = 0
    @ObservationIgnored private var isRunning = false

    private init() {
        prefs = Preferences.load()
        location.onResolve = { [weak self] coordinate, name in
            self?.prefs.coordinate = coordinate
            self?.prefs.locationName = name
        }
    }

    // MARK: - Derived state

    var schedule: Schedule { prefs.schedule }
    var timeline: Timeline { schedule.timeline(around: now) }
    var scheduledKelvin: Double { timeline.kelvin(at: now) }
    var currentPhase: Phase { timeline.phase(at: now) }

    /// One line describing what the display is doing and what comes next.
    var statusLine: String {
        guard prefs.isEnabled else { return "Off" }
        if isPreviewing { return "Previewing" }
        switch pause {
        case .app(let app):
            return "Paused while \(app.name) is in front"
        case .fullScreen(let name):
            return "Paused while \(name ?? "an app") is in full screen"
        case nil:
            let timeline = timeline
            let phase = timeline.phase(at: now).title
            guard let next = timeline.nextEvent(after: now) else { return phase }
            return "\(phase) · \(next.kind.title) at \(next.date.clockTime)"
        }
    }

    private var targetKelvin: Double {
        guard prefs.isEnabled else { return ColorTemperature.neutral }
        if let previewKelvin { return previewKelvin }
        return pause == nil ? scheduledKelvin : ColorTemperature.neutral
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSystem()

        let heartbeat = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        heartbeat.tolerance = 0.4
        RunLoop.main.add(heartbeat, forMode: .common)
        self.heartbeat = heartbeat

        refresh()
        if let coordinate = prefs.coordinate, prefs.locationName == nil {
            Task { await location.resolveName(for: coordinate) }
        }
    }

    func stop() {
        isRunning = false
        heartbeat?.invalidate()
        fadeTimer?.invalidate()
        gamma.reset()
    }

    /// Re-evaluates everything. Cheap, and called both on a slow heartbeat
    /// and whenever the system tells us something relevant changed.
    func refresh() {
        guard isRunning else { return }
        now = Date()

        let conflict = NSRunningApplication.runningApplications(withBundleIdentifier: "org.herf.Flux").first
        if conflict != conflictingApp { conflictingApp = conflict }

        let reason = evaluatePause()
        if reason != pause { pause = reason }
        retarget()
    }

    private func evaluatePause() -> PauseReason? {
        guard prefs.isEnabled else { return nil }
        if let app = AppExceptions.appInFront(among: prefs.exceptionApps) { return .app(app) }
        if prefs.disableForFullScreen, SpaceInspector.isFullScreenActive() {
            return .fullScreen(appName: NSWorkspace.shared.menuBarOwningApplication?.localizedName)
        }
        return nil
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in workspaceEvents {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemChanged() }
            }
        }

        let displayEvents: [Notification.Name] = [
            NSApplication.didChangeScreenParametersNotification,
            NSScreen.colorSpaceDidChangeNotification,
        ]
        for name in displayEvents {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.gamma.invalidateBaselines()
                    self?.systemChanged()
                }
            }
        }

        // The clock, and our own Settings window coming to the front or leaving it.
        let localEvents: [Notification.Name] = [
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]
        for name in localEvents {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Windows and Spaces take a moment to settle after the notification, and
    /// macOS may reload display profiles late after waking, so look again.
    private func systemChanged() {
        refresh()
        for delay in [0.6, 1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    // MARK: - Applying color

    private func retarget() {
        let target = targetKelvin
        if abs(target - appliedKelvin) > 40 {
            startFade()
        } else if fadeTimer == nil {
            // The schedule drifts by a few kelvin per heartbeat: no fade needed.
            apply(target)
        }
    }

    private func apply(_ kelvin: Double) {
        if appliedKelvin != kelvin { appliedKelvin = kelvin }
        gamma.apply(ColorTemperature.gain(kelvin: kelvin))
    }

    private func startFade() {
        guard fadeTimer == nil else { return }
        lastFadeStep = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    /// Eases toward the target; also follows it smoothly while a slider moves.
    private func fadeStep() {
        let time = CACurrentMediaTime()
        let elapsed = min(time - lastFadeStep, 0.1)
        lastFadeStep = time

        let target = targetKelvin
        var next = ColorTemperature.mix(appliedKelvin, target, 1 - exp(-elapsed / 0.16))
        if abs(next - target) < 12 {
            next = target
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        apply(next)
    }

    // MARK: - Actions

    func isException(_ app: AppIdentity) -> Bool {
        prefs.exceptionApps.contains { $0.bundleID == app.bundleID }
    }

    func setException(_ app: AppIdentity, enabled: Bool) {
        if enabled {
            guard !isException(app) else { return }
            prefs.exceptionApps.append(app)
        } else {
            prefs.exceptionApps.removeAll { $0.bundleID == app.bundleID }
        }
    }

    /// Shows a temperature on screen straight away, ignoring schedule and
    /// pauses (but not the main switch: off means off). `beginPreview` keeps
    /// it up while a slider is held.
    func beginPreview() {
        previewHeld = true
        previewExpiry?.cancel()
    }

    func preview(_ kelvin: Double) {
        guard prefs.isEnabled else { return }
        previewKelvin = kelvin
        if !isPreviewing { isPreviewing = true }
        if !previewHeld { schedulePreviewExpiry() }
        retarget()
    }

    func endPreview() {
        previewHeld = false
        if previewKelvin != nil { schedulePreviewExpiry() }
    }

    private func schedulePreviewExpiry() {
        previewExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            previewKelvin = nil
            isPreviewing = false
            refresh()
        }
        previewExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: expiry)
    }
}

extension Timeline.Event.Kind {
    nonisolated var title: String {
        switch self {
        case .sunrise: "Sunrise"
        case .sunset: "Sunset"
        case .bedtime: "Bedtime"
        case .wake: "Wake up"
        }
    }
}

extension Date {
    nonisolated var clockTime: String {
        formatted(date: .omitted, time: .shortened)
    }
}
