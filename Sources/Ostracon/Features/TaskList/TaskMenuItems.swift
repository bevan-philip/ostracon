import OstraconCore
import SwiftUI

/// Actions shared by a task's context menu and its "more" button.
struct TaskMenuItems: View {
    @Environment(AppModel.self) private var model

    let task: TaskItem

    var body: some View {
        Button(task.isCompleted ? "Mark as Not Done" : "Complete") { model.toggleCompleted(task.id) }
        Button("Edit") { model.startEditing(task.id) }
        Button("Add Subtask") { model.startAddingSubtask(to: task.id) }

        Menu("Due Date") {
            ForEach(DueDateShortcut.allCases) { shortcut in
                Button(shortcut.title, systemImage: shortcut.systemImage) {
                    model.setDueDate(task.id, shortcut.dueDate())
                }
            }
            Divider()
            Button("Remove Due Date") { model.setDueDate(task.id, nil) }
                .disabled(task.dueDate == nil)
        }

        Divider()

        Button("Indent") { model.indent(task.id) }
        Button("Outdent") { model.outdent(task.id) }
            .disabled(task.parentID == nil)
        Button("Move Up") { model.move(task.id, by: -1) }
        Button("Move Down") { model.move(task.id, by: 1) }

        Menu("Move to Project") {
            ForEach(model.projects) { project in
                Button(project.name) { model.move(task.id, toProject: project) }
                    .disabled(project.id == task.projectID)
            }
        }

        Divider()

        Button("Delete…", role: .destructive) { model.requestDeletion(task.id) }
    }
}
