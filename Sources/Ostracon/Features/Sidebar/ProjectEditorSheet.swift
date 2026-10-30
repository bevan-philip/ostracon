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
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Work"))
                    .focused($isNameFocused)
                    .onSubmit(save)
                LabeledContent("Color") {
                    ColorSwatchGrid(selection: $draft.color)
                }
            } header: {
                ProjectEditorPreview(draft: draft)
            } footer: {
                if draft.name.contains(where: \.isWhitespace) {
                    Text("Tip: type #\(draft.name.trimmingCharacters(in: .whitespaces)) in a task to file it here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(draft.isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cancel() {
        dismiss()
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        model.saveProjectDraft(draft)
    }
}
