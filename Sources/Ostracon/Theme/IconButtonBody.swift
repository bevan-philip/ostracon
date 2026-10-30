import SwiftUI

/// The body of `IconButtonStyle`; a view of its own so it can track hover state.
struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: Double

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .frame(width: size, height: size)
            .background(
                (configuration.isPressed ? HierarchicalShapeStyle.tertiary : .quaternary)
                    .opacity(isHovered || configuration.isPressed ? 1 : 0),
                in: .rect(cornerRadius: 5)
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}
