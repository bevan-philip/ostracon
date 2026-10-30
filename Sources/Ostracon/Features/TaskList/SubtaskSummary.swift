import OstraconCore
import SwiftUI

/// The line under a parent task: subtasks folded away, how many are done, and how many of those are hidden.
struct SubtaskSummary: View {
    let row: TaskRow
    let isShowingCompleted: Bool

    /// Whether there is anything to say; parents with no completed subtasks stay uncluttered unless collapsed.
    static func hasContent(for row: TaskRow) -> Bool {
        isCollapsedWithChildren(row) || showsProgress(for: row)
    }

    var body: some View {
        HStack(spacing: 12) {
            if Self.isCollapsedWithChildren(row) {
                Label(
                    row.childCount == 1 ? "1 subtask hidden" : "\(row.childCount) subtasks hidden",
                    systemImage: "arrow.turn.down.right"
                )
            }
            if Self.showsProgress(for: row) {
                Label {
                    Text("\(row.completedSubtaskCount) of \(row.subtaskCount) done")
                } icon: {
                    SubtaskProgressRing(fraction: Double(row.completedSubtaskCount) / Double(row.subtaskCount))
                }
                // Folded away, the completed subtasks are hidden anyway; otherwise say they're out of sight.
                if !isShowingCompleted && !row.task.isCollapsed {
                    Label(
                        row.completedSubtaskCount == 1 ? "1 completed hidden" : "\(row.completedSubtaskCount) completed hidden",
                        systemImage: "eye.slash"
                    )
                    .help("Show completed tasks with ⇧⌘C")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private static func isCollapsedWithChildren(_ row: TaskRow) -> Bool {
        row.task.isCollapsed && row.hasChildren
    }

    /// A completed parent's subtasks are all done too, so progress only means something on an open one.
    private static func showsProgress(for row: TaskRow) -> Bool {
        row.completedSubtaskCount > 0 && !row.task.isCompleted
    }
}
