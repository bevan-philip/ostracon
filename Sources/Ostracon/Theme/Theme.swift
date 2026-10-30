import OstraconCore
import SwiftUI

/// Todoist-inspired colours.
enum Theme {
    static let accent = Color(hex: 0xDC4C3E)
    static let accentHover = Color(hex: 0xC3392C)

    static let contentBackground = Color(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let sidebarBackground = Color(light: 0xFCFAF8, dark: 0x262626)
    static let sidebarSelection = Color(light: 0xFFEFE5, dark: 0x4A2B26)
    static let sidebarHover = Color(light: 0xF2EFED, dark: 0x333333)
    static let rowSelection = Color(light: 0xF5F3F1, dark: 0x2C2C2C)
    static let separator = Color(light: 0xEEEEEE, dark: 0x333333)
    static let composerBorder = Color(light: 0xDDDDDD, dark: 0x444444)
    static let composerBorderFocused = Color(light: 0x999999, dark: 0x777777)
    static let secondaryButton = Color(light: 0xF5F5F5, dark: 0x333333)
    static let subtleText = Color(light: 0x808080, dark: 0x999999)
    static let checkbox = Color(light: 0x999999, dark: 0x888888)

    static let inboxColor = Color(hex: 0x246FE0)

    static func color(for projectColor: ProjectColor) -> Color {
        Color(hex: projectColor.hex)
    }
}
