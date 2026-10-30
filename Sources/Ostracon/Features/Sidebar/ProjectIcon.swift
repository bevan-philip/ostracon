import OstraconCore
import SwiftUI

/// A white tray (Inbox) or `#` (projects) on a circle of the project's colour.
struct ProjectIcon: View {
    private let isInbox: Bool
    private let color: Color

    init(project: Project) {
        isInbox = project.isInbox
        color = Theme.tint(for: project)
    }

    /// A project icon for a colour that isn't saved yet, such as in the project editor.
    init(color: ProjectColor) {
        isInbox = false
        self.color = Theme.color(for: color)
    }

    var body: some View {
        Image(systemName: isInbox ? "tray.circle.fill" : "number.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .accessibilityHidden(true)
    }
}
