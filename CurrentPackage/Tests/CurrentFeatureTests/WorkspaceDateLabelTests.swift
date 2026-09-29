import Foundation
import Testing
@testable import CurrentFeature

@Suite
struct WorkspaceDateLabelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func currentYearUsesCompactWeekdayAndOlderYearsRemainUnambiguous() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let previousYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 9, day: 28)))
        let locale = Locale(identifier: "en_US")
        #expect(WorkspaceDateLabel.title(for: today, relativeTo: today, calendar: calendar, locale: locale) == "Mon, Sep 28")
        #expect(WorkspaceDateLabel.title(for: previousYear, relativeTo: today, calendar: calendar, locale: locale) == "Sep 28, 2025")
    }

    @Test func dateOrderAndMonthNamesFollowLocale() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let french = WorkspaceDateLabel.title(for: today, relativeTo: today, calendar: calendar,
                                             locale: Locale(identifier: "fr_FR"))
        #expect(french.contains("lun."))
        #expect(french.contains("28 sept."))
        #expect(!french.contains("Sep"))
    }

    @Test func yearBoundaryUsesTheDisplayCalendarTimeZone() throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let reference = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 9)))
        let date = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 1)))
        #expect(WorkspaceDateLabel.title(for: date, relativeTo: reference, calendar: local,
                                        locale: Locale(identifier: "en_US")) == "Dec 31, 2026")
    }
}
