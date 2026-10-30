import SwiftUI

/// Todoist's round checkbox: hovering previews the tick.
struct CompletionCircle: View {
    let isCompleted: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Theme.checkbox : Theme.checkbox.opacity(isHovered ? 0.12 : 0))
                Circle()
                    .strokeBorder(Theme.checkbox, lineWidth: 1)
                if isCompleted || isHovered {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCompleted ? .white : Theme.checkbox)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(isCompleted ? "Mark as not done" : "Complete task")
    }
}
