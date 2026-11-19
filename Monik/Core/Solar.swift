import Foundation

nonisolated struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Accepts "43.3, 5.4" style input.
    init?(parsing text: String) {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        self.init(latitude: parts[0], longitude: parts[1])
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var formatted: String {
        let lat = String(format: "%.2f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.2f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat), \(lon)"
    }
}

nonisolated enum SunDay: Equatable, Sendable {
    case regular(sunrise: Date, sunset: Date)
    /// Midnight sun: the sun stays above the horizon all day.
    case alwaysUp
    /// Polar night: the sun never rises.
    case alwaysDown
}

nonisolated enum Solar {
    /// Sunrise and sunset for the solar day whose noon is closest to `midday`.
    /// Standard sunrise equation, accurate to about a minute at mid latitudes.
    static func day(around midday: Date, at coordinate: Coordinate) -> SunDay {
        let rad = Double.pi / 180
        let latitude = min(max(coordinate.latitude, -89.9), 89.9)
        let east = coordinate.longitude

        let julian = midday.timeIntervalSince1970 / 86400 + 2440587.5
        let dayNumber = (julian - 2451545.0 + east / 360).rounded()
        let meanNoon = dayNumber + 0.0009 - east / 360

        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360) * rad
        let center = 1.9148 * sin(anomaly) + 0.0200 * sin(2 * anomaly) + 0.0003 * sin(3 * anomaly)
        let longitude = (anomaly / rad + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360) * rad
        let transit = 2451545.0 + meanNoon + 0.0053 * sin(anomaly) - 0.0069 * sin(2 * longitude)

        let sinDeclination = sin(longitude) * sin(23.4397 * rad)
        let cosDeclination = cos(asin(sinDeclination))
        // -0.833° puts the sun's upper edge on the horizon, allowing for refraction.
        let cosHourAngle = (sin(-0.833 * rad) - sin(latitude * rad) * sinDeclination)
            / (cos(latitude * rad) * cosDeclination)

        if cosHourAngle > 1 { return .alwaysDown }
        if cosHourAngle < -1 { return .alwaysUp }

        let halfDay = acos(cosHourAngle) / (2 * .pi)
        return .regular(sunrise: date(julian: transit - halfDay), sunset: date(julian: transit + halfDay))
    }

    private static func date(julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2440587.5) * 86400)
    }
}
