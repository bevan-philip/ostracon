import OstraconCore
import SwiftUI

/// Actions shared by a task's context menu and its "more" button.
/// On a task that is part of a multiple selection, they act on every selected task.
struct TaskMenuItems: View {
    @Environment(AppModel.self) private var model

    let task: TaskItem

    var body: some View {
        let taskIDs = model.taskIDs(actingOn: task.id)
        let isMultiple = taskIDs.count > 1

        if isMultiple {
            Button("Complete \(taskIDs.count) Tasks") { model.toggleCompleted(task.id) }
        } else {
            Button(task.isCompleted ? "Mark as Not Done" : "Complete") { model.toggleCompleted(task.id) }
            Button("Edit") { model.startEditing(task.id) }
            Button("Add Subtask") { model.startAddingSubtask(to: task.id) }
        }

        Menu("Due Date") {
            ForEach(DueDateShortcut.allCases) { shortcut in
                Button(shortcut.title, systemImage: shortcut.systemImage) {
                    model.setDueDate(task.id, shortcut.dueDate())
                }
            }
            Divider()
            Button("Remove Due Date") { model.setDueDate(task.id, nil) }
                .disabled(!isMultiple && task.dueDate == nil)
        }

        Divider()

        if !isMultiple {
            Button("Indent") { model.indent(task.id) }
            Button("Outdent") { model.outdent(task.id) }
                .disabled(task.parentID == nil)
            Button("Move Up") { model.move(task.id, by: -1) }
            Button("Move Down") { model.move(task.id, by: 1) }
        }

        Menu("Move to Project") {
            ForEach(model.projects) { project in
                Button(project.name) { model.move(taskIDs, toProject: project) }
                    .disabled(project.id == task.projectID)
            }
        }

        Divider()

        Button(isMultiple ? "Delete \(taskIDs.count) Tasks…" : "Delete…", role: .destructive) {
            model.requestDeletion(task.id)
        }
    }
}
