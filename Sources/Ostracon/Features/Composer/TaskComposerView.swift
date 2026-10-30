import OstraconCore
import SwiftUI

/// The inline editor for adding or editing a task.
///
/// Return saves and, when adding, clears the fields so the next task can be typed straight away.
/// Typing `#` offers project autocomplete; Tab or Return accepts, ↑/↓ choose, Escape dismisses.
struct TaskComposerView: View {
    private enum Field {
        case content, details
    }

    @Environment(AppModel.self) private var model

    let mode: ComposerMode

    @State private var text = ""
    @State private var details = ""
    @State private var pickedProjectID: Int64?
    @State private var highlightedSuggestion = 0
    /// A `#query` the user dismissed with Escape; suggestions stay hidden until it changes.
    @State private var dismissedQuery: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Task name", text: $text, prompt: Text("Task name — type # to pick a project"))
                    .font(.body.weight(.medium))
                    .focused($focusedField, equals: .content)
                    .onSubmit(submit)
                    .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                    .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                    .onKeyPress(.tab) { acceptHighlightedSuggestion() }

                if !suggestions.isEmpty {
                    ProjectSuggestionList(
                        projects: suggestions,
                        highlightedIndex: highlightedSuggestion,
                        onSelect: accept
                    )
                }

                TextField("Description", text: $details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .focused($focusedField, equals: .details)
                    .onSubmit(submit)
            }
            .textFieldStyle(.plain)
            .padding(12)

            Divider()

            HStack(spacing: 8) {
                ProjectPickerMenu(
                    projects: model.projects,
                    selectedProjectID: effectiveProjectID,
                    isFromHashtag: parsed.projectID != nil,
                    onSelect: pick
                )
                Spacer()
                Button("Cancel") { model.closeComposer() }
                    .buttonStyle(ComposerButtonStyle(isProminent: false))
                Button(isEditing ? "Save" : "Add task", action: submit)
                    .buttonStyle(ComposerButtonStyle(isProminent: true))
                    .disabled(parsed.content.isEmpty)
            }
            .padding(8)
        }
        .background(Theme.contentBackground, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focusedField == nil ? Theme.composerBorder : Theme.composerBorderFocused)
        }
        .onExitCommand(perform: handleEscape)
        .onChange(of: text) { _, newText in
            highlightedSuggestion = 0
            if QuickAddParser.activeProjectQuery(in: newText) != dismissedQuery {
                dismissedQuery = nil
            }
        }
        .onAppear(perform: loadInitialValues)
    }

    // MARK: - Derived state

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var parsed: QuickAddResult {
        QuickAddParser.parse(text, projects: model.projects)
    }

    /// Where the task will go: a `#Project` in the text wins over the picker.
    private var effectiveProjectID: Int64 {
        parsed.projectID ?? pickedProjectID ?? model.selectedProjectID ?? model.projects.first?.id ?? 0
    }

    private var suggestions: [Project] {
        guard focusedField == .content,
              let query = QuickAddParser.activeProjectQuery(in: text),
              query != dismissedQuery
        else { return [] }
        return Array(QuickAddParser.suggestions(for: query, in: model.projects).prefix(6))
    }

    // MARK: - Actions

    private func loadInitialValues() {
        switch mode {
        case .add(let parentID):
            pickedProjectID = parentID.flatMap(model.task(id:))?.projectID ?? model.selectedProjectID
        case .edit(let taskID):
            if let task = model.task(id: taskID) {
                text = task.content
                details = task.details
                pickedProjectID = task.projectID
            }
        }
        focusedField = .content
    }

    private func submit() {
        if !suggestions.isEmpty {
            _ = acceptHighlightedSuggestion()
            return
        }
        let saved = model.submitComposer(mode: mode, text: text, details: details, projectID: effectiveProjectID)
        if saved, !isEditing {
            text = ""
            details = ""
            focusedField = .content
        }
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        highlightedSuggestion = (highlightedSuggestion + offset + suggestions.count) % suggestions.count
        return .handled
    }

    private func acceptHighlightedSuggestion() -> KeyPress.Result {
        guard suggestions.indices.contains(highlightedSuggestion) else { return .ignored }
        accept(suggestions[highlightedSuggestion])
        return .handled
    }

    private func accept(_ project: Project) {
        text = QuickAddParser.complete(text, with: project)
        focusedField = .content
    }

    /// Choosing from the picker replaces any `#Project` typed in the text.
    private func pick(_ project: Project) {
        if parsed.projectID != nil {
            text = parsed.content
        }
        pickedProjectID = project.id
        focusedField = .content
    }

    private func handleEscape() {
        if !suggestions.isEmpty {
            dismissedQuery = QuickAddParser.activeProjectQuery(in: text)
        } else {
            model.closeComposer()
        }
    }
}
