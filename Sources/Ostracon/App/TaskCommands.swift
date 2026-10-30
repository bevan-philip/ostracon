import OstraconCore
import SwiftUI

/// Menu bar commands. Shortcuts here use ⌘ so they never clash with typing;
/// single-key shortcuts live on the task list itself.
struct TaskCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task", action: model.startAddingTask)
                .keyboardShortcut("n")
                .disabled(model.selectedProject == nil)
            Button("New Subtask") { model.startAddingSubtask() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!canActOnSingleTask)
            Button("New Project…", action: model.startCreatingProject)
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Task") {
            Button("Complete") { model.toggleCompleted() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canActOnSelection)
            Button("Edit") { model.startEditing() }
                .keyboardShortcut("e")
                .disabled(!canActOnSingleTask)

            Divider()

            Button("Indent") { model.indent() }
                .keyboardShortcut("]")
                .disabled(!canActOnSingleTask)
            Button("Outdent") { model.outdent() }
                .keyboardShortcut("[")
                .disabled(!canActOnSingleTask)
            Button("Move Up") { model.move(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!canActOnSingleTask)
            Button("Move Down") { model.move(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!canActOnSingleTask)

            Divider()

            Button("Delete…") { model.requestDeletion() }
                .disabled(!canActOnSelection)

            Divider()

            Toggle("Show Completed Tasks", isOn: $model.showCompleted)
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandMenu("Go") {
            ForEach(Array(model.projects.prefix(9).enumerated()), id: \.element.id) { index, project in
                Button(project.name) { model.selectProject(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
        }
    }

    /// Task actions apply to the selected tasks, and are off while the composer has the keyboard.
    private var canActOnSelection: Bool {
        model.selectedTaskID != nil && model.composer == nil
    }

    /// Editing and outlining need exactly one task selected.
    private var canActOnSingleTask: Bool {
        canActOnSelection && !model.hasMultipleSelection
    }
}
