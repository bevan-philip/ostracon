import SwiftUI

/// A task's checkbox: an empty circle that previews the tick on hover and fills when done.
struct CompletionCircle: View {
    let isCompleted: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .imageScale(.large)
                .foregroundStyle(isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                // A plain button only hit-tests opaque pixels; this makes the circle's middle clickable too.
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(isCompleted ? "Mark as Not Done" : "Complete Task")
    }

    private var symbolName: String {
        if isCompleted {
            "checkmark.circle.fill"
        } else if isHovered {
            "checkmark.circle"
        } else {
            "circle"
        }
    }
}
