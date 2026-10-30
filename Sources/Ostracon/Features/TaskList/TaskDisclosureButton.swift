import OstraconCore
import SwiftUI

/// The chevron that collapses or expands a task's subtasks.
///
/// Leaf tasks keep an invisible, disabled copy so every row lines up.
struct TaskDisclosureButton: View {
    @Environment(AppModel.self) private var model

    let row: TaskRow
    let isRowHovered: Bool

    var body: some View {
        Button(row.task.isCollapsed ? "Expand" : "Collapse", systemImage: "chevron.right", action: toggle)
            .buttonStyle(IconButtonStyle(size: Theme.disclosureSize))
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(row.task.isCollapsed ? 0 : 90))
            .opacity(opacity)
            .disabled(!row.hasChildren)
            .accessibilityHidden(!row.hasChildren)
    }

    private var opacity: Double {
        if !row.hasChildren {
            0
        } else if isRowHovered || row.task.isCollapsed {
            1
        } else {
            0.35
        }
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) {
            model.setCollapsed(row.id, !row.task.isCollapsed)
        }
    }
}
