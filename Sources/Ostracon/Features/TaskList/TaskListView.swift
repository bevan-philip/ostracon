import AppKit
import OstraconCore
import SwiftUI

struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isListFocused: Bool

    var body: some View {
        @Bindable var model = model
        let groups = model.cardGroups

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let project = model.selectedProject {
                        TaskListHeader(project: project, openCount: model.openCount(for: project))
                            .padding(.horizontal, Theme.rowPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                    }

                    LazyVStack(alignment: .leading, spacing: Theme.taskSpacing) {
                        ForEach(groups) { group in
                            TaskCard(group: group, selectedTaskIDs: model.selectedTaskIDs, onSelect: select)
                                .transition(.opacity)
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: groups)

                    if model.composer == nil {
                        AddTaskRow(action: model.startAddingTask)
                            .padding(.top, Theme.taskSpacing)
                    }

                    if model.composer == nil && groups.isEmpty {
                        ContentUnavailableView(
                            "All Clear",
                            systemImage: "checkmark.circle",
                            description: Text("Press A or ⌘N to add a task. Type #ProjectName to file it somewhere else.")
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical)
                .frame(maxWidth: Theme.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .tint(model.selectedProject.map(Theme.tint(for:)))
            .onChange(of: model.selectedTaskID) { _, taskID in
                guard let taskID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("task-\(taskID)")
                }
            }
        }
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onChange(of: model.composer) { _, composer in
            if composer == nil { isListFocused = true }
        }
        // Choosing a project in the sidebar hands the keyboard straight back to the task list.
        .onChange(of: model.selectedProjectID) {
            isListFocused = true
        }
        .onAppear { isListFocused = true }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .confirmationDialog(
            deletionTitle,
            isPresented: isConfirmingDeletion,
            presenting: model.tasksPendingDeletion
        ) { tasks in
            Button("Delete", role: .destructive) { model.confirmDeletion(tasks) }
        } message: { tasks in
            if let task = tasks.first, tasks.count == 1 {
                Text("“\(task.content)” and any subtasks will be permanently deleted.")
            } else {
                Text("These \(tasks.count) tasks and any subtasks will be permanently deleted.")
            }
        }
        .navigationTitle(model.selectedProject?.name ?? "Ostracon")
        .modifier(HeaderReplacesToolbarTitle())
        .toolbar {
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Show Completed", systemImage: "checkmark.circle", isOn: $model.showCompleted)
                    .help(model.showCompleted ? "Hide completed tasks (⇧⌘C)" : "Show completed tasks (⇧⌘C)")
                Button("New Task", systemImage: "plus", action: model.startAddingTask)
                    .help("Add a task to the current project (⌘N)")
                    .disabled(model.selectedProject == nil)
            }
        }
    }

    private var deletionTitle: String {
        let count = model.tasksPendingDeletion.count
        return count > 1 ? String(localized: "Delete \(count) Tasks?") : String(localized: "Delete Task?")
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            !model.tasksPendingDeletion.isEmpty
        } set: { isPresented in
            if !isPresented { model.tasksPendingDeletion = [] }
        }
    }

    /// A click on a row: Command adds or removes it from the selection, Shift selects a range to it.
    private func select(_ taskID: Int64) {
        // A double-click's clicks arrive here as well as opening the editor;
        // closing it or taking the keyboard back would undo the double-click.
        guard model.composer != .edit(taskID: taskID) else { return }
        model.closeComposer()
        // The click's own modifiers, rather than the keyboard's state by the time the tap is recognised.
        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if modifiers.contains(.command) {
            model.toggleSelection(of: taskID)
        } else if modifiers.contains(.shift) {
            model.extendSelection(to: taskID)
        } else {
            model.selectedTaskID = taskID
        }
        isListFocused = true
    }

    /// Single-key shortcuts for the list. Ignored while the composer is open so typing is never hijacked.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard model.composer == nil, !press.modifiers.contains(.command) else { return .ignored }
        let hasSelection = model.selectedTaskID != nil
        // Editing and outlining work on one task at a time.
        let hasSingleSelection = hasSelection && !model.hasMultipleSelection

        switch press.key {
        case .upArrow where press.modifiers.contains(.shift):
            model.extendSelection(by: -1)
        case .downArrow where press.modifiers.contains(.shift):
            model.extendSelection(by: 1)
        case .upArrow:
            model.moveSelection(by: -1)
        case .downArrow:
            model.moveSelection(by: 1)
        case .leftArrow where hasSingleSelection:
            model.collapseOrSelectParent()
        case .rightArrow where hasSingleSelection:
            model.expandSelected()
        case .return where hasSingleSelection:
            model.startEditing()
        case .space where hasSelection:
            model.toggleCompleted()
        case .tab where hasSingleSelection:
            if press.modifiers.contains(.shift) { model.outdent() } else { model.indent() }
        case .delete where hasSelection, .deleteForward where hasSelection:
            model.requestDeletion()
        case .escape where hasSelection:
            model.selectedTaskID = nil
        default:
            switch press.characters {
            case "j": model.moveSelection(by: 1)
            case "k": model.moveSelection(by: -1)
            case "a", "q": model.startAddingTask()
            case "A" where hasSingleSelection: model.startAddingSubtask()
            case "\u{19}" where hasSingleSelection: model.outdent() // Shift-Tab arrives as "back tab"
            default: return .ignored
            }
        }
        return .handled
    }
}
