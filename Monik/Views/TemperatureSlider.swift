import SwiftUI

/// A warm-to-cool bar for one phase of the day. The bar is the scale, so no
/// labels are needed: slide toward amber for warmer, toward blue for cooler.
/// The screen shows the color while the knob moves.
struct TemperatureSlider: View {
    @Environment(AppModel.self) private var model
    let phase: Phase
    var height: CGFloat = 24

    @State private var isDragging = false

    /// The chart's colors, lightened so three bars in a row stay calm.
    private static let scale = Gradient(colors: stride(from: 0.0, through: 1.0, by: 0.125).map { position in
        Color.temperature(ColorTemperature.warmest + position * (ColorTemperature.neutral - ColorTemperature.warmest))
            .mix(with: .white, by: 0.3)
    })

    var body: some View {
        GeometryReader { geometry in
            let range = ColorTemperature.range
            let travel = max(geometry.size.width - height, 1)
            let position = (model.prefs[phase] - range.lowerBound) / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.linearGradient(Self.scale, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.08)))

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2, y: 1)
                    .overlay {
                        Image(systemName: phase.symbol)
                            .font(.system(size: height * 0.42, weight: .semibold))
                            .foregroundStyle(Color.temperature(model.prefs[phase]).mix(with: .black, by: 0.25))
                    }
                    .padding(2)
                    .frame(width: height, height: height)
                    .offset(x: travel * position)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            model.beginPreview()
                        }
                        let position = min(max((value.location.x - height / 2) / travel, 0), 1)
                        set(range.lowerBound + position * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in
                        isDragging = false
                        model.endPreview()
                    }
            )
        }
        .frame(height: height)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { model.prefs[phase] }, set: { set($0) }),
                in: ColorTemperature.range,
                step: 50
            ) {
                Text("\(phase.title) color temperature")
            }
        }
    }

    private func set(_ kelvin: Double) {
        let rounded = (kelvin / 50).rounded() * 50
        if rounded != model.prefs[phase] { model.prefs[phase] = rounded }
        model.preview(rounded)
    }
}
