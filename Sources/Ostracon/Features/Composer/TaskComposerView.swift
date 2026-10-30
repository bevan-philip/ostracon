import OstraconCore
import SwiftUI

/// The inline editor for adding or editing a task.
///
/// Return saves and, when adding, clears the fields so the next task can be typed straight away.
/// Typing `#` offers project autocomplete; Tab or Return accepts, ↑/↓ choose, Escape dismisses.
/// Projects, dates ("tomorrow 5pm") and `!reminders` typed in the name become blocks, reflected in the footer chips;
/// backspacing a block turns it back into text.
struct TaskComposerView: View {
    private enum Field {
        case details
    }

    @Environment(AppModel.self) private var model

    let mode: ComposerMode

    @State private var draft = QuickAddDraft()
    @State private var details = ""
    @State private var pickedProjectID: Int64?
    @State private var pickedDueDate: DueDate?
    @State private var pickedReminders: [Reminder] = []
    @State private var highlightedSuggestion = 0
    /// A `#query` the user dismissed with Escape; suggestions stay hidden until it changes.
    @State private var dismissedQuery: String?
    @FocusState private var focusedField: Field?
    @State private var isNameFocused = false
    @State private var nameFocusRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                QuickAddField(
                    draft: $draft,
                    isFocused: $isNameFocused,
                    projects: model.projects,
                    placeholder: "Task name",
                    focusRequest: nameFocusRequest,
                    tokenColor: tokenColor,
                    onCommand: handle
                )
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Task name — try “tomorrow 5pm” or #Project")
                            .foregroundStyle(.placeholder)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

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

            HStack {
                ProjectPickerMenu(
                    projects: model.projects,
                    selectedProjectID: effectiveProjectID,
                    isFromHashtag: parsed.projectID != nil,
                    onSelect: pick
                )
                DueDateChip(
                    dueDate: effectiveDueDate,
                    typedText: parsed.dueText,
                    onPick: pickDueDate,
                    onKeepAsText: keepDueDateAsText
                )
                ReminderChip(
                    reminders: pickedReminders,
                    typedReminders: parsed.reminders,
                    dueDate: effectiveDueDate,
                    isBlocked: model.areRemindersBlocked,
                    onChange: { pickedReminders = $0 }
                )
                Spacer()
                Button("Cancel", action: model.closeComposer)
                Button(isEditing ? "Save" : "Add Task", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsed.content.isEmpty)
            }
            .padding(8)
        }
        // A card lifted off the page, outlined in the project's colour while it has the keyboard.
        .background {
            RoundedRectangle(cornerRadius: Theme.composerCornerRadius)
                .fill(.background)
                .stroke(focusedField == nil && !isNameFocused ? AnyShapeStyle(.separator) : AnyShapeStyle(.tint.secondary))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .onExitCommand(perform: handleEscape)
        .onChange(of: draft) { _, newDraft in
            highlightedSuggestion = 0
            if newDraft.activeProjectQuery != dismissedQuery {
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
        model.composerResult(for: draft)
    }

    /// A date typed in the text wins over the picker.
    private var effectiveDueDate: DueDate? {
        parsed.dueDate ?? pickedDueDate
    }

    /// Where the task will go: a `#Project` in the text wins over the picker.
    private var effectiveProjectID: Int64 {
        parsed.projectID ?? pickedProjectID ?? model.selectedProjectID ?? model.projects.first?.id ?? 0
    }

    private var suggestions: [Project] {
        guard isNameFocused,
              let query = draft.activeProjectQuery,
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
                // Kept as typed: words like "Monday" in an existing name shouldn't turn into blocks.
                draft = QuickAddDraft(text: task.content, isLiteral: true)
                details = task.details
                pickedProjectID = task.projectID
                pickedDueDate = task.dueDate
                pickedReminders = task.reminders
            }
        }
        nameFocusRequest += 1
    }

    private func submit() {
        if !suggestions.isEmpty {
            _ = acceptHighlightedSuggestion()
            return
        }
        let saved = model.submitComposer(
            mode: mode, draft: draft, details: details, projectID: effectiveProjectID,
            dueDate: pickedDueDate, reminders: pickedReminders
        )
        if saved, !isEditing {
            draft = QuickAddDraft()
            details = ""
            pickedDueDate = nil
            pickedReminders = []
            nameFocusRequest += 1
        }
    }

    /// Keys from the name field. Returns `true` when handled here.
    private func handle(_ command: QuickAddField.Command) -> Bool {
        switch command {
        case .submit:
            submit()
            return true
        case .tab:
            return acceptHighlightedSuggestion()
        case .moveUp:
            return moveHighlight(by: -1)
        case .moveDown:
            return moveHighlight(by: 1)
        case .escape:
            handleEscape()
            return true
        }
    }

    private func moveHighlight(by offset: Int) -> Bool {
        guard !suggestions.isEmpty else { return false }
        highlightedSuggestion = (highlightedSuggestion + offset + suggestions.count) % suggestions.count
        return true
    }

    private func acceptHighlightedSuggestion() -> Bool {
        guard suggestions.indices.contains(highlightedSuggestion) else { return false }
        accept(suggestions[highlightedSuggestion])
        return true
    }

    private func accept(_ project: Project) {
        draft.complete(with: project)
        nameFocusRequest += 1
    }

    /// The draft with any half-typed last word recognised, as it would be on submit.
    private var finishedDraft: QuickAddDraft {
        draft.converted(projects: model.projects, dates: DateParser(), includingTrailing: true)
    }

    /// Choosing from the picker replaces any project block.
    private func pick(_ project: Project) {
        if parsed.projectID != nil {
            draft = finishedDraft
            draft.removeTokens { if case .project = $0 { true } else { false } }
        }
        pickedProjectID = project.id
        nameFocusRequest += 1
    }

    /// Choosing a date replaces any date block.
    private func pickDueDate(_ dueDate: DueDate?) {
        if parsed.dueDate != nil {
            draft = finishedDraft
            draft.removeTokens { if case .due = $0 { true } else { false } }
        }
        pickedDueDate = dueDate
    }

    /// Like backspacing the date block: its words stay in the name as text.
    private func keepDueDateAsText() {
        draft = finishedDraft
        draft.revertTokens { if case .due = $0 { true } else { false } }
    }

    private func tokenColor(_ token: QuickAddDraft.Token) -> NSColor {
        switch token.value {
        case .project(let id):
            model.project(id: id).map { NSColor(Theme.tint(for: $0)) } ?? .secondaryLabelColor
        case .due(let fragment):
            NSColor(Theme.color(for: DueUrgency(DateParser().resolve(fragment))))
        case .reminder:
            .secondaryLabelColor
        }
    }

    private func handleEscape() {
        if !suggestions.isEmpty {
            dismissedQuery = draft.activeProjectQuery
        } else {
            model.closeComposer()
        }
    }
}
