import OstraconCore
import SwiftUI

/// The project's name in its colour, with the number of open tasks opposite.
struct TaskListHeader: View {
    let project: Project
    let openCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(project.name)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            } icon: {
                ProjectIcon(project: project)
            }
            Spacer()
            Text(openCount, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: openCount)
        }
        .font(.largeTitle.bold())
        .fontDesign(.rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(project.name)
        .accessibilityValue(openCount == 1 ? Text("1 open task") : Text("\(openCount) open tasks"))
        .accessibilityAddTraits(.isHeader)
    }
}
