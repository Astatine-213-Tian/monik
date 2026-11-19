import SwiftUI

/// The day as something you can read and adjust in place. The curve's height
/// is the screen's color, the bar underneath is the night, and the two knobs
/// at its ends are bedtime and wake time: drag one and the curve follows.
struct ScheduleChart: View {
    @Environment(AppModel.self) private var model
    var plotHeight: CGFloat = 78

    /// The 24 hours on show. Centred on the waking day when the chart comes
    /// on screen, then left where it is: moving a knob moves the middle of
    /// the night, and centring on that again would slide the whole chart
    /// sideways the moment the knob is let go.
    @State private var window: DateInterval?
    @State private var drag: KnobDrag?
    /// The bedtime and wake time this chart last set, to tell its own
    /// changes from ones made elsewhere.
    @State private var written: [Int] = []

    private struct KnobDrag {
        var kind: Timeline.Event.Kind
        /// Where the knob was when the drag began.
        var origin: Date
        /// The knob was pushed against an end of the chart.
        var reachedEdge = false
    }

    /// Knobs stop this far short of the chart's ends, where they would
    /// otherwise wrap round to the other side.
    private static let edgeMargin: TimeInterval = 3600
    private static let trackHeight: CGFloat = 22
    private static let labelHeight: CGFloat = 13
    private static let knobSize: CGFloat = 20
    private static let coordinates = "ScheduleChart"

    var body: some View {
        let schedule = model.schedule
        let window = window ?? schedule.chartWindow(containing: model.now)
        let timeline = schedule.timeline(around: window.start + window.duration / 2)
        let events = timeline.events(in: window)

        GeometryReader { geometry in
            let scale = Scale(window: window, width: geometry.size.width, height: plotHeight)
            VStack(spacing: 3) {
                plot(timeline, events, scale)
                    .frame(height: plotHeight)
                track(timeline, events, scale)
                    .frame(height: Self.trackHeight)
                times(events, scale)
                    .frame(height: Self.labelHeight)
            }
        }
        .frame(height: plotHeight + Self.trackHeight + Self.labelHeight + 6)
        .coordinateSpace(.named(Self.coordinates))
        .onAppear(perform: centre)
        .onChange(of: model.now) {
            // Past the end of the day on show: move on to the next one.
            if drag == nil, let held = self.window, !held.contains(model.now) { centre() }
        }
        .onChange(of: [model.prefs.bedtimeMinutes, model.prefs.wakeMinutes]) { _, times in
            // Changed somewhere else, such as the time fields in Settings.
            if times != written { centre() }
        }
    }

    private func centre() {
        window = model.schedule.chartWindow(containing: model.now)
    }

    // MARK: - Curve

