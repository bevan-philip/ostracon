import SwiftUI

/// A borderless icon button whose whole square is clickable, with a hover highlight.
///
/// `.plain` only hit-tests a symbol's opaque pixels, which leaves glyphs like `plus` nearly unclickable.
struct IconButtonStyle: ButtonStyle {
    var size: Double = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: Double

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .frame(width: size, height: size)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.14 : isHovered ? 0.08 : 0),
                in: .rect(cornerRadius: 5)
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}
