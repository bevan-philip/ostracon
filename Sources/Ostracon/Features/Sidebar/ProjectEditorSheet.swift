import OstraconCore
import SwiftUI

struct ProjectEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectDraft
    @FocusState private var isNameFocused: Bool

    init(draft: ProjectDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.isNew ? "Add project" : "Edit project")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.callout.weight(.semibold))
                TextField("Name", text: $draft.name, prompt: Text("e.g. Work"))
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(save)
                if draft.name.contains(where: \.isWhitespace) {
                    Text("Tip: type #\(draft.name.trimmingCharacters(in: .whitespaces)) in a task to file it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.callout.weight(.semibold))
                ColorSwatchGrid(selection: $draft.color)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        model.saveProjectDraft(draft)
    }
}