    private func plot(_ timeline: Timeline, _ events: [Timeline.Event], _ scale: Scale) -> some View {
        let count = 144
        let dates = (0...count).map { scale.window.start + scale.window.duration * Double($0) / Double(count) }
        let kelvins = dates.map(timeline.kelvin(at:))
        let points = kelvins.enumerated().map { index, kelvin in
            CGPoint(x: scale.width * CGFloat(index) / CGFloat(count), y: scale.y(kelvin))
        }
        let warmth = LinearGradient(
            stops: stride(from: 0, through: count, by: 6).map { index in
                .init(color: .temperature(kelvins[index]), location: Double(index) / Double(count))
            },
            startPoint: .leading,
            endPoint: .trailing
        )
        let line = Path { $0.addLines(points) }
        let area = Path { path in
            path.addLines(points)
            path.addLine(to: CGPoint(x: scale.width, y: scale.height))
            path.addLine(to: CGPoint(x: 0, y: scale.height))
            path.closeSubpath()
        }
        let now = model.now
        let current = timeline.kelvin(at: now)

        return ZStack(alignment: .topLeading) {
            area.fill(warmth)
                .opacity(0.22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Each knob is tied to the bend it controls.
            Path { path in
                for event in events where event.kind.isAdjustable {
                    path.move(to: CGPoint(x: scale.x(event.date), y: scale.y(timeline.kelvin(at: event.date))))
                    path.addLine(to: CGPoint(x: scale.x(event.date), y: scale.height))
                }
            }
            .stroke(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

            line.stroke(warmth, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            ForEach(plateaus(dates: dates, timeline: timeline)) { plateau in
                if scale.x(plateau.end) - scale.x(plateau.start) >= 22 {
                    Image(systemName: plateau.phase.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .position(x: scale.x(plateau.middle), y: scale.y(timeline.kelvin(at: plateau.middle)) - 13)
                        .help(plateau.phase.title)
                }
            }

            if scale.window.contains(now) {
                Circle()
                    .fill(.white)
                    .stroke(Color.temperature(current), lineWidth: 3)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(x: scale.x(now), y: scale.y(current))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Color temperature over the day")
        .accessibilityValue("\(kelvinLabel(current)) now")
    }

    private struct Plateau: Identifiable {
        let phase: Phase
        let start: Date
        let end: Date
        var middle: Date { start + end.timeIntervalSince(start) / 2 }
        var id: Phase { phase }
    }

    /// The longest unbroken stretch of each phase, which is where its icon goes.
    private func plateaus(dates: [Date], timeline: Timeline) -> [Plateau] {
        var runs: [Plateau] = []
        for date in dates {
            let phase = timeline.phase(at: date)
            if let last = runs.last, last.phase == phase {
                runs[runs.count - 1] = Plateau(phase: phase, start: last.start, end: date)
            } else {
                runs.append(Plateau(phase: phase, start: date, end: date))
            }
        }
        return Phase.allCases.compactMap { phase in
            runs.filter { $0.phase == phase }
                .max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
        }
    }

    // MARK: - Night bar and knobs

    private func track(_ timeline: Timeline, _ events: [Timeline.Event], _ scale: Scale) -> some View {
        let middle = Self.trackHeight / 2
        let knobs = events.filter(\.kind.isAdjustable)
        let nights = timeline.sleep.compactMap { span -> (CGFloat, CGFloat)? in
            let start = max(span.start, scale.window.start)
            let end = min(span.end, scale.window.end)
            return start < end ? (scale.x(start), scale.x(end)) : nil
        }

        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.primary.opacity(0.08))
                .frame(width: scale.width, height: 4)
                .position(x: scale.width / 2, y: middle)

            ForEach(nights, id: \.0) { night in
                Capsule()
                    .fill(Color.night.opacity(0.8))
                    .frame(width: night.1 - night.0, height: 4)
                    .position(x: (night.0 + night.1) / 2, y: middle)
            }

            // Sunrise and sunset come from the location, so they are marks, not knobs.
            ForEach(events.filter { !$0.kind.isAdjustable }, id: \.date) { event in
                if knobs.allSatisfy({ abs(scale.x($0.date) - scale.x(event.date)) >= Self.knobSize }) {
                    Image(systemName: event.kind.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .position(x: scale.x(event.date), y: middle)
                        .help("\(event.kind.title) at \(event.date.clockTime)")
                }
            }

            ForEach(knobs, id: \.kind) { event in
                knob(event, scale)
                    .position(x: scale.x(event.date), y: middle)
            }
        }
    }

    private func knob(_ event: Timeline.Event, _ scale: Scale) -> some View {
        let isDragging = drag?.kind == event.kind
        return Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2, y: 1)
            .overlay {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.night)
            }
            .frame(width: Self.knobSize, height: Self.knobSize)
            .scaleEffect(isDragging ? 1.12 : 1)
            .animation(.snappy(duration: 0.15), value: isDragging)
            .contentShape(Circle().inset(by: -5))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinates))
                    .onChanged { value in
                        var current = drag ?? KnobDrag(kind: event.kind, origin: event.date)
                        let moved = (value.translation.width / scale.width * 1440 / 5).rounded() * 5 * 60
                        let wanted = current.origin + moved
                        let date = min(max(wanted, scale.window.start + Self.edgeMargin),
                                       scale.window.end - Self.edgeMargin)
                        current.reachedEdge = date != wanted
                        drag = current
                        setMinutes(minutes(at: date), for: event.kind)
                    }
                    .onEnded { _ in
                        let reachedEdge = drag?.reachedEdge == true
                        drag = nil
                        // Out of room: centre again so the knob can go further.
                        if reachedEdge { centre() }
                    }
            )
            .help(event.kind.title)
            .accessibilityElement()
            .accessibilityLabel(event.kind.title)
            .accessibilityValue(event.date.clockTime)
            .accessibilityAdjustableAction { direction in
                setMinutes(minutes(of: event.kind) + (direction == .increment ? 15 : -15), for: event.kind)
            }
    }

