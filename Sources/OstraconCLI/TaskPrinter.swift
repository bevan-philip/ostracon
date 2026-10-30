import Foundation
import OstraconCore
import OstraconToolKit

/// Renders the tools' JSON as text for a terminal.
struct TaskPrinter {
    var now: Date
    var calendar = Calendar.current

    func projects(_ output: JSONValue) -> String {
        let projects = output["projects"]?.arrayValue ?? []
        let idWidth = projects.map { text($0["id"]).count }.max() ?? 0
        let nameWidth = projects.map { text($0["name"]).count }.max() ?? 0
        return projects.map { project in
            pad(text(project["id"]), idWidth, leading: true) + "  " + pad(text(project["name"]), nameWidth)
                + "  \(text(project["open_tasks"])) open"
        }.joined(separator: "\n")
    }

    /// "5 Garden (limeGreen)", for a project the tools just changed.
    func project(_ output: JSONValue) -> String {
        "\(text(output["id"])) \(text(output["name"])) (\(text(output["color"])))"
    }

    /// A task list in outline order, under a heading for each project when it spans several.
    func tasks(_ output: JSONValue, showingProjects: Bool) -> String {
        let tasks = output["tasks"]?.arrayValue ?? []
        guard !tasks.isEmpty else { return "No tasks." }
        let idWidth = tasks.map { text($0["id"]).count }.max() ?? 0
        var lines: [String] = []
        var currentProject: JSONValue?
        for task in tasks {
            if showingProjects, task["project_id"] != currentProject {
                if !lines.isEmpty { lines.append("") }
                lines.append(text(task["project"]))
                currentProject = task["project_id"]
            }
            lines.append(line(task, idWidth: idWidth, depth: Int(task["depth"]?.int64Value ?? 0)))
        }
        return lines.joined(separator: "\n")
    }

    /// One task on one line: "12  [ ] Pay rent  due tomorrow 09:00 · 1/3 subtasks".
    func line(_ task: JSONValue, idWidth: Int = 0, depth: Int = 0, showingProject: Bool = false) -> String {
        var notes: [String] = []
        if let due = task["due"]?.stringValue {
            notes.append("due " + dueText(due) + (task["overdue"] == true ? ", overdue" : ""))
        }
        if showingProject { notes.append("#" + text(task["project"])) }
        if let count = task["subtask_count"]?.int64Value {
            notes.append("\(task["completed_subtask_count"]?.int64Value ?? 0)/\(count) subtasks")
        }
        return pad(text(task["id"]), idWidth, leading: true) + "  " + String(repeating: "  ", count: depth)
            + checkbox(task) + " " + text(task["content"])
            + (notes.isEmpty ? "" : "  " + notes.joined(separator: " · "))
    }

    /// Everything about a task, for `show`.
    func detail(_ task: JSONValue) -> String {
        var facts = ["ID \(text(task["id"]))", "#" + text(task["project"])]
        if let due = task["due"]?.stringValue {
            facts.append("due " + dueText(due) + (task["overdue"] == true ? ", overdue" : ""))
        }
        if let completedAt = task["completed_at"]?.stringValue.flatMap(parseTimestamp) {
            facts.append("completed " + momentText(completedAt))
        }
        var lines = [checkbox(task) + " " + text(task["content"]), facts.joined(separator: " · ")]

        let reminders = task["reminders"]?.arrayValue ?? []
        if !reminders.isEmpty { lines.append("Reminders: " + reminders.map(reminderText).joined(separator: ", ")) }
        if let details = task["details"]?.stringValue { lines += ["", details] }

        var subtasks: [(task: JSONValue, depth: Int)] = []
        func collect(_ children: [JSONValue], depth: Int) {
            for child in children {
                subtasks.append((child, depth))
                collect(child["subtasks"]?.arrayValue ?? [], depth: depth + 1)
            }
        }
        collect(task["subtasks"]?.arrayValue ?? [], depth: 0)
        if !subtasks.isEmpty {
            let idWidth = subtasks.map { text($0.task["id"]).count }.max() ?? 0
            lines += ["", "Subtasks:"] + subtasks.map { "  " + line($0.task, idWidth: idWidth, depth: $0.depth) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private func checkbox(_ task: JSONValue) -> String {
        task["completed"] == true ? "[x]" : "[ ]"
    }

    /// "today", "tomorrow 17:00", "Wednesday", "Sat 7 Nov", "Mon 4 Jan 2027", in the user's locale.
    func dueText(_ storageValue: String) -> String {
        guard let due = DueDate(storageValue: storageValue) else { return storageValue }
        let day = dayText(due.startOfDay(in: calendar))
        guard due.hasTime else { return day }
        return day + " " + due.date(in: calendar).formatted(date: .omitted, time: .shortened)
    }

    private func momentText(_ date: Date) -> String {
        dayText(date) + " " + date.formatted(date: .omitted, time: .shortened)
    }

    private func dayText(_ date: Date) -> String {
        let days = DueDate(day: date, calendar: calendar).daysFrom(now, calendar: calendar)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6: return date.formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            return date.formatted(sameYear ? style : style.year())
        }
    }

    private func reminderText(_ reminder: JSONValue) -> String {
        if let minutes = reminder["minutes_before_due"]?.int64Value {
            let (amount, unit) = minutes % 1440 == 0 && minutes > 0 ? (minutes / 1440, "day")
                : minutes % 60 == 0 && minutes > 0 ? (minutes / 60, "hour")
                : (minutes, "min")
            return "\(amount) \(unit)\(amount == 1 || unit == "min" ? "" : "s") before"
        }
        if let at = reminder["at"]?.stringValue.flatMap(parseTimestamp) { return momentText(at) }
        return reminder.prettyString()
    }

    private func parseTimestamp(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private func text(_ value: JSONValue?) -> String {
        switch value {
        case .string(let string): string
        case .number: value?.int64Value.map(String.init) ?? value?.prettyString() ?? ""
        case .none, .null: ""
        case .some(let other): other.prettyString()
        }
    }

    private func pad(_ text: String, _ width: Int, leading: Bool = false) -> String {
        let padding = String(repeating: " ", count: max(0, width - text.count))
        return leading ? padding + text : text + padding
    }
}
