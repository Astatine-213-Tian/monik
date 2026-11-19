import Foundation
import Testing

// Marseille: a mid-latitude place whose November sunrise falls after a 7 AM wake time.
private let paris = TimeZone(identifier: "Europe/Paris")!
private let marseille = Coordinate(latitude: 43.3, longitude: 5.4)

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = paris
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func schedule(bedtime: Int = 23 * 60, wake: Int = 7 * 60, transition: TimeInterval = 3600) -> Schedule {
    Schedule(
        dayKelvin: 6500, sunsetKelvin: 3400, bedtimeKelvin: 2700,
        bedtimeMinutes: bedtime, wakeMinutes: wake,
        transition: transition, coordinate: marseille, calendar: calendar
    )
}

@Suite struct ColorTemperatureTests {
    @Test func neutralLeavesTheDisplayUntouched() {
        #expect(ColorTemperature.gain(kelvin: 6500) == .identity)
        #expect(ColorTemperature.gain(kelvin: 6500).isIdentity)
    }

    @Test func warmerMeansLessBlueThenLessGreen() {
        var previous = ColorTemperature.gain(kelvin: 6400)
        for kelvin in stride(from: 6300.0, through: 2700, by: -100) {
            let gain = ColorTemperature.gain(kelvin: kelvin)
            #expect(gain.red == 1)
            #expect(gain.blue < gain.green)
            #expect(gain.green < previous.green)
            #expect(gain.blue < previous.blue)
            previous = gain
        }
    }

    @Test func matchesKnownWhitePoints() {
        // Within a few percent of the values f.lux writes at 3900K.
        let gain = ColorTemperature.gain(kelvin: 3900)
        #expect(abs(gain.green - 0.82) < 0.03)
        #expect(abs(gain.blue - 0.61) < 0.03)
    }

    @Test func mixingIsExactAtBothEnds() {
        #expect(abs(ColorTemperature.mix(3400, 6500, 0) - 3400) < 0.001)
        #expect(abs(ColorTemperature.mix(3400, 6500, 1) - 6500) < 0.001)
        let middle = ColorTemperature.mix(3400, 6500, 0.5)
        #expect(middle > 3400 && middle < 6500)
    }
}

@Suite struct SolarTests {
    @Test func midLatitudeSunTimes() {
        guard case .regular(let sunrise, let sunset) = Solar.day(around: date(2026, 11, 18), at: marseille) else {
            Issue.record("expected a sunrise and a sunset")
            return
        }
        #expect(abs(sunrise.timeIntervalSince(date(2026, 11, 18, 7, 35))) < 5 * 60)
        #expect(abs(sunset.timeIntervalSince(date(2026, 11, 18, 17, 13))) < 5 * 60)
    }

    @Test func equinoxDayIsAboutTwelveHours() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let noon = utc.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        guard case .regular(let sunrise, let sunset) = Solar.day(around: noon, at: Coordinate(latitude: 0, longitude: 0)) else {
            Issue.record("expected a sunrise and a sunset")
            return
        }
        let length = sunset.timeIntervalSince(sunrise)
        #expect(length > 12 * 3600 && length < 12.25 * 3600)
    }

    @Test func polarDayAndNight() {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        #expect(Solar.day(around: date(2026, 6, 21), at: tromso) == .alwaysUp)
        #expect(Solar.day(around: date(2026, 12, 21), at: tromso) == .alwaysDown)
    }
}

