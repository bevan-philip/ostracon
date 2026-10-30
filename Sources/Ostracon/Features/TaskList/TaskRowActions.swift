import OstraconCore
import SwiftUI

/// The edit, add-subtask and "more" buttons shown on a hovered or selected task.
struct TaskRowActions: View {
    @Environment(AppModel.self) private var model

    let task: TaskItem

    var body: some View {
        HStack(spacing: 2) {
            Button("Edit", systemImage: "pencil", action: edit)
                .help("Edit (Return)")
            Button("Add Subtask", systemImage: "plus", action: addSubtask)
                .help("Add subtask (Shift-A)")
            Menu("More", systemImage: "ellipsis.circle") {
                TaskMenuItems(task: task)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            // Menus otherwise take the project's tint; keep it grey like the buttons beside it.
            .tint(.secondary)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func edit() {
        model.startEditing(task.id)
    }

    private func addSubtask() {
        model.startAddingSubtask(to: task.id)
    }
}
