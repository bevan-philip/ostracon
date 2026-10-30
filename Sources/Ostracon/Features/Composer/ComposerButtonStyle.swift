import SwiftUI

/// Todoist's flat composer buttons: red for the primary action, grey for Cancel.
struct ComposerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isProminent ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(background(isPressed: configuration.isPressed), in: .rect(cornerRadius: 5))
            .opacity(isEnabled ? 1 : 0.5)
    }

    private func background(isPressed: Bool) -> Color {
        if isProminent {
            isPressed ? Theme.accentHover : Theme.accent
        } else {
            isPressed ? Theme.composerBorder : Theme.secondaryButton
        }
    }
}
