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
                    HStack {
                        Label {
                            Text(project.name)
                        } icon: {
                            ProjectIcon(project: project)
                        }
                        Spacer()
                        Text("⇥")
                            .foregroundStyle(.secondary)
                            .opacity(index == highlightedIndex ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        index == highlightedIndex ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 5)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == highlightedIndex ? .isSelected : [])
            }
        }
        .padding(4)
        .glassSurface(in: .rect(cornerRadius: 9))
        .frame(maxWidth: 320, alignment: .leading)
    }
}
