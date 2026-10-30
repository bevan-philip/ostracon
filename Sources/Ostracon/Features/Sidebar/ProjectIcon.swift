import OstraconCore
import SwiftUI

/// Inbox tray, or a `#` in the project's colour.
struct ProjectIcon: View {
    let project: Project

    var body: some View {
        Image(systemName: project.isInbox ? "tray" : "number")
            .foregroundStyle(project.isInbox ? Theme.inboxColor : Theme.color(for: project.color))
            .fontWeight(.medium)
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}
