import OstraconCore
import SwiftUI

struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    let project: Project

    var body: some View {
        let isSelected = model.selectedProjectID == project.id
        let count = model.openCount(for: project)

        Button {
            model.select(project: project)
        } label: {
            HStack(spacing: 8) {
                ProjectIcon(project: project)
                Text(project.name)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Theme.accent : .primary)
                Spacer(minLength: 4)
                if count > 0 {
                    Text(count, format: .number)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.subtleText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background(isSelected: isSelected), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text("\(count) open tasks"))
        .contextMenu {
            if !project.isInbox {
                Button("Edit Project…") { model.startEditing(project) }
                Button("Delete Project…", role: .destructive) { model.projectPendingDeletion = project }
            }
        }
    }

    private func background(isSelected: Bool) -> Color {
        if isSelected {
            Theme.sidebarSelection
        } else if isHovered {
            Theme.sidebarHover
        } else {
            .clear
        }
    }
}
