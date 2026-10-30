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
