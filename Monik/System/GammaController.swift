import CoreGraphics

/// Tints every connected display by scaling its transfer (gamma) table.
///
/// Each display keeps the table from its own color profile as a baseline and
/// receives the same per-channel gain on top, so built-in and external
/// monitors always share one white point. The tables belong to the display,
/// not to a window or Space, which is why the tint follows you everywhere.
final class GammaController {
    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]

        static let linear: Table = {
            let ramp = (0..<256).map { CGGammaValue($0) / 255 }
            return Table(red: ramp, green: ramp, blue: ramp)
        }()
    }

    private var baselines: [CGDirectDisplayID: Table] = [:]
    private var isTinted = false

    /// Writes `gain` to all displays. Safe to call repeatedly: macOS quietly
    /// reloads profile tables after wake and display changes, so the current
    /// tint is simply asserted again.
    func apply(_ gain: ChannelGain) {
        guard !gain.isIdentity else {
            reset()
            return
        }

        let displays = onlineDisplays()
        if !isTinted || displays.contains(where: { baselines[$0] == nil }) {
            // Start from pristine profile tables so a baseline can never
            // include our own (or anyone else's) tint.
            CGDisplayRestoreColorSyncSettings()
            baselines = Dictionary(uniqueKeysWithValues: displays.map { ($0, capture($0)) })
        }

        for display in displays {
            guard let base = baselines[display] else { continue }
            let red = base.red.map { $0 * CGGammaValue(gain.red) }
            let green = base.green.map { $0 * CGGammaValue(gain.green) }
            let blue = base.blue.map { $0 * CGGammaValue(gain.blue) }
            CGSetDisplayTransferByTable(display, UInt32(red.count), red, green, blue)
        }
        isTinted = true
    }

    /// Hands the displays back to their color profiles, untouched.
    func reset() {
        guard isTinted else { return }
        CGDisplayRestoreColorSyncSettings()
        baselines.removeAll()
        isTinted = false
    }

    /// Call when displays are added, removed or get a new profile.
    func invalidateBaselines() {
        baselines.removeAll()
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func capture(_ display: CGDirectDisplayID) -> Table {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 1 else { return .linear }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success,
              count > 1 else { return .linear }
        let n = Int(count)
        return Table(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }
}
