import Foundation
import OstraconCore
import Testing

struct DateParserTests {
    let calendar: Calendar
    let now: Date
    let parser: DateParser

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        self.calendar = calendar
        // Friday 30 October 2026, 10:00.
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10)))
        parser = DateParser(now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    private func parse(_ text: String) -> QuickAddResult {
        QuickAddParser.parse(text, projects: [], dates: parser)
    }

    private func due(_ text: String) -> DueDate? {
        parse(text).dueDate
    }

    private func day(_ month: Int, _ day: Int, _ year: Int = 2026, at hour: Int? = nil, _ minute: Int = 0) -> DueDate {
        DueDate(year: year, month: month, day: day, time: hour.map { TimeOfDay(hour: $0, minute: minute) })
    }

    private func moment(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func relativeDays() {
        #expect(due("Call today") == day(10, 30))
        #expect(due("Call tomorrow") == day(10, 31))
        #expect(due("Call tmrw") == day(10, 31))
        #expect(due("Call tonight") == day(10, 30, at: 19))
        #expect(due("in 3 days") == day(11, 2))
        #expect(due("in a week") == day(11, 6))
        #expect(due("in 2 months") == day(12, 30))
        #expect(due("in 2 hours") == day(10, 30, at: 12))
        #expect(due("in 90 min") == day(10, 30, at: 11, 30))
        #expect(due("in 3d") == day(11, 2))
    }

    @Test func weekdaysAndWeeks() {
        #expect(due("monday") == day(11, 2))
        #expect(due("friday") == day(11, 6), "A weekday means the next one, not today")
        #expect(due("this friday") == day(10, 30))
        #expect(due("next friday") == day(11, 6))
        #expect(due("next tue") == day(11, 3))
        #expect(due("next week") == day(11, 2))
        #expect(due("weekend") == day(10, 31))
        #expect(due("next weekend") == day(11, 7))
        #expect(due("next month") == day(11, 1))
        #expect(due("end of month") == day(10, 31))
    }

    @Test func calendarDates() {
        #expect(due("jan 27") == day(1, 27, 2027), "Past dates without a year roll into next year")
        #expect(due("Dec 3rd") == day(12, 3))
        #expect(due("27th january 2028") == day(1, 27, 2028))
        #expect(due("on 5 nov") == day(11, 5))
        #expect(due("3/11") == day(11, 3), "en_GB reads day first")
        #expect(due("11/30") == day(11, 30), "A second number over 12 must be the day")
        #expect(due("2027-02-14") == day(2, 14, 2027))
        #expect(due("feb 30") == nil)
    }

    @Test func monthFirstLocale() {
        let american = DateParser(now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(QuickAddParser.parse("3/11", projects: [], dates: american).dueDate == day(3, 11, 2027))
    }

    @Test func times() {
        #expect(due("tomorrow at 5pm") == day(10, 31, at: 17))
        #expect(due("friday 9:30am") == day(11, 6, at: 9, 30))
        #expect(due("5 pm tomorrow") == day(10, 31, at: 17))
        #expect(due("at 17:45 on monday") == day(11, 2, at: 17, 45))
        #expect(due("at 3pm") == day(10, 30, at: 15), "A time later today stays today")
        #expect(due("at 8am") == day(10, 31, at: 8), "A time already gone today means tomorrow")
        #expect(due("noon") == day(10, 30, at: 12))
        #expect(due("12am tomorrow") == day(10, 31, at: 0))
        #expect(due("at 17") == day(10, 30, at: 17))
    }

    @Test func contentLosesTheDate() {
        let result = parse("Call mum tomorrow at 5pm about the party")
        #expect(result.content == "Call mum about the party")
        #expect(result.dueText == "tomorrow at 5pm")
    }

    @Test func separatedDateAndTimeCombine() {
        let result = parse("5pm call mum tomorrow")
        #expect(result.dueDate == day(10, 31, at: 17))
        #expect(result.content == "call mum")
    }

    @Test func lastDateWins() {
        let result = parse("Move monday meeting to friday")
        #expect(result.dueDate == day(11, 6))
        #expect(result.content == "Move monday meeting to")
    }

    @Test func ordinaryWordsAndNumbersAreLeftAlone() {
        for text in ["Buy 2 apples", "Call Tom", "Read today's paper", "Sit in the sun", "Meet at the cafe",
                     "in a meeting", "Sat down", "Version 1.2"] {
            let result = parse(text)
            #expect(result.dueDate == nil, "\(text)")
            #expect(result.content == text)
        }
    }

    @Test func relativeReminders() {
        let result = parse("Dentist friday 3pm !30min !1 hour before")
        #expect(result.content == "Dentist")
        #expect(result.dueDate == day(11, 6, at: 15))
        #expect(result.reminders == [.before(minutes: 30), .before(minutes: 60)])
    }

    @Test func absoluteReminders() {
        #expect(parse("Dentist friday 3pm !9am").reminders == [.at(moment(11, 6, 9))], "A bare time is on the due day")
        #expect(parse("Pay rent !tomorrow 8am").reminders == [.at(moment(10, 31, 8))])
        #expect(parse("Pay rent !tomorrow").reminders == [.at(moment(10, 31, 9))], "A bare day is reminded at 9am")
        #expect(parse("Pay rent !2pm").reminders == [.at(moment(10, 30, 14))])
        let result = parse("Pay rent !tomorrow 8am")
        #expect(result.dueDate == nil, "A reminder's date isn't the due date")
        #expect(result.content == "Pay rent")
    }

    @Test func unrecognisedBangsStay() {
        let result = parse("Wow! !important")
        #expect(result.content == "Wow! !important")
        #expect(result.reminders.isEmpty)
    }

    @Test func wholeTextParsing() {
        #expect(parser.dueDate(from: "next mon 9am") == day(11, 2, at: 9))
        #expect(parser.dueDate(from: "next mon and more") == nil)
        #expect(parser.reminder(from: "15 min before", due: nil) == .before(minutes: 15))
        #expect(parser.reminder(from: "!1d", due: nil) == .before(minutes: 1440))
        #expect(parser.reminder(from: "8am", due: day(11, 6)) == .at(moment(11, 6, 8)))
        #expect(parser.reminder(from: "whenever", due: nil) == nil)
    }

    @Test func projectsAndDatesTogether() {
        let projects = [Project(id: 2, name: "Work Monday", color: .red, sortOrder: 0, isInbox: false)]
        let result = QuickAddParser.parse("Report #Work Monday tomorrow", projects: projects, dates: parser)
        #expect(result.projectID == 2)
        #expect(result.dueDate == day(10, 31), "A project's name isn't read as a date")
        #expect(result.content == "Report")

        let ignored = QuickAddParser.parse("Read Today magazine", projects: [], dates: nil)
        #expect(ignored == QuickAddResult(content: "Read Today magazine", projectID: nil))
    }
}
