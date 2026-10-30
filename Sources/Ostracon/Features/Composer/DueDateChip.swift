import OstraconCore
import SwiftUI

/// The date chip in the composer's footer, opening the date picker.
struct DueDateChip: View {
    let dueDate: DueDate?
    /// The words in the task name that set the date, when it came from there.
    let typedText: String?
    let onPick: (DueDate?) -> Void
    let onKeepAsText: () -> Void

    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            ComposerChipLabel(isHighlighted: typedText != nil) {
                Label {
                    Text(dueDate.map { DueDateFormatter.string(for: $0) } ?? String(localized: "Date"))
                } icon: {
                    Image(systemName: "calendar")
                }
                .foregroundStyle(dueDate.map { Theme.style(for: DueUrgency($0)) } ?? AnyShapeStyle(.secondary))
            }
        }
        .buttonStyle(.plain)
        .help("Due date — or type one in the task name, like “tomorrow 5pm”")
        .accessibilityLabel(dueDate.map { "Due \(DueDateFormatter.string(for: $0))" } ?? "Due date: none")
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            DueDatePicker(dueDate: dueDate, typedText: typedText, onPick: onPick) {
                onKeepAsText()
                isShowingPicker = false
            }
        }
    }
}

/// The capsule shared by the composer's footer chips.
struct ComposerChipLabel<Content: View>: View {
    /// Tinted when the value came from the task name.
    let isHighlighted: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isHighlighted ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.fill.tertiary),
            in: .capsule
        )
        .contentShape(.capsule)
    }
}
