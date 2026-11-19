import Foundation

/// The three colors the day moves between.
nonisolated enum Phase: String, CaseIterable, Identifiable, Sendable {
    case day, sunset, bedtime

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Daytime"
        case .sunset: "Sunset"
        case .bedtime: "Bedtime"
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .bedtime: "moon.fill"
        }
    }
}

/// Everything that shapes the daily curve.
nonisolated struct Schedule: Equatable, Sendable {
    var dayKelvin: Double
    var sunsetKelvin: Double
    var bedtimeKelvin: Double
    /// Minutes after midnight.
    var bedtimeMinutes: Int
    var wakeMinutes: Int
    /// How long each change of color takes.
    var transition: TimeInterval
    /// Without a location the sun is assumed up from 7 AM to 7 PM.
    var coordinate: Coordinate?
    var calendar: Calendar = .autoupdatingCurrent

    func kelvin(at date: Date) -> Double {
        timeline(around: date).kelvin(at: date)
    }

    /// The 24 hours worth drawing for `date`: from the middle of one night to
    /// the middle of the next. Whatever the bedtime, the waking day sits in
    /// the centre with the night split evenly at both edges.
    func chartWindow(containing date: Date) -> DateInterval {
        let asleep = (wakeMinutes - bedtimeMinutes + 1440) % 1440
        let halfNight = TimeInterval((asleep == 0 ? 1440 : asleep) * 30)
        let today = calendar.startOfDay(for: date)
        let starts = (-2...1).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { moment(bedtimeMinutes, after: $0) + halfNight }
        }
        let start = starts.last { $0 <= date } ?? starts.first ?? today
        return DateInterval(start: start, duration: 86400)
    }

    /// Resolves the schedule into concrete moments for the day containing
    /// `date` plus its neighbours, so any instant in that day can be evaluated
    /// with plain arithmetic.
    func timeline(around date: Date) -> Timeline {
        let start = calendar.startOfDay(for: date)
        var daylight: [Timeline.Span] = []
        var sleep: [Timeline.Span] = []
        var events: [Timeline.Event] = []
        var today = SunDay.alwaysDown

        for offset in -1...1 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let sun = sunDay(from: dayStart, to: dayEnd)
            switch sun {
            case .regular(let sunrise, let sunset):
                daylight.append(.init(start: sunrise, end: sunset))
                events.append(.init(kind: .sunrise, date: sunrise))
                events.append(.init(kind: .sunset, date: sunset))
            case .alwaysUp:
                // Padded so the ramps at either end fall outside the day.
                daylight.append(.init(start: dayStart - transition, end: dayEnd + transition))
            case .alwaysDown:
                break
            }

            let bedtime = moment(bedtimeMinutes, after: dayStart)
            var wake = moment(wakeMinutes, after: dayStart)
            if wake <= bedtime { wake = moment(wakeMinutes, after: dayEnd) }
            sleep.append(.init(start: bedtime, end: wake))
            events.append(.init(kind: .bedtime, date: bedtime))
            events.append(.init(kind: .wake, date: wake))

            if offset == 0 { today = sun }
        }

        return Timeline(
            schedule: self,
            sun: today,
            daylight: daylight,
            sleep: sleep,
            events: events.sorted { $0.date < $1.date }
        )
    }

    private func sunDay(from dayStart: Date, to dayEnd: Date) -> SunDay {
        guard let coordinate else {
            return .regular(sunrise: moment(7 * 60, after: dayStart), sunset: moment(19 * 60, after: dayStart))
        }
        let midday = dayStart + dayEnd.timeIntervalSince(dayStart) / 2
        return Solar.day(around: midday, at: coordinate)
    }

    private func moment(_ minutes: Int, after dayStart: Date) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)
            ?? dayStart + TimeInterval(minutes * 60)
    }
}

nonisolated struct Timeline: Sendable {
    struct Span: Equatable, Sendable {
        var start: Date
        var end: Date
    }

    struct Event: Equatable, Sendable {
        enum Kind: Sendable { case sunrise, sunset, bedtime, wake }
        var kind: Kind
        var date: Date
    }

    let schedule: Schedule
    /// Sun times for the day this timeline is centred on.
    let sun: SunDay
    /// Sunrise to sunset, for each covered day.
    let daylight: [Span]
    /// Bedtime to wake time, for each covered night.
    let sleep: [Span]
    let events: [Event]

    /// 0 at night, 1 in full daylight. Each change is centred on sunrise or sunset.
    func daylightLevel(at date: Date) -> Double {
        let length = schedule.transition
        return daylight.map { span in
            min(ease(date, from: span.start - length / 2, over: length),
                1 - ease(date, from: span.end - length / 2, over: length))
        }.max() ?? 0
    }

    /// 0 while awake, 1 while asleep. Winding down finishes exactly at bedtime
    /// and the screen is back to normal by wake time.
    func sleepLevel(at date: Date) -> Double {
        let length = schedule.transition
        return sleep.map { span in
            min(ease(date, from: span.start - length, over: length),
                1 - ease(date, from: span.end - length, over: length))
        }.max() ?? 0
    }

    func kelvin(at date: Date) -> Double {
        let ambient = ColorTemperature.mix(schedule.sunsetKelvin, schedule.dayKelvin, daylightLevel(at: date))
        return ColorTemperature.mix(ambient, schedule.bedtimeKelvin, sleepLevel(at: date))
    }

    /// The color target that currently dominates.
    func phase(at date: Date) -> Phase {
        if sleepLevel(at: date) >= 0.5 { return .bedtime }
        return daylightLevel(at: date) >= 0.5 ? .day : .sunset
    }

    /// The next moment the color will start heading somewhere else.
    func nextEvent(after date: Date) -> Event? {
        let asleep = phase(at: date) == .bedtime
        return events.first { event in
            event.date > date && (asleep ? event.kind == .wake : event.kind != .wake)
        }
    }

    /// The sunrise, sunset, bedtime and wake time that fall inside
    /// `interval`, in the order they happen.
    func events(in interval: DateInterval) -> [Event] {
        var seen: Set<Event.Kind> = []
        return events.filter { event in
            interval.start <= event.date && event.date < interval.end && seen.insert(event.kind).inserted
        }
    }

    private func ease(_ date: Date, from start: Date, over length: TimeInterval) -> Double {
        guard length > 0 else { return date >= start ? 1 : 0 }
        let x = min(max(date.timeIntervalSince(start) / length, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
