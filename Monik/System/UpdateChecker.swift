import Foundation
import Observation

nonisolated struct ReleaseVersion: Comparable, Sendable {
    private let components: [Int]

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// Checks for a stable GitHub release; downloading and installation stay manual.
@MainActor @Observable
final class UpdateChecker {
    nonisolated struct Release: Codable, Sendable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", draft, prerelease
        }

        var stableVersion: ReleaseVersion? {
            guard !draft, !prerelease else { return nil }
            return ReleaseVersion(tagName)
        }

        var versionLabel: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
        var downloadURL: URL {
            URL(string: "https://github.com/Astatine-213-Tian/monik/releases/tag/\(tagName)")!
        }
    }

    enum State { case idle, checking, upToDate, available, failed }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private(set) var state = State.idle
    private(set) var availableRelease: Release?

    var isChecking: Bool { state == .checking }

    @ObservationIgnored private let installedVersion: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    private static let lastAttemptKey = "lastUpdateCheckAttempt"
    private static let cachedReleaseKey = "latestCheckedRelease"

    init(
        installedVersion: String = UpdateChecker.currentVersion,
        defaults: UserDefaults = .standard,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.installedVersion = installedVersion
        self.defaults = defaults
        self.fetch = fetch
        if let data = defaults.data(forKey: Self.cachedReleaseKey),
           let release = try? JSONDecoder().decode(Release.self, from: data),
           let latest = release.stableVersion,
           let current = ReleaseVersion(installedVersion), latest > current {
            availableRelease = release
            state = .available
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        automaticTask?.cancel()
        automaticTask = nil
        guard enabled else { return }
        automaticTask = Task { [weak self] in
            while !Task.isCancelled, self != nil {
                if self?.isAutomaticCheckDue() == true {
                    await self?.checkForUpdates()
                }
                do { try await Task.sleep(for: .seconds(3600)) }
                catch { return }
            }
        }
    }

    func isAutomaticCheckDue(at date: Date = Date()) -> Bool {
        guard let lastAttempt = defaults.object(forKey: Self.lastAttemptKey) as? Date else { return true }
        let elapsed = date.timeIntervalSince(lastAttempt)
        return elapsed >= 24 * 60 * 60 || elapsed < 0
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        let previousState = state
        state = .checking
        defaults.set(Date(), forKey: Self.lastAttemptKey)
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Astatine-213-Tian/monik/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Monik/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                state = .failed
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let latest = release.stableVersion,
                  let current = ReleaseVersion(installedVersion) else {
                state = .failed
                return
            }
            availableRelease = latest > current ? release : nil
            state = availableRelease == nil ? .upToDate : .available
            defaults.set(try JSONEncoder().encode(release), forKey: Self.cachedReleaseKey)
        } catch {
            state = Task.isCancelled ? previousState : .failed
        }
    }
}
