import SwiftUI

/// Hides the toolbar's title where the task list's own header shows it instead.
///
/// Only from macOS 26: without a title the toolbar needs `ToolbarSpacer` to keep its buttons on the trailing side,
/// and earlier systems don't have it, so they keep the title.
struct HeaderReplacesToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
