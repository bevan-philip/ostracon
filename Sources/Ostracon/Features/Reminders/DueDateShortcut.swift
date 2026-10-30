import Foundation
import OstraconCore

/// The one-click dates offered in the date picker and the task menu.
enum DueDateShortcut: CaseIterable, Identifiable {
    case today, tomorrow, weekend, nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .weekend: String(localized: "This Weekend")
        case .nextWeek: String(localized: "Next Week")
        }
    }

    var systemImage: String {
        switch self {
        case .today: "star"
        case .tomorrow: "sun.max"
        case .weekend: "sofa"
        case .nextWeek: "arrow.right.circle"
        }
    }

    /// Phrased as the user would type it, so the shortcut and the typed date can never disagree.
    private var phrase: String {
        switch self {
        case .today: "today"
        case .tomorrow: "tomorrow"
        case .weekend: "this weekend"
        case .nextWeek: "next week"
        }
    }

    func dueDate(now: Date = .now) -> DueDate? {
        DateParser(now: now).dueDate(from: phrase)
    }
}
