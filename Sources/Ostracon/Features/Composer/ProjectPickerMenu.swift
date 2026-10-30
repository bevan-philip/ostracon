import OstraconCore
import SwiftUI

/// The project chip at the bottom-left of the composer.
struct ProjectPickerMenu: View {
    let projects: [Project]
    let selectedProjectID: Int64
    /// Highlights the chip when the project came from a `#` token in the text.
    let isFromHashtag: Bool
    let onSelect: (Project) -> Void

    var body: some View {
        Menu {
            ForEach(projects) { project in
                Button {
                    onSelect(project)
                } label: {
                    if project.id == selectedProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let selected {
                    ProjectIcon(project: selected)
                    Text(selected.name)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isFromHashtag ? Theme.sidebarSelection : Theme.secondaryButton, in: .rect(cornerRadius: 5))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Project — or type #ProjectName in the task name")
        .accessibilityLabel("Project: \(selected?.name ?? "")")
    }

    private var selected: Project? {
        projects.first { $0.id == selectedProjectID }
    }
}
