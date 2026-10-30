import OstraconCore
import SwiftUI

/// The date popover: type a date, pick a shortcut, or choose a day and time from the calendar.
struct DueDatePicker: View {
    @Environment(\.dismiss) private var dismiss

    let dueDate: DueDate?
    let typedText: String?
    let onPick: (DueDate?) -> Void
    let onKeepAsText: () -> Void

    @State private var query = ""
    @State private var day: Date
    @State private var includesTime: Bool
    @State private var time: Date

    init(dueDate: DueDate?, typedText: String?, onPick: @escaping (DueDate?) -> Void, onKeepAsText: @escaping () -> Void) {
        self.dueDate = dueDate
        self.typedText = typedText
        self.onPick = onPick
        self.onKeepAsText = onKeepAsText
        let start = dueDate?.date() ?? .now
        _day = State(initialValue: Calendar.current.startOfDay(for: start))
        _includesTime = State(initialValue: dueDate?.hasTime ?? false)
        _time = State(initialValue: dueDate?.hasTime == true ? start : Self.nextHour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Type a date", text: $query, prompt: Text("Type a date, e.g. next fri 5pm"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(pickTyped)
                if let typed = typedDueDate {
                    Text("↩ \(DueDateFormatter.string(for: typed))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if !query.isEmpty {
                    Text("Not a date I recognise")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let typedText {
                Button("Keep “\(typedText)” as Text", systemImage: "textformat", action: onKeepAsText)
                    .buttonStyle(.link)
                    .font(.callout)
            }

            VStack(spacing: 0) {
                ForEach(DueDateShortcut.allCases) { shortcut in
                    if let date = shortcut.dueDate() {
                        Button {
                            pick(date.withTime(selectedTime))
                            dismiss()
                        } label: {
                            HStack {
                                Label(shortcut.title, systemImage: shortcut.systemImage)
                                Spacer()
                                Text(date.date().formatted(.dateTime.weekday(.abbreviated)))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if dueDate != nil {
                    Button {
                        pick(nil)
                        dismiss()
                    } label: {
                        Label("No Date", systemImage: "nosign")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            DatePicker("Day", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: day) { pickFromCalendar() }

            HStack {
                Toggle("Time", isOn: $includesTime)
                    .onChange(of: includesTime) { pickFromCalendar() }
                Spacer()
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!includesTime)
                    .onChange(of: time) { pickFromCalendar() }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var typedDueDate: DueDate? {
        DateParser().dueDate(from: query)
    }

    private var selectedTime: TimeOfDay? {
        guard includesTime else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private static var nextHour: Date {
        Calendar.current.dateInterval(of: .hour, for: .now)?.end ?? .now
    }

    private func pickTyped() {
        guard let typed = typedDueDate else { return }
        pick(typed)
        dismiss()
    }

    private func pickFromCalendar() {
        pick(DueDate(day: day, time: selectedTime))
    }

    private func pick(_ dueDate: DueDate?) {
        guard dueDate != self.dueDate else { return }
        onPick(dueDate)
    }
}
