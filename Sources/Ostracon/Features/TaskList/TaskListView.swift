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
                            TaskCard(group: group, selectedTaskID: model.selectedTaskID, onSelect: select)
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
        .confirmationDialog("Delete Task?", item: $model.taskPendingDeletion) { task in
            Button("Delete", role: .destructive) { model.confirmDeletion(task) }
        } message: { task in
            Text("“\(task.content)” and any subtasks will be permanently deleted.")
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

    private func select(_ taskID: Int64) {
        model.closeComposer()
        model.selectedTaskID = taskID
        isListFocused = true
    }

    /// Single-key shortcuts for the list. Ignored while the composer is open so typing is never hijacked.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard model.composer == nil, !press.modifiers.contains(.command) else { return .ignored }
        let hasSelection = model.selectedTaskID != nil

        switch press.key {
        case .upArrow:
            model.moveSelection(by: -1)
        case .downArrow:
            model.moveSelection(by: 1)
        case .leftArrow where hasSelection:
            model.collapseOrSelectParent()
        case .rightArrow where hasSelection:
            model.expandSelected()
        case .return where hasSelection:
            model.startEditing()
        case .space where hasSelection:
            model.toggleCompleted()
        case .tab where hasSelection:
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
            case "A" where hasSelection: model.startAddingSubtask()
            case "\u{19}" where hasSelection: model.outdent() // Shift-Tab arrives as "back tab"
            default: return .ignored
            }
        }
        return .handled
    }
}
