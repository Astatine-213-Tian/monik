import Foundation

nonisolated enum TransitionSpeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick, natural, gentle

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .quick: 20 * 60
        case .natural: 60 * 60
        case .gentle: 120 * 60
        }
    }

    var title: String {
        switch self {
        case .quick: "Quick (20 minutes)"
        case .natural: "Natural (1 hour)"
        case .gentle: "Gentle (2 hours)"
        }
    }
}

/// Everything the user can change, stored as one JSON value.
nonisolated struct Preferences: Codable, Equatable, Sendable {
    /// The main switch in the menu bar panel.
    var isEnabled = true
    var dayKelvin = ColorTemperature.neutral
    var sunsetKelvin = 3400.0
    var bedtimeKelvin = ColorTemperature.warmest
    /// Minutes after midnight.
    var bedtimeMinutes = 23 * 60
    var wakeMinutes = 7 * 60
    var transition = TransitionSpeed.natural
    var coordinate: Coordinate?
    var locationName: String?
    var disableForFullScreen = true
    var exceptionApps: [AppIdentity] = []
    var automaticallyCheckForUpdates = true

    init() {}

    // Missing keys fall back to defaults so settings survive app updates.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        dayKelvin = try values.decodeIfPresent(Double.self, forKey: .dayKelvin) ?? defaults.dayKelvin
        sunsetKelvin = try values.decodeIfPresent(Double.self, forKey: .sunsetKelvin) ?? defaults.sunsetKelvin
        bedtimeKelvin = try values.decodeIfPresent(Double.self, forKey: .bedtimeKelvin) ?? defaults.bedtimeKelvin
        bedtimeMinutes = try values.decodeIfPresent(Int.self, forKey: .bedtimeMinutes) ?? defaults.bedtimeMinutes
        wakeMinutes = try values.decodeIfPresent(Int.self, forKey: .wakeMinutes) ?? defaults.wakeMinutes
        transition = try values.decodeIfPresent(TransitionSpeed.self, forKey: .transition) ?? defaults.transition
        coordinate = try values.decodeIfPresent(Coordinate.self, forKey: .coordinate)
        locationName = try values.decodeIfPresent(String.self, forKey: .locationName)
        disableForFullScreen = try values.decodeIfPresent(Bool.self, forKey: .disableForFullScreen) ?? defaults.disableForFullScreen
        exceptionApps = try values.decodeIfPresent([AppIdentity].self, forKey: .exceptionApps) ?? defaults.exceptionApps
        automaticallyCheckForUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? defaults.automaticallyCheckForUpdates
    }

    subscript(phase: Phase) -> Double {
        get {
            switch phase {
            case .day: dayKelvin
            case .sunset: sunsetKelvin
            case .bedtime: bedtimeKelvin
            }
        }
        set {
            switch phase {
            case .day: dayKelvin = newValue
            case .sunset: sunsetKelvin = newValue
            case .bedtime: bedtimeKelvin = newValue
            }
        }
    }

    var schedule: Schedule {
        Schedule(
            dayKelvin: dayKelvin,
            sunsetKelvin: sunsetKelvin,
            bedtimeKelvin: bedtimeKelvin,
            bedtimeMinutes: bedtimeMinutes,
            wakeMinutes: wakeMinutes,
            transition: transition.duration,
            coordinate: coordinate
        )
    }
}

// MARK: - Storage

extension Preferences {
    private static let storageKey = "preferences"

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            return stored
        }
        var fresh = Preferences()
        fresh.adoptFluxSettings()
        return fresh
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// On first launch, start from what the user already told f.lux (location,
    /// wake time and colors) instead of asking again. f.lux is never modified.
    private mutating func adoptFluxSettings() {
        guard let flux = UserDefaults.standard.persistentDomain(forName: "org.herf.Flux") else { return }

        if let location = flux["location"] as? String, let parsed = Coordinate(parsing: location) {
            coordinate = parsed
        }
        if let wake = flux["wakeTime"] as? Int, (0..<1440).contains(wake) {
            wakeMinutes = wake
            bedtimeMinutes = (wake + 16 * 60) % 1440 // eight hours of sleep
        }
        if let day = flux["dayColorTemp"] as? Double { dayKelvin = ColorTemperature.clamp(day) }
        if let sunset = flux["nightColorTemp"] as? Double { sunsetKelvin = ColorTemperature.clamp(sunset) }
        if let late = flux["lateColorTemp"] as? Double { bedtimeKelvin = ColorTemperature.clamp(late) }
        if let fullScreen = flux["disableFullscreen"] as? Bool { disableForFullScreen = fullScreen }
    }
}
