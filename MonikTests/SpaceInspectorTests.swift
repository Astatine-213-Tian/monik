import CoreGraphics
import Testing

@Suite struct FullScreenDetectionTests {
    private let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    private func window(layer: Int, alpha: Double = 1, bounds: CGRect? = nil) -> WindowList.Window {
        WindowList.Window(owner: 1, layer: layer, alpha: alpha, bounds: bounds ?? display)
    }

    @Test func aWindowAboveTheNormalLevelThatFillsADisplayCoversIt() {
        #expect(window(layer: Int(CGWindowLevelForKey(.screenSaverWindow))).coversDisplay(among: [display]))
        #expect(window(layer: Int(CGShieldingWindowLevel())).coversDisplay(among: [display]))
    }

    @Test func anOrdinaryWindowThatFillsTheDisplayDoesNot() {
        #expect(!window(layer: 0).coversDisplay(among: [display]))
    }

    @Test func aSmallerOrSeeThroughWindowDoesNot() {
        let level = Int(CGWindowLevelForKey(.screenSaverWindow))
        #expect(!window(layer: level, bounds: display.insetBy(dx: 0, dy: 20)).coversDisplay(among: [display]))
        #expect(!window(layer: level, alpha: 0.5).coversDisplay(among: [display]))
    }

    /// What a drag out of Finder puts on screen for as long as it lasts, as
    /// measured on macOS 26: opaque, display-sized, layer 500.
    @Test func theOverlayOfADragInProgressDoesNot() {
        #expect(!window(layer: 500).coversDisplay(among: [display]))
    }
}
