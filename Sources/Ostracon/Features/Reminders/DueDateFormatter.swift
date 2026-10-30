import Foundation
import OstraconCore

/// Todoist-style wording for due dates and reminders: "Today", "Tomorrow 17:00", "Wednesday", "6 Nov".
enum DueDateFormatter {
    static func string(for due: DueDate, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = due.date(in: calendar)
        let days = due.daysFrom(now, calendar: calendar)
        let day: String
        switch days {
        case 0: day = String(localized: "Today")
        case 1: day = String(localized: "Tomorrow")
        case -1: day = String(localized: "Yesterday")
        case 2...6: day = date.formatted(.dateTime.weekday(.wide).locale(locale))
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let style = Date.FormatStyle(locale: locale, calendar: calendar).day().month(.abbreviated)
            day = date.formatted(sameYear ? style : style.year())
        }
        guard due.hasTime else { return day }
        return day + " " + date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).hour().minute())
    }

    static func string(for reminder: Reminder, now: Date = .now, calendar: Calendar = .current) -> String {
        switch reminder {
        case .at(let date):
            string(for: DueDate(dayAndTime: date, calendar: calendar), now: now, calendar: calendar)
        case .before(let minutes):
            beforeString(minutes)
        }
    }

    private static func beforeString(_ minutes: Int) -> String {
        if minutes == 0 {
            return String(localized: "At due time")
        }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? String(localized: "1 day before") : String(localized: "\(days) days before")
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? String(localized: "1 hour before") : String(localized: "\(hours) hours before")
        }
        return String(localized: "\(minutes) min before")
    }
}

/// How urgent a due date looks, which picks its colour.
enum DueUrgency {
    case overdue, today, tomorrow, thisWeek, later

    init(_ due: DueDate, now: Date = .now, calendar: Calendar = .current) {
        let days = due.daysFrom(now, calendar: calendar)
        if due.isOverdue(at: now, calendar: calendar) {
            self = .overdue
        } else {
            switch days {
            case 0: self = .today
            case 1: self = .tomorrow
            case 2...6: self = .thisWeek
            default: self = .later
            }
        }
    }
}
