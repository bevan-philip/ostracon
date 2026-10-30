import SwiftUI

/// The "Add Task" row under the list, lined up with the tasks' checkboxes.
struct AddTaskRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Add Task")
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.large)
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, Theme.rowPadding)
        .padding(.leading, Theme.rowPadding + Theme.disclosureSize + Theme.rowSpacing)
        .help("Add task (A or ⌘N)")
    }
}
