import SwiftUI

/// What follows the pointer while tasks are dragged: the first task's name, with a count badge
/// when there are more, as in Finder.
struct TaskDragPreview: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            if count > 1 {
                Text(count, format: .number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.red, in: .capsule)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: .capsule)
    }
}
