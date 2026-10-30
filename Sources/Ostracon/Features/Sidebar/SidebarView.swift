import OstraconCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var isProjectsHeaderHovered = false

    var body: some View {
        @Bindable var model = model

        // A List rather than a ScrollView: in the sidebar column a ScrollView is drawn below the toolbar
        // inset but hit-tested above it, so clicks land ~38pt off target.
        List {
            addTaskButton
                .sidebarItem(top: 8, bottom: 8)

            ForEach(model.projects.filter(\.isInbox)) { project in
                SidebarRow(project: project)
                    .sidebarItem()
            }

            projectsHeader
                .sidebarItem(top: 16)

            ForEach(model.userProjects) { project in
                SidebarRow(project: project)
                    .sidebarItem()
            }

            if model.userProjects.isEmpty {
                Text("Add a project with the + button, then file tasks into it by typing #ProjectName.")
                    .font(.callout)
                    .foregroundStyle(Theme.subtleText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .sidebarItem()
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBackground)
        .confirmationDialog(
            "Delete project?",
            isPresented: $model.isConfirmingProjectDeletion,
            presenting: model.projectPendingDeletion
        ) { project in
            Button("Delete \(project.name)", role: .destructive) { model.confirmDeletion(project) }
        } message: { project in
            Text("This will permanently delete \(project.name) and all of its tasks.")
        }
    }

    private var addTaskButton: some View {
        Button {
            model.startAddingTask()
        } label: {
            // An HStack, not a Label: sidebar lists restyle Label icons, which would turn this one grey.
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .accessibilityHidden(true)
                Text("Add task")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Add a task to the current project (⌘N)")
    }

    private var projectsHeader: some View {
        HStack {
            Text("My Projects")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Add Project", systemImage: "plus") {
                model.startCreatingProject()
            }
            .buttonStyle(IconButtonStyle())
            .foregroundStyle(.secondary)
            .opacity(isProjectsHeaderHovered || model.userProjects.isEmpty ? 1 : 0.4)
            .help("Add project (⇧⌘N)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .onHover { isProjectsHeaderHovered = $0 }
    }
}

private extension View {
    /// Strips List row chrome so sidebar rows draw their own hover and selection.
    func sidebarItem(top: Double = 1, bottom: Double = 1) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
