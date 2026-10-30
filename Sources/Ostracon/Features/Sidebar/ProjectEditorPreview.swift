import SwiftUI

/// The top of the project editor: a large icon in the chosen colour, with the sheet's title beneath.
struct ProjectEditorPreview: View {
    let draft: ProjectDraft

    var body: some View {
        VStack(spacing: 8) {
            ProjectIcon(color: draft.color)
                .font(.system(.largeTitle))
                .imageScale(.large)
                .animation(.snappy, value: draft.color)
            Text(draft.isNew ? "New Project" : "Edit Project")
                .font(.title3.bold())
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}
