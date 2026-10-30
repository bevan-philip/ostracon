import SwiftUI

/// A small ring, in the project's colour, filled by the share of a task's subtasks that are done.
struct SubtaskProgressRing: View {
    let fraction: Double

    @ScaledMetric(relativeTo: .callout) private var size = 11.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}
