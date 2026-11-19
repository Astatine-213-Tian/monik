import CoreLocation
import Observation

/// Finds a coordinate either from the Mac's own location or from a typed
/// place name. The result is only ever used for sunrise and sunset maths.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case working
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored var onResolve: ((Coordinate, String?) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func useCurrentLocation() {
        state = .working
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .failed("Location access is turned off for Monik in System Settings › Privacy & Security.")
        default:
            manager.requestLocation()
        }
    }

    /// Accepts a city, a postcode or raw "latitude, longitude".
    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let coordinate = Coordinate(parsing: query) {
            state = .idle
            onResolve?(coordinate, nil)
            await resolveName(for: coordinate)
            return
        }

        state = .working
        let placemark = try? await geocoder.geocodeAddressString(query).first
        guard let placemark, let location = placemark.location else {
            state = .failed("Couldn’t find “\(query)”.")
            return
        }
        state = .idle
        onResolve?(Coordinate(location.coordinate), placemark.placeName)
    }

    /// Looks up a readable name for a coordinate. Silent when offline.
    func resolveName(for coordinate: Coordinate) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let name = try? await geocoder.reverseGeocodeLocation(location).first?.placeName else { return }
        onResolve?(coordinate, name)
    }

    // Core Location calls its delegate on the thread that created the
    // manager, which is the main thread here.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard state == .working else { return }
            switch self.manager.authorizationStatus {
            case .notDetermined:
                break
            case .denied, .restricted:
                state = .failed("Location access was declined. You can type a city instead.")
            default:
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last.map({ Coordinate($0.coordinate) }) else { return }
        MainActor.assumeIsolated {
            state = .idle
            onResolve?(coordinate, nil)
            Task { await resolveName(for: coordinate) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            state = .failed("Couldn’t determine your location. You can type a city instead.")
        }
    }
}

private extension Coordinate {
    nonisolated init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

private extension CLPlacemark {
    nonisolated var placeName: String? {
        let parts = [locality ?? name, administrativeArea].compactMap { $0 }
        return parts.isEmpty ? country : parts.joined(separator: ", ")
    }
}
