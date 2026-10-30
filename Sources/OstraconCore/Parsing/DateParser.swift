import Foundation

/// Recognises Todoist-style natural-language dates in task text.
///
/// Due dates: `today`, `tomorrow`, `tonight`, `friday`, `next friday`, `next week`, `weekend`, `next month`,
/// `in 3 days`, `in 2 hours`, `end of month`, `jan 27`, `27th january 2027`, `27/1`, `2027-01-27`,
/// each optionally with a time such as `at 5pm`, `17:30`, `9:15am` or `noon`. A time on its own means the
/// next time the clock reads it.
///
/// Reminders start with `!`: `!30min` or `!1 hour before` (relative to the due time),
/// or `!tomorrow 9am`, `!3pm` (a fixed moment; a bare time falls on the due day).
public struct DateParser: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// Decides whether `3/4` means 3 April or March 4.
    public var locale: Locale

    public init(now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    /// A date or reminder phrase found in a piece of text.
    public struct Phrase: Hashable, Sendable {
        public enum Value: Hashable, Sendable {
            case due(DateFragment)
            case reminder(ReminderFragment)
        }

        public var range: Range<String.Index>
        public var value: Value
    }

    /// Every date and `!reminder` phrase in `text`, left to right, taking the longest phrase at each position.
    public func phrases(in text: String) -> [Phrase] {
        let tokens = Self.tokenize(text)
        var phrases: [Phrase] = []
        var index = 0
        while index < tokens.count {
            func range(_ length: Int) -> Range<String.Index> {
                tokens[index].range.lowerBound..<tokens[index + length - 1].range.upperBound
            }
            if tokens[index].isReminder, let found = reminder(in: tokens, at: index) {
                phrases.append(Phrase(range: range(found.length), value: .reminder(found.value)))
                index += found.length
            } else if let found = phrase(in: tokens, at: index) {
                phrases.append(Phrase(range: range(found.length), value: .due(found.value)))
                index += found.length
            } else {
                index += 1
            }
        }
        return phrases
    }

    /// Reads the whole of `text` as a date. `nil` unless all of it is understood.
    public func dateFragment(from text: String) -> DateFragment? {
        let tokens = Self.tokenize(text)
        guard !tokens.isEmpty, let found = phrase(in: tokens, at: 0), found.length == tokens.count else { return nil }
        return found.value
    }

    /// Reads the whole of `text` as a reminder, with or without its leading `!`.
    public func reminderFragment(from text: String) -> ReminderFragment? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let tokens = Self.tokenize(trimmed.hasPrefix("!") ? trimmed : "!" + trimmed)
        guard !tokens.isEmpty, let found = reminder(in: tokens, at: 0), found.length == tokens.count else { return nil }
        return found.value
    }

    /// Reads the whole of `text` as a due date, for a "type a date" field.
    public func dueDate(from text: String) -> DueDate? {
        dateFragment(from: text).map(resolve)
    }

    /// Reads the whole of `text` as a reminder for a task due at `due`.
    public func reminder(from text: String, due: DueDate?) -> Reminder? {
        reminderFragment(from: text).map { resolve($0, due: due) }
    }

    // MARK: - Resolution

    /// Something recognised, spanning `length` tokens.
    struct Match<Value> {
        var length: Int
        var value: Value

        init(_ length: Int, _ value: Value) {
            self.length = length
            self.value = value
        }
    }

    private var today: Date { calendar.startOfDay(for: now) }

    /// A bare time means today, or tomorrow if that time has already gone.
    public func resolve(_ fragment: DateFragment) -> DueDate {
        if let day = fragment.day {
            return DueDate(day: day, time: fragment.time, calendar: calendar)
        }
        let time = fragment.time ?? .morning
        var candidate = DueDate(day: today, time: time, calendar: calendar)
        if candidate.date(in: calendar) <= now {
            candidate = DueDate(day: adding(days: 1, to: today), time: time, calendar: calendar)
        }
        return candidate
    }

    /// A bare reminder time falls on the due day if there is one; a bare day is reminded at 9am.
    public func resolve(_ fragment: ReminderFragment, due: DueDate?) -> Reminder {
        switch fragment {
        case .before(let minutes):
            return .before(minutes: minutes)
        case .at(let date):
            let time = date.time ?? .morning
            if date.day == nil, let due {
                return .at(due.withTime(time).date(in: calendar))
            }
            return .at(resolve(DateFragment(day: date.day, time: time)).date(in: calendar))
        }
    }

    // MARK: - Grammar

    /// `date [time]`, `time [on] [date]`, or `on date [time]`.
    private func phrase(in tokens: [Token], at index: Int) -> Match<DateFragment>? {
        guard index < tokens.count, !tokens[index].isReminder else { return nil }
        if tokens[index].word == "on", let found = phrase(in: tokens, at: index + 1), found.value.day != nil {
            return Match(found.length + 1, found.value)
        }
        if let date = date(in: tokens, at: index) {
            if date.value.time == nil, let time = time(in: tokens, at: index + date.length) {
                return Match(date.length + time.length, DateFragment(day: date.value.day, time: time.value))
            }
            return date
        }
        if let time = time(in: tokens, at: index) {
            var next = index + time.length
            if next < tokens.count, tokens[next].word == "on" { next += 1 }
            if let date = date(in: tokens, at: next), date.value.time == nil {
                return Match(next - index + date.length, DateFragment(day: date.value.day, time: time.value))
            }
            return Match(time.length, DateFragment(day: nil, time: time.value))
        }
        return nil
    }

    private func date(in tokens: [Token], at index: Int) -> Match<DateFragment>? {
        func word(_ offset: Int) -> String? {
            tokens.indices.contains(index + offset) && !tokens[index + offset].isReminder ? tokens[index + offset].word : nil
        }
        func day(_ length: Int, _ date: Date?) -> Match<DateFragment>? { date.map { Match(length, DateFragment(day: $0)) } }
        guard let first = word(0) else { return nil }

        switch first {
        case "today": return day(1, today)
        case "tomorrow", "tmr", "tmrw": return day(1, adding(days: 1, to: today))
        case "tonight": return Match(1, DateFragment(day: today, time: TimeOfDay(hour: 19)))
        case "weekend": return day(1, thisWeekend)
        case "eom": return day(1, endOfMonth)
        default: break
        }

        if let weekday = Self.weekday(first) {
            return day(1, next(weekday: weekday, includingToday: false))
        }

        if first == "this", let second = word(1) {
            if second == "weekend" { return day(2, thisWeekend) }
            if let weekday = Self.weekday(second) { return day(2, next(weekday: weekday, includingToday: true)) }
        }

        if first == "next", let second = word(1) {
            let monday = next(weekday: 2, includingToday: false)
            switch second {
            case "week": return day(2, monday)
            case "weekend": return day(2, adding(days: 5, to: monday))
            case "month":
                let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
                return day(2, calendar.date(byAdding: .month, value: 1, to: start))
            default:
                if let weekday = Self.weekday(second) {
                    return day(2, adding(days: (weekday - 2 + 7) % 7, to: monday))
                }
            }
        }

        if first == "end", word(1) == "of", word(2) == "month" || word(2) == "the" && word(3) == "month" {
            return day(word(2) == "the" ? 4 : 3, endOfMonth)
        }

        if first == "in", let amountWord = word(1) {
            let amount = Int(amountWord) ?? (["a", "an", "one"].contains(amountWord) ? 1 : nil)
            if let amount, let unitWord = word(2), let unit = Self.durationUnit(unitWord) {
                return offset(amount, unit).map { Match(3, $0) }
            }
            if let (amount, unit) = Self.compactDuration(amountWord) {
                return offset(amount, unit).map { Match(2, $0) }
            }
        }

        // jan 27 [2027], 27th january [2027]
        if let month = Self.month(first), let second = word(1), let dayNumber = Self.dayNumber(second) {
            let year = word(2).flatMap(Self.year)
            return day(year == nil ? 2 : 3, calendarDate(year: year, month: month, day: dayNumber))
        }
        if let dayNumber = Self.dayNumber(first), let second = word(1), let month = Self.month(second) {
            let year = word(2).flatMap(Self.year)
            return day(year == nil ? 2 : 3, calendarDate(year: year, month: month, day: dayNumber))
        }

        return day(1, numericDate(first))
    }

    /// `5pm`, `5 pm`, `5:30pm`, `17:30`, `noon`, `midnight`; after `at` or `@`, a bare hour such as `at 17`.
    private func time(in tokens: [Token], at index: Int) -> Match<TimeOfDay>? {
        var position = index
        let hasMarker = tokens.indices.contains(position) && ["at", "@"].contains(tokens[position].word)
        if hasMarker { position += 1 }
        guard tokens.indices.contains(position), !tokens[position].isReminder else { return nil }
        let word = tokens[position].word
        let consumed = position - index + 1

        switch word {
        case "noon", "midday": return Match(consumed, TimeOfDay(hour: 12))
        case "midnight": return Match(consumed, TimeOfDay(hour: 0))
        default: break
        }

        guard let match = word.wholeMatch(of: /(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?/),
              let hour = Int(match.1)
        else { return nil }
        let minute = match.2.flatMap { Int($0) } ?? 0
        guard minute < 60 else { return nil }

        var meridiem = match.3.map(String.init)
        var length = consumed
        if meridiem == nil, tokens.indices.contains(position + 1), ["am", "pm"].contains(tokens[position + 1].word) {
            meridiem = tokens[position + 1].word
            length += 1
        }

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            let isPM = meridiem.hasPrefix("p")
            return Match(length, TimeOfDay(hour: hour % 12 + (isPM ? 12 : 0), minute: minute))
        }
        // Without am/pm, only clearly-a-time forms count, so "buy 2 apples" keeps its 2.
        guard match.2 != nil || hasMarker, (0...23).contains(hour) else { return nil }
        return Match(length, TimeOfDay(hour: hour, minute: minute))
    }

    /// `!30min [before]`, `!1 hour before`, or `!` followed by a date and/or time.
    private func reminder(in tokens: [Token], at index: Int) -> Match<ReminderFragment>? {
        guard tokens[index].isReminder, !tokens[index].word.isEmpty else { return nil }
        var tokens = tokens
        tokens[index].isReminder = false

        func before(_ length: Int) -> Int {
            tokens.indices.contains(index + length) && tokens[index + length].word == "before" ? length + 1 : length
        }
        if let (amount, unit) = Self.compactDuration(tokens[index].word), let minutes = Self.minutes(amount, unit) {
            return Match(before(1), .before(minutes: minutes))
        }
        if let amount = Int(tokens[index].word), tokens.indices.contains(index + 1),
           let unit = Self.durationUnit(tokens[index + 1].word), let minutes = Self.minutes(amount, unit) {
            return Match(before(2), .before(minutes: minutes))
        }
        return phrase(in: tokens, at: index).map { Match($0.length, .at($0.value)) }
    }

    // MARK: - Calendar helpers

    private func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The next given weekday (1 = Sunday … 7 = Saturday).
    private func next(weekday: Int, includingToday: Bool) -> Date {
        let current = calendar.component(.weekday, from: today)
        var days = (weekday - current + 7) % 7
        if days == 0 && !includingToday { days = 7 }
        return adding(days: days, to: today)
    }

    /// Today if it's the weekend, otherwise the coming Saturday.
    private var thisWeekend: Date {
        calendar.component(.weekday, from: today) == 1 ? today : next(weekday: 7, includingToday: true)
    }

    private var endOfMonth: Date? {
        guard let month = calendar.dateInterval(of: .month, for: today) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: month.end)
    }

    private func offset(_ amount: Int, _ unit: Calendar.Component) -> DateFragment? {
        guard let date = calendar.date(byAdding: unit, value: amount, to: now) else { return nil }
        if unit == .hour || unit == .minute {
            let due = DueDate(dayAndTime: date, calendar: calendar)
            return DateFragment(day: date, time: due.time)
        }
        return DateFragment(day: calendar.startOfDay(for: date))
    }

    /// A valid date; without a year, the next time that day comes round.
    private func calendarDate(year: Int?, month: Int, day: Int) -> Date? {
        let thisYear = calendar.component(.year, from: today)
        func make(_ year: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day
            else { return nil }
            return date
        }
        if let year { return make(year) }
        if let date = make(thisYear), date >= today { return date }
        return make(thisYear + 1)
    }

    /// `2027-01-27`, or `27/1`, `27/1/27`, `27/01/2027` in the locale's day–month order.
    private func numericDate(_ word: String) -> Date? {
        if let match = word.wholeMatch(of: /(\d{4})-(\d{1,2})-(\d{1,2})/),
           let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) {
            return calendarDate(year: year, month: month, day: day)
        }
        guard let match = word.wholeMatch(of: /(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?/),
              let first = Int(match.1), let second = Int(match.2)
        else { return nil }
        let year = match.3.flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
        let dayFirst = first > 12 || (second <= 12 && localeIsDayFirst)
        return calendarDate(year: year, month: dayFirst ? second : first, day: dayFirst ? first : second)
    }

    private var localeIsDayFirst: Bool {
        let pattern = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale) ?? "d/M"
        guard let day = pattern.firstIndex(of: "d"), let month = pattern.firstIndex(of: "M") else { return true }
        return day < month
    }

    // MARK: - Words

    struct Token {
        /// Lowercased, without a leading `!` or trailing `,` or `.`.
        var word: String
        var range: Range<String.Index>
        /// Started with `!`.
        var isReminder: Bool
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            let end = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            var word = text[index..<end].lowercased()
            let isReminder = word.hasPrefix("!")
            if isReminder { word.removeFirst() }
            while let last = word.last, [",", "."].contains(last) { word.removeLast() }
            tokens.append(Token(word: word, range: index..<end, isReminder: isReminder))
            index = end
        }
        return tokens
    }

    /// Full names, plus abbreviations unlikely to be ordinary words ("sat" and "sun" are left out).
    private static func weekday(_ word: String) -> Int? {
        switch word {
        case "sunday": 1
        case "monday", "mon": 2
        case "tuesday", "tue", "tues": 3
        case "wednesday", "wed": 4
        case "thursday", "thu", "thur", "thurs": 5
        case "friday", "fri": 6
        case "saturday": 7
        default: nil
        }
    }

    private static func month(_ word: String) -> Int? {
        let names = ["january", "february", "march", "april", "may", "june", "july",
                     "august", "september", "october", "november", "december"]
        if let index = names.firstIndex(of: word) { return index + 1 }
        if word == "sept" { return 9 }
        guard word.count == 3 else { return nil }
        return names.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 }
    }

    /// `27`, `27th`, `1st`, `2nd`, `3rd`.
    private static func dayNumber(_ word: String) -> Int? {
        guard let match = word.wholeMatch(of: /(\d{1,2})(st|nd|rd|th)?/), let day = Int(match.1), (1...31).contains(day) else {
            return nil
        }
        return day
    }

    private static func year(_ word: String) -> Int? {
        word.wholeMatch(of: /\d{4}/).flatMap { Int($0.output) }
    }

    private static func durationUnit(_ word: String) -> Calendar.Component? {
        switch word {
        case "m", "min", "mins", "minute", "minutes": .minute
        case "h", "hr", "hrs", "hour", "hours": .hour
        case "d", "day", "days": .day
        case "w", "wk", "wks", "week", "weeks": .weekOfYear
        case "month", "months": .month
        case "y", "yr", "yrs", "year", "years": .year
        default: nil
        }
    }

    /// `30min`, `2h`, `3d`.
    private static func compactDuration(_ word: String) -> (Int, Calendar.Component)? {
        guard let match = word.wholeMatch(of: /(\d+)([a-z]+)/), let amount = Int(match.1),
              let unit = durationUnit(String(match.2))
        else { return nil }
        return (amount, unit)
    }

    /// Relative reminders are measured in minutes; months and years are too vague to count back from.
    private static func minutes(_ amount: Int, _ unit: Calendar.Component) -> Int? {
        switch unit {
        case .minute: amount
        case .hour: amount * 60
        case .day: amount * 60 * 24
        case .weekOfYear: amount * 60 * 24 * 7
        default: nil
        }
    }
}
