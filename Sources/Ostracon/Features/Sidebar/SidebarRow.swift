import OstraconCore
import SwiftUI

struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    let project: Project

    var body: some View {
        let count = model.openCount(for: project)

        Label {
            Text(project.name)
        } icon: {
            ProjectIcon(project: project)
        }
        .badge(count)
        .tag(project.id)
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            model.move(payloads.flatMap(\.taskIDs), toProject: project)
        } isTargeted: { isDropTargeted = $0 }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.tint(for: project).opacity(isDropTargeted ? 0.3 : 0))
                .padding(.horizontal, 10)
        )
        .accessibilityValue(count == 1 ? Text("1 open task") : Text("\(count) open tasks"))
        .contextMenu {
            if !project.isInbox {
                Button("Edit Project…", action: edit)
                Button("Delete Project…", role: .destructive, action: requestDeletion)
            }
        }
    }

    private func edit() {
        model.startEditing(project)
    }

    private func requestDeletion() {
        model.projectPendingDeletion = project
    }
}
