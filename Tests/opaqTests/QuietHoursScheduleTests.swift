import XCTest

@testable import opaq

final class QuietHoursScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = gregorian
    }

    func testDefaultScheduleWeekdayWindow() {
        let schedule = QuietHoursSchedule.defaultSchedule
        let wednesdayMorning = date(year: 2026, month: 10, day: 21, hour: 10, minute: 0)
        let wednesdayEvening = date(year: 2026, month: 10, day: 21, hour: 18, minute: 0)
        let saturdayMorning = date(year: 2026, month: 10, day: 24, hour: 10, minute: 0)

        XCTAssertEqual(calendar.component(.weekday, from: wednesdayMorning), 4)
        XCTAssertEqual(calendar.component(.weekday, from: saturdayMorning), 7)

        XCTAssertTrue(schedule.isCurrentlyActive(at: wednesdayMorning, calendar: calendar))
        XCTAssertFalse(schedule.isCurrentlyActive(at: wednesdayEvening, calendar: calendar))
        XCTAssertFalse(schedule.isCurrentlyActive(at: saturdayMorning, calendar: calendar))
    }

    func testDisabledScheduleIsInactive() {
        var schedule = QuietHoursSchedule.defaultSchedule
        schedule.isEnabled = false
        let wednesdayMorning = date(year: 2026, month: 10, day: 21, hour: 10, minute: 0)

        XCTAssertFalse(schedule.isCurrentlyActive(at: wednesdayMorning, calendar: calendar))
    }

    func testOvernightWindowOnActiveWeekday() {
        var schedule = QuietHoursSchedule.defaultSchedule
        schedule.startHour = 22
        schedule.startMinute = 0
        schedule.endHour = 7
        schedule.endMinute = 0

        let lateNight = date(year: 2026, month: 10, day: 21, hour: 23, minute: 0)
        let earlyMorning = date(year: 2026, month: 10, day: 21, hour: 6, minute: 30)
        let midday = date(year: 2026, month: 10, day: 21, hour: 12, minute: 0)

        XCTAssertEqual(calendar.component(.weekday, from: lateNight), 4)
        XCTAssertTrue(schedule.activeWeekdays.contains(4))
        XCTAssertTrue(schedule.isCurrentlyActive(at: lateNight, calendar: calendar))
        XCTAssertTrue(schedule.isCurrentlyActive(at: earlyMorning, calendar: calendar))
        XCTAssertFalse(schedule.isCurrentlyActive(at: midday, calendar: calendar))
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
