import OstraconCore
import SwiftUI

/// Shared layout constants and colours. Everything else uses the system's own styles.
enum Theme {
    /// How far each level of nesting indents a task.
    static let indentWidth = 28.0
    /// The side of the disclosure chevron's button; leaf rows reserve the same space so tasks line up.
    static let disclosureSize = 20.0
    static let rowSpacing = 8.0
    static let rowPadding = 10.0
    /// The gap between task cards.
    static let taskSpacing = 6.0
    static let cardCornerRadius = 12.0
    /// How far a row's highlight sits inside its card, and the composer's margin when it's on one.
    static let cardInset = 4.0
    /// Concentric with the card's corners.
    static let rowCornerRadius = cardCornerRadius - cardInset
    static let composerCornerRadius = 12.0
    /// The task list reads as a centred column rather than stretching across wide windows.
    static let contentMaxWidth = 760.0

    static let inboxColor = Color.blue

    static func color(for projectColor: ProjectColor) -> Color {
        Color(hex: projectColor.hex)
    }

    /// The colour a project's page is tinted with.
    static func tint(for project: Project) -> Color {
        project.isInbox ? inboxColor : color(for: project.color)
    }
}
