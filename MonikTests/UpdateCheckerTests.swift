import Foundation
import Testing

@Suite @MainActor
struct UpdateCheckerTests {
    private func withChecker(
        tag: String = "v0.1.3", status: Int = 200, destination: String? = nil,
        failure: URLError? = nil, onFetch: @escaping @Sendable () -> Void = {},
        body: @MainActor (UpdateChecker, UserDefaults) async -> Void
    ) async {
        let suite = "com.monik.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let resolvedURL = URL(string: destination ?? "https://github.com/Astatine-213-Tian/monik/releases/tag/\(tag)")!
        let checker = UpdateChecker(installedVersion: "0.1.2", defaults: defaults) { request in
            #expect(request.url?.absoluteString == "https://github.com/Astatine-213-Tian/monik/releases/latest")
            #expect(request.httpMethod == "HEAD")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            onFetch()
            if let failure { throw failure }
            return (Data(), HTTPURLResponse(url: resolvedURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        await body(checker, defaults)
        checker.setAutomaticChecksEnabled(false)
    }

    @Test func comparesNumericVersions() {
        #expect(ReleaseVersion("v0.1.10")! > ReleaseVersion("0.1.9")!)
        #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        #expect(ReleaseVersion("v0.1.2") == ReleaseVersion("0.1.2"))
    }

    @Test(arguments: ["", "1.2", "1..2", "1.2.3.4", "v1.2.3-beta", "1.2.-3", "../../bad"])
    func rejectsInvalidVersions(_ value: String) {
        #expect(ReleaseVersion(value) == nil)
    }

    @Test func readsVersionFromPublicLatestReleaseRedirect() async {
        await withChecker { checker, _ in
            await checker.checkForUpdates()
            #expect(checker.state == .available)
            #expect(checker.availableRelease?.versionLabel == "0.1.3")
            #expect(checker.availableRelease?.downloadURL.absoluteString == "https://github.com/Astatine-213-Tian/monik/releases/tag/v0.1.3")
        }
    }

    @Test(arguments: ["v0.1.2", "v0.1.1", "v0.0.9"])
    func neverOffersADowngrade(_ tag: String) async {
        await withChecker(tag: tag) { checker, _ in
            await checker.checkForUpdates()
            #expect(checker.state == .upToDate)
            #expect(checker.availableRelease == nil)
        }
    }

    @Test(arguments: [403, 404, 429, 500])
    func handlesServerErrors(_ status: Int) async {
        await withChecker(status: status) { checker, _ in
            await checker.checkForUpdates()
            #expect(checker.state == .failed)
            #expect(!checker.isAutomaticCheckDue())
        }
    }

    @Test(arguments: [
        "http://github.com/Astatine-213-Tian/monik/releases/tag/v9.0.0",
        "https://example.com/Astatine-213-Tian/monik/releases/tag/v9.0.0",
        "https://github.com/someone/else/releases/tag/v9.0.0",
        "https://github.com/Astatine-213-Tian/monik/releases/latest",
        "https://github.com/Astatine-213-Tian/monik/releases/tag/v9.0.0-beta",
        "https://github.com/Astatine-213-Tian/monik/releases/tag/not-a-version"
    ])
    func rejectsInvalidReleaseDestinations(_ destination: String) async {
        await withChecker(destination: destination) { checker, _ in
            await checker.checkForUpdates()
            #expect(checker.state == .failed)
            #expect(checker.availableRelease == nil)
        }
    }

    @Test func handlesOfflineChecks() async {
        await withChecker(failure: URLError(.notConnectedToInternet)) { checker, _ in
            await checker.checkForUpdates()
            #expect(checker.state == .failed)
            #expect(!checker.isChecking)
        }
    }

    @Test func limitsAutomaticChecksAcrossRelaunchesButAllowsManualChecks() async {
        await withChecker { checker, defaults in
            #expect(checker.isAutomaticCheckDue())
            await checker.checkForUpdates()
            let now = Date()
            #expect(!checker.isAutomaticCheckDue(at: now))
            #expect(!checker.isAutomaticCheckDue(at: now.addingTimeInterval(23 * 3600)))
            #expect(checker.isAutomaticCheckDue(at: now.addingTimeInterval(24 * 3600)))
            let relaunched = UpdateChecker(installedVersion: "0.1.2", defaults: defaults)
            #expect(!relaunched.isAutomaticCheckDue())
            #expect(relaunched.state == .available)
            #expect(relaunched.availableRelease?.versionLabel == "0.1.3")
            let updated = UpdateChecker(installedVersion: "0.1.3", defaults: defaults)
            #expect(updated.availableRelease == nil)
            await checker.checkForUpdates()
            #expect(checker.state == .available)
        }
    }

    @Test func disablingAutomaticChecksCancelsQueuedWork() async {
        await withChecker { checker, _ in
            checker.setAutomaticChecksEnabled(true)
            checker.setAutomaticChecksEnabled(false)
            await Task.yield()
            #expect(checker.state == .idle)
            #expect(checker.isAutomaticCheckDue())
        }
    }

    @Test(arguments: [
        "not JSON",
        "{\"tag_name\":\"../../bad\",\"draft\":false,\"prerelease\":false}",
        "{\"tag_name\":\"v9.0.0\",\"draft\":false,\"prerelease\":true}"
    ])
    func ignoresInvalidCachedReleases(_ payload: String) async {
        await withChecker { _, defaults in
            defaults.set(Data(payload.utf8), forKey: "latestCheckedRelease")
            let checker = UpdateChecker(installedVersion: "0.1.2", defaults: defaults)
            #expect(checker.availableRelease == nil)
            #expect(checker.state == .idle)
        }
    }

    @Test(.timeLimit(.minutes(1))) func enablingAutomaticChecksFetchesTheLatestRelease() async {
        let (events, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        await withChecker(onFetch: { continuation.yield() }) { checker, _ in
            checker.setAutomaticChecksEnabled(true)
            var iterator = events.makeAsyncIterator()
            await iterator.next()
            while checker.isChecking { await Task.yield() }
            #expect(checker.state == .available)
        }
    }
}
