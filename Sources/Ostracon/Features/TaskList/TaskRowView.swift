import OstraconCore
import SwiftUI

struct TaskRowView: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false
    /// Shows the tick immediately while the completion animation plays.
    @State private var isCompleting = false

    let row: TaskRow
    let onSelect: () -> Void

    private var task: TaskItem { row.task }

    var body: some View {
        let isSelected = model.selectedTaskID == task.id

        HStack(alignment: .top, spacing: 6) {
            disclosureButton
            CompletionCircle(isCompleted: task.isCompleted || isCompleting, action: complete)
                .padding(.top, 1)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.content)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.callout)
                        .foregroundStyle(Theme.subtleText)
                        .lineLimit(2)
                }
                if row.task.isCollapsed && row.hasChildren {
                    Label("\(row.childCount)", systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleText)
                        .accessibilityLabel("\(row.childCount) hidden subtasks")
                }
            }

            actions
                .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(isSelected ? Theme.rowSelection : .clear, in: .rect(cornerRadius: 6))
        .overlay(alignment: .bottom) {
            Theme.separator.frame(height: 1)
        }
        .padding(.leading, Double(row.depth) * 30)
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.startEditing(task.id) })
        .onHover { isHovered = $0 }
        .contextMenu { TaskMenuItems(task: task) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if row.hasChildren {
            Button(task.isCollapsed ? "Expand" : "Collapse", systemImage: "chevron.right") {
                withAnimation(.snappy(duration: 0.2)) {
                    model.setCollapsed(task.id, !task.isCollapsed)
                }
            }
            .buttonStyle(IconButtonStyle(size: 20))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(task.isCollapsed ? 0 : 90))
            .opacity(isHovered || task.isCollapsed ? 1 : 0.35)
        } else {
            Color.clear.frame(width: 20, height: 20)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button("Edit", systemImage: "pencil") { model.startEditing(task.id) }
                .help("Edit (Return)")
            Button("Add Subtask", systemImage: "plus") { model.startAddingSubtask(to: task.id) }
                .help("Add subtask (Shift-A)")
            Menu {
                TaskMenuItems(task: task)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func complete() {
        guard !task.isCompleted else {
            model.toggleCompleted(task.id)
            return
        }
        isCompleting = true
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.2)) {
                model.toggleCompleted(task.id)
            }
            isCompleting = false
        }
    }
}
