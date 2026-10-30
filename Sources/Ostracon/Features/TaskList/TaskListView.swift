import OstraconCore
import SwiftUI

struct TaskListView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isListFocused: Bool

    var body: some View {
        @Bindable var model = model

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    taskList
                    if model.composer == nil {
                        AddTaskRow { model.startAddingTask() }
                        if model.rows.isEmpty {
                            EmptyStateView()
                        }
                    }
                }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.selectedTaskID) { _, taskID in
                guard let taskID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("task-\(taskID)")
                }
            }
        }
        .background(Theme.contentBackground)
        .focusable()
        .focused($isListFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onChange(of: model.composer) { _, composer in
            if composer == nil { isListFocused = true }
        }
        .onAppear { isListFocused = true }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .confirmationDialog(
            "Delete task?",
            isPresented: $model.isConfirmingTaskDeletion,
            presenting: model.taskPendingDeletion
        ) { task in
            Button("Delete", role: .destructive) { model.confirmDeletion(task) }
        } message: { task in
            Text("“\(task.content)” and any subtasks will be permanently deleted.")
        }
        .navigationTitle(model.selectedProject?.name ?? "Ostracon")
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Show Completed", systemImage: "checkmark.circle", isOn: $model.showCompleted)
                    .help(model.showCompleted ? "Hide completed tasks (⇧⌘C)" : "Show completed tasks (⇧⌘C)")
            }
        }
    }

    private var header: some View {
        Text(model.selectedProject?.name ?? "")
            .font(.title.bold())
            .padding(.top, 36)
            .padding(.bottom, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private var taskList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.listItems) { item in
                switch item {
                case .task(let row):
                    TaskRowView(row: row) { select(row.id) }
                        .id(item.id)
                        .transition(.opacity)
                case .composer(let mode, let depth):
                    TaskComposerView(mode: mode)
                        .id(mode)
                        .padding(.leading, Double(depth) * 30)
                        .padding(.vertical, 8)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: model.listItems)
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
