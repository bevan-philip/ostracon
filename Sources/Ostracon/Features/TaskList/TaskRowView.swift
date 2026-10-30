import OstraconCore
import SwiftUI

struct TaskRowView: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    /// Shows the tick immediately while the completion animation plays.
    @State private var isCompleting = false

    let row: TaskRow
    let isSelected: Bool
    let onSelect: (Int64) -> Void

    private var task: TaskItem { row.task }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.rowSpacing) {
            TaskDisclosureButton(row: row, isRowHovered: isHovered)
            CompletionCircle(isCompleted: task.isCompleted || isCompleting, action: complete)

            VStack(alignment: .leading, spacing: 2) {
                // Completed tasks drop a level of emphasis so they recede behind open ones.
                Text(task.content)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.callout)
                        .foregroundStyle(task.isCompleted ? .tertiary : .secondary)
                        .lineLimit(2)
                }
                if TaskDueLabel.hasContent(for: task) || SubtaskSummary.hasContent(for: row) {
                    HStack(spacing: 12) {
                        if TaskDueLabel.hasContent(for: task) {
                            TaskDueLabel(task: task)
                        }
                        if SubtaskSummary.hasContent(for: row) {
                            SubtaskSummary(row: row, isShowingCompleted: model.showCompleted)
                        }
                    }
                }
            }

            TaskRowActions(task: task)
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(Theme.rowPadding)
        .padding(.leading, Double(row.depth) * Theme.indentWidth)
        // Inset within the card, spanning its full width even for subtasks.
        .background {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                .fill(highlight)
                .padding(Theme.cardInset)
        }
        .contentShape(.rect)
        // A gesture rather than a Button: rows need both single-click to select and double-click to edit.
        .onTapGesture(perform: select)
        .simultaneousGesture(TapGesture(count: 2).onEnded(edit))
        .onHover { isHovered = $0 }
        .contextMenu { TaskMenuItems(task: task) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Without these, activating the combined row would press its first child: the checkbox.
        .accessibilityAction(.default, select)
        .accessibilityAction(named: task.isCompleted ? Text("Mark as Not Done") : Text("Complete Task"), complete)
        .accessibilityAction(named: "Edit", edit)
    }

    private var highlight: AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(.tint.quaternary)
        } else if isHovered {
            AnyShapeStyle(.fill.quaternary)
        } else {
            AnyShapeStyle(.clear)
        }
    }

    private func select() {
        onSelect(task.id)
    }

    private func edit() {
        model.startEditing(task.id)
    }

    private func complete() {
        guard !task.isCompleted else {
            model.toggleCompleted(task.id)
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            isCompleting = true
        } completion: {
            withAnimation(.easeOut(duration: 0.2)) {
                model.toggleCompleted(task.id)
            }
            isCompleting = false
        }
    }
}