@Suite struct ScheduleTests {
    @Test func holdsEachTargetInItsPartOfTheDay() {
        let plan = schedule()
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 12, 0)) - 6500) < 1)   // midday
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 20, 0)) - 3400) < 1)   // after sunset
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 23, 30)) - 2700) < 1)  // after bedtime
        #expect(abs(plan.kelvin(at: date(2026, 11, 19, 3, 0)) - 2700) < 1)    // small hours
    }

    @Test func sunsetTransitionIsCentredOnSunset() {
        let plan = schedule()
        guard case .regular(_, let sunset) = plan.timeline(around: date(2026, 11, 18)).sun else {
            Issue.record("expected a sunset")
            return
        }
        #expect(abs(plan.kelvin(at: sunset - 1800) - 6500) < 1)
        #expect(abs(plan.kelvin(at: sunset + 1800) - 3400) < 1)
        let halfway = plan.kelvin(at: sunset)
        #expect(abs(halfway - ColorTemperature.mix(3400, 6500, 0.5)) < 1)
    }

    @Test func windsDownIntoBedtimeAndIsNormalByWakeTime() {
        let plan = schedule()
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 22, 0)) - 3400) < 1)   // wind-down starts
        let midway = plan.kelvin(at: date(2026, 11, 18, 22, 30))
        #expect(midway < 3400 && midway > 2700)
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 23, 0)) - 2700) < 1)   // at bedtime
        #expect(abs(plan.kelvin(at: date(2026, 11, 19, 6, 0)) - 2700) < 1)    // an hour before waking
        // By wake time nothing of the bedtime color is left. In November 7 AM
        // is before sunrise, so the screen is at the sunset color, about to
        // start brightening.
        let wake = date(2026, 11, 19, 7, 0)
        let timeline = plan.timeline(around: wake)
        #expect(timeline.sleepLevel(at: wake) == 0)
        #expect(timeline.kelvin(at: wake) >= 3400)
        #expect(timeline.kelvin(at: wake) < 3600)
    }

    @Test func curveNeverJumps() {
        for plan in [schedule(), schedule(bedtime: 60, wake: 9 * 60), schedule(transition: 20 * 60)] {
            var previous = plan.kelvin(at: date(2026, 11, 18, 0, 0))
            for minute in 1...(48 * 60) {
                let now = plan.kelvin(at: date(2026, 11, 18, 0, 0) + TimeInterval(minute * 60))
                #expect(abs(now - previous) < 400, "jump at minute \(minute)")
                previous = now
            }
        }
    }

    @Test func bedtimeAfterMidnight() {
        let plan = schedule(bedtime: 60, wake: 9 * 60)
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 23, 30)) - 3400) < 1)
        #expect(abs(plan.kelvin(at: date(2026, 11, 19, 1, 0)) - 2700) < 1)
        #expect(abs(plan.kelvin(at: date(2026, 11, 19, 9, 0)) - 6500) < 1)
    }

    @Test func reportsPhaseAndNextEvent() {
        let timeline = schedule().timeline(around: date(2026, 11, 18))
        #expect(timeline.phase(at: date(2026, 11, 18, 12, 0)) == .day)
        #expect(timeline.phase(at: date(2026, 11, 18, 20, 0)) == .sunset)
        #expect(timeline.phase(at: date(2026, 11, 18, 23, 30)) == .bedtime)

        #expect(timeline.nextEvent(after: date(2026, 11, 18, 12, 0))?.kind == .sunset)
        #expect(timeline.nextEvent(after: date(2026, 11, 18, 20, 0))?.kind == .bedtime)
        let wake = timeline.nextEvent(after: date(2026, 11, 18, 23, 30))
        #expect(wake?.kind == .wake)
        #expect(wake?.date == date(2026, 11, 19, 7, 0))
    }

    @Test func chartWindowRunsFromMidSleepToMidSleep() {
        // Asleep 9 PM to 9 AM, so the night is halfway through at 3 AM.
        let plan = schedule(bedtime: 21 * 60, wake: 9 * 60)
        for now in [date(2026, 11, 18, 3, 0), date(2026, 11, 18, 12, 0), date(2026, 11, 18, 23, 0), date(2026, 11, 19, 2, 59)] {
            let window = plan.chartWindow(containing: now)
            #expect(window.start == date(2026, 11, 18, 3, 0))
            #expect(window.end == date(2026, 11, 19, 3, 0))
        }
        #expect(plan.chartWindow(containing: date(2026, 11, 19, 3, 0)).start == date(2026, 11, 19, 3, 0))

        // A bedtime after midnight: asleep 1 AM to 9 AM, halfway at 5 AM.
        let late = schedule(bedtime: 60, wake: 9 * 60)
        #expect(late.chartWindow(containing: date(2026, 11, 18, 22, 0)).start == date(2026, 11, 18, 5, 0))
        #expect(late.chartWindow(containing: date(2026, 11, 19, 2, 0)).start == date(2026, 11, 18, 5, 0))
    }

    @Test func chartWindowHoldsEachEventOnceInOrder() {
        let plan = schedule(bedtime: 21 * 60, wake: 9 * 60)
        let window = plan.chartWindow(containing: date(2026, 11, 18, 19, 0))
        let timeline = plan.timeline(around: window.start + window.duration / 2)
        let events = timeline.events(in: window)
        #expect(events.map(\.kind) == [.sunrise, .wake, .sunset, .bedtime])
        #expect(events[1].date == date(2026, 11, 18, 9, 0))
        #expect(events[3].date == date(2026, 11, 18, 21, 0))
        // Both edges of the window are deep in the night.
        #expect(abs(timeline.kelvin(at: window.start) - 2700) < 1)
        #expect(abs(timeline.kelvin(at: window.end) - 2700) < 1)
    }

    @Test func worksWithoutALocation() {
        var plan = schedule()
        plan.coordinate = nil
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 12, 0)) - 6500) < 1)
        #expect(abs(plan.kelvin(at: date(2026, 11, 18, 20, 0)) - 3400) < 1)
    }
}
