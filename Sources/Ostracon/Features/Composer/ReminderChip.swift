import OstraconCore
import SwiftUI

/// The reminders chip in the composer's footer, opening the reminder editor.
struct ReminderChip: View {
    /// Reminders set in the editor, which it can change.
    let reminders: [Reminder]
    /// Reminders typed in the task name with `!`.
    let typedReminders: [Reminder]
    let dueDate: DueDate?
    let isBlocked: Bool
    let onChange: ([Reminder]) -> Void

    @State private var isShowingEditor = false

    var body: some View {
        let count = reminders.count + typedReminders.count
        Button {
            isShowingEditor.toggle()
        } label: {
            ComposerChipLabel(isHighlighted: !typedReminders.isEmpty) {
                Image(systemName: count == 0 ? "bell" : "bell.fill")
                    .foregroundStyle(.secondary)
                if count > 0 {
                    Text(count, format: .number)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Reminders — or type one in the task name, like “!30min” or “!tomorrow 9am”")
        .accessibilityLabel(count == 1 ? "1 reminder" : "\(count) reminders")
        .popover(isPresented: $isShowingEditor, arrowEdge: .bottom) {
            ReminderEditor(
                reminders: reminders, typedReminders: typedReminders, dueDate: dueDate,
                isBlocked: isBlocked, onChange: onChange
            )
        }
    }
}

/// Lists a task's reminders and adds new ones, typed or from presets.
struct ReminderEditor: View {
    private static let presets = [0, 10, 30, 60, 1440]

    let reminders: [Reminder]
    let typedReminders: [Reminder]
    let dueDate: DueDate?
    let isBlocked: Bool
    let onChange: ([Reminder]) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reminders")
                .font(.headline)

            if isBlocked {
                Label("Notifications are turned off for Ostracon in System Settings.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if reminders.isEmpty && typedReminders.isEmpty {
                Text(dueDate?.hasTime == true ? "You’ll be notified at the due time." : "No reminders yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reminders, id: \.self) { reminder in
                        row(for: reminder) {
                            Button("Remove", systemImage: "xmark.circle.fill") {
                                onChange(reminders.filter { $0 != reminder })
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(typedReminders, id: \.self) { reminder in
                        row(for: reminder) {
                            Text("in task name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if dueDate?.hasTime == true {
                    Text("You’ll also be notified at the due time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                TextField("Add a reminder", text: $query, prompt: Text("e.g. 30 min before, tomorrow 9am"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTyped)
                if let typed = typedReminder {
                    Text("↩ \(DueDateFormatter.string(for: typed))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Menu("Before Due Time") {
                ForEach(Self.presets, id: \.self) { minutes in
                    Button(DueDateFormatter.string(for: .before(minutes: minutes))) {
                        add(.before(minutes: minutes))
                    }
                }
            }
            .disabled(dueDate?.hasTime != true)
            .help(dueDate?.hasTime == true ? "" : "Give the task a due time first")
            .fixedSize()
        }
        .padding(12)
        .frame(width: 280)
    }

    private func row(for reminder: Reminder, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 0) {
                    Text(DueDateFormatter.string(for: reminder))
                    if case .before = reminder, dueDate?.hasTime != true {
                        Text("Needs a due time")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } icon: {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }

    private var typedReminder: Reminder? {
        DateParser().reminder(from: query, due: dueDate)
    }

    private func addTyped() {
        guard let typed = typedReminder else { return }
        add(typed)
        query = ""
    }

    private func add(_ reminder: Reminder) {
        guard !reminders.contains(reminder) else { return }
        onChange(Reminder.sorted(reminders + [reminder]))
    }
}
