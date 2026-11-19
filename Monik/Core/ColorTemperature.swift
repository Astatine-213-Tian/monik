import Foundation

/// Per-channel multipliers applied to a display's transfer (gamma) table.
nonisolated struct ChannelGain: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let identity = ChannelGain(red: 1, green: 1, blue: 1)

    var isIdentity: Bool { min(red, green, blue) > 0.9995 }
}

nonisolated enum ColorTemperature {
    /// The display's native white point: no adjustment at all.
    static let neutral: Double = 6500
    /// The warmest setting offered. Lower this to allow candle-like colors.
    static let warmest: Double = 2700
    static let range: ClosedRange<Double> = warmest...neutral

    static func clamp(_ kelvin: Double) -> Double {
        min(max(kelvin, warmest), neutral)
    }

    /// Channel multipliers that move a 6500K display white to `kelvin`.
    ///
    /// The target white is taken from the Planckian locus, expressed relative
    /// to the 6500K point so that neutral is exactly (1, 1, 1), then encoded
    /// for a gamma-2.2 display because transfer tables scale encoded values.
    static func gain(kelvin: Double) -> ChannelGain {
        let kelvin = min(max(kelvin, 1700), neutral)
        guard kelvin < neutral - 0.5 else { return .identity }

        let white = linearRGB(kelvin: kelvin)
        let reference = linearRGB(kelvin: neutral)
        let ratio = [white.0 / reference.0, white.1 / reference.1, white.2 / reference.2]
        let peak = ratio.max() ?? 1
        let encoded = ratio.map { pow(max($0 / peak, 0), 1 / 2.2) }
        return ChannelGain(red: encoded[0], green: encoded[1], blue: encoded[2])
    }

    /// Blends two temperatures in mired (reciprocal) space, where equal steps
    /// look equally large to the eye.
    static func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        let t = min(max(amount, 0), 1)
        let mired = 1e6 / from + (1e6 / to - 1e6 / from) * t
        return 1e6 / mired
    }

    /// Linear sRGB of a black body at `kelvin`, unnormalised.
    /// Chromaticity uses Kim et al.'s approximation of the Planckian locus.
    private static func linearRGB(kelvin t: Double) -> (Double, Double, Double) {
        let x: Double
        if t <= 4000 {
            x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
        } else {
            x = -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
        }

        let y: Double
        if t <= 2222 {
            y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if t <= 4000 {
            y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        }

        let X = x / y
        let Z = (1 - x - y) / y
        return (
            3.2406 * X - 1.5372 - 0.4986 * Z,
            -0.9689 * X + 1.8758 + 0.0415 * Z,
            0.0557 * X - 0.2040 + 1.0570 * Z
        )
    }
}

nonisolated func kelvinLabel(_ kelvin: Double) -> String {
    "\(Int((kelvin / 10).rounded()) * 10)K"
}
