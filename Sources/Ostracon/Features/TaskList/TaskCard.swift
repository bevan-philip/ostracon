import SwiftUI

/// A top-level task and its subtasks on one card, divided by hairlines that start at each row's checkbox.
struct TaskCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let group: TaskCardGroup
    let selectedTaskID: Int64?
    let onSelect: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(group.items) { item in
                VStack(alignment: .leading, spacing: 0) {
                    if item.id != group.items.first?.id {
                        Divider()
                            .padding(.leading, dividerInset(depth: item.depth))
                            .padding(.trailing, Theme.rowPadding)
                    }
                    switch item {
                    case .task(let row):
                        TaskRowView(row: row, isSelected: row.id == selectedTaskID, onSelect: onSelect)
                    case .composer(let mode, let depth):
                        TaskComposerView(mode: mode)
                            .id(mode)
                            .padding(.leading, composerLeading(depth: depth))
                            .padding(group.isStandaloneComposer ? 0 : Theme.cardInset)
                    }
                }
                .id(item.id)
                .transition(.opacity)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(cardFill)
                .stroke(.separator)
                .opacity(group.isStandaloneComposer ? 0 : 1)
        }
    }

    /// Dark mode needs one step more fill for cards to stand off the window background.
    private var cardFill: AnyShapeStyle {
        colorScheme == .dark ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary)
    }

    /// A subtask composer starts just before its siblings' checkboxes; a top-level one spans the card.
    private func composerLeading(depth: Int) -> Double {
        depth == 0 ? 0 : dividerInset(depth: depth) - Theme.rowSpacing - Theme.cardInset
    }

    /// Lines a divider up with the checkbox of the row beneath it.
    private func dividerInset(depth: Int) -> Double {
        Theme.rowPadding + Double(depth) * Theme.indentWidth + Theme.disclosureSize + Theme.rowSpacing
    }
}
