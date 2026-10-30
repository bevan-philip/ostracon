import SwiftUI

/// The "Add Project" button pinned to the bottom of the sidebar.
struct AddProjectButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Add Project", systemImage: "plus.circle", action: model.startCreatingProject)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .help("Add project (⇧⌘N)")
    }
}
