import OstraconCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebarSelection) {
            if let inbox = model.inbox {
                SidebarRow(project: inbox)
            }

            Section("My Projects") {
                ForEach(model.userProjects) { project in
                    SidebarRow(project: project)
                }

                if model.userProjects.isEmpty {
                    Text("Add a project, then file tasks into it by typing #ProjectName.")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            AddProjectButton()
        }
        .confirmationDialog("Delete Project?", item: $model.projectPendingDeletion) { project in
            Button("Delete \(project.name)", role: .destructive) { model.confirmDeletion(project) }
        } message: { project in
            Text("This will permanently delete \(project.name) and all of its tasks.")
        }
    }
}