    private func minutes(at date: Date) -> Int {
        let parts = model.schedule.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func minutes(of kind: Timeline.Event.Kind) -> Int {
        kind == .bedtime ? model.prefs.bedtimeMinutes : model.prefs.wakeMinutes
    }

    /// Moves bedtime or wake time, always leaving at least an hour awake and
    /// an hour asleep so the two knobs can't cross.
    private func setMinutes(_ value: Int, for kind: Timeline.Event.Kind) {
        func wrapped(_ minutes: Int) -> Int { (minutes % 1440 + 1440) % 1440 }
        var bedtime = model.prefs.bedtimeMinutes
        var wake = model.prefs.wakeMinutes
        if kind == .bedtime { bedtime = wrapped(value) } else { wake = wrapped(value) }

        let awake = min(max(wrapped(bedtime - wake), 60), 1380)
        if kind == .bedtime { bedtime = wrapped(wake + awake) } else { wake = wrapped(bedtime - awake) }

        written = [bedtime, wake]
        if bedtime != model.prefs.bedtimeMinutes { model.prefs.bedtimeMinutes = bedtime }
        if wake != model.prefs.wakeMinutes { model.prefs.wakeMinutes = wake }
    }

    // MARK: - Times

    private struct TimeLabel: Identifiable {
        let event: Timeline.Event
        let text: String
        let x: CGFloat
        /// Close enough for deciding whether two labels would touch.
        var width: CGFloat { CGFloat(text.count) * 5.6 }
        var id: Date { event.date }
    }

    private func times(_ events: [Timeline.Event], _ scale: Scale) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(timeLabels(events, scale)) { label in
                let isKnob = label.event.kind.isAdjustable
                Text(label.text)
                    .font(.system(size: 10, weight: isKnob ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(drag?.kind == label.event.kind ? .primary : isKnob ? .secondary : .tertiary)
                    .fixedSize()
                    .position(x: label.x, y: Self.labelHeight / 2)
            }
        }
    }

    /// Bedtime and wake time are always labelled; sunrise and sunset only
    /// where there is room beside them.
    private func timeLabels(_ events: [Timeline.Event], _ scale: Scale) -> [TimeLabel] {
        var placed: [TimeLabel] = []
        for event in events.sorted(by: { $0.kind.isAdjustable && !$1.kind.isAdjustable }) {
            var label = TimeLabel(event: event, text: event.date.clockTime, x: scale.x(event.date))
            label = TimeLabel(event: event, text: label.text,
                              x: min(max(label.x, label.width / 2), scale.width - label.width / 2))
            if placed.allSatisfy({ abs($0.x - label.x) >= ($0.width + label.width) / 2 + 5 }) {
                placed.append(label)
            }
        }
        return placed
    }
}

/// Maps time and temperature onto the plot.
private struct Scale {
    let window: DateInterval
    let width: CGFloat
    let height: CGFloat

    /// Wider than the adjustable range so there is room for an icon above
    /// the daytime line and some fill below the bedtime line.
    private static let kelvins = (ColorTemperature.warmest - 800)...(ColorTemperature.neutral + 1400)

    func x(_ date: Date) -> CGFloat {
        width * date.timeIntervalSince(window.start) / window.duration
    }

    func y(_ kelvin: Double) -> CGFloat {
        let level = (kelvin - Self.kelvins.lowerBound) / (Self.kelvins.upperBound - Self.kelvins.lowerBound)
        return height * (1 - level)
    }
}

extension Timeline.Event.Kind {
    /// Bedtime and wake time are the user's to move; the sun's are not.
    var isAdjustable: Bool { self == .bedtime || self == .wake }

    var symbol: String {
        switch self {
        case .sunrise: "sunrise.fill"
        case .sunset: "sunset.fill"
        case .bedtime: "bed.double.fill"
        case .wake: "alarm.fill"
        }
    }
}
