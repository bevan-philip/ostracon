import SwiftUI

/// Todoist's "+ Add task" row: the plus fills red on hover.
struct AddTaskRow: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isHovered ? Theme.accent : .clear)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHovered ? .white : Theme.accent)
                }
                .frame(width: 18, height: 18)
                Text("Add task")
                    .foregroundStyle(isHovered ? Theme.accent : Theme.subtleText)
            }
            .padding(.leading, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Add task (A or ⌘N)")
    }
}
