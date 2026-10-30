@testable import Ostracon
import AppKit
import OstraconCore
import SwiftUI
import Testing

/// Drives the real text view with the same calls the keyboard makes.
@MainActor
struct QuickAddFieldTests {
    final class DraftBox {
        var draft = QuickAddDraft()
    }

    let box = DraftBox()
    let textView = TokenTextView(usingTextLayoutManager: false)
    let coordinator: QuickAddField.Coordinator

    init() {
        let box = box
        let field = QuickAddField(
            draft: Binding(get: { box.draft }, set: { box.draft = $0 }),
            isFocused: .constant(false),
            projects: [Project(id: 2, name: "Work", color: .red, sortOrder: 0, isInbox: false)],
            placeholder: "Task name",
            focusRequest: 0,
            tokenColor: { _ in .systemRed },
            onCommand: { _ in false }
        )
        coordinator = field.makeCoordinator()
        textView.delegate = coordinator
        textView.allowsUndo = true
        textView.typingAttributes = TokenTextView.baseAttributes
    }

    private func type(_ text: String) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
    }

    /// Blocks in [brackets], literal text in «guillemets».
    private var rendered: String {
        box.draft.segments.map { segment in
            switch segment {
            case .text(let text, false): text
            case .text(let text, true): "«\(text)»"
            case .token(let token): "[\(token.text)]"
            }
        }.joined()
    }

    @Test func typedDateBecomesABlockAndBackspaceRevertsIt() {
        type("Plan launch friday ")
        #expect(rendered == "Plan launch [friday] ")
        #expect(textView.string == "Plan launch \u{FFFC} ", "The block is a single character")

        textView.deleteBackward(nil)
        textView.deleteBackward(nil)
        #expect(rendered == "Plan launch «friday»")
        #expect(textView.string == "Plan launch friday")
        #expect(textView.selectedRange() == NSRange(location: 18, length: 0), "The caret stays after the words")

        type(" tomorrow ")
        #expect(rendered == "Plan launch «friday» [tomorrow] ", "Reverted words stay text; new ones still convert")
    }

    @Test func projectsBecomeBlocks() {
        type("Report #Work today ")
        #expect(rendered == "Report [#Work] [today] ")
        textView.deleteBackward(nil)
        textView.deleteBackward(nil)
        #expect(rendered == "Report [#Work] «today»")
    }

    @Test func blocksSurviveTypingInTheMiddle() {
        type("Call tomorrow ")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        type(" mum")
        #expect(rendered == "Call mum [tomorrow] ")
    }
}
