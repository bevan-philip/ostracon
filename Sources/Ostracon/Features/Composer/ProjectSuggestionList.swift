import OstraconCore
import SwiftUI

/// The `#` autocomplete list shown under the task name.
struct ProjectSuggestionList: View {
    let projects: [Project]
    let highlightedIndex: Int
    let onSelect: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                Button {
                    onSelect(project)
                } label: {
                    HStack(spacing: 8) {
                        ProjectIcon(project: project)
                        Text(project.name)
                        Spacer()
                        if index == highlightedIndex {
                            Text("⇥")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(index == highlightedIndex ? Theme.rowSelection : .clear, in: .rect(cornerRadius: 5))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == highlightedIndex ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.contentBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.composerBorder)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .frame(maxWidth: 320, alignment: .leading)
    }
}
