import AppKit
import OstraconCore
import SwiftUI

/// The composer's task name field. Recognised projects, dates and reminders become blocks as you type, as in
/// Todoist; backspacing over a block turns it back into plain text that stays plain.
///
/// SwiftUI's `TextField` can't show inline blocks, so this wraps an `NSTextView` whose blocks are text attachments.
struct QuickAddField: NSViewRepresentable {
    /// Keys the composer may want before the text view gets them.
    enum Command {
        case submit, tab, moveUp, moveDown, escape
    }

    @Binding var draft: QuickAddDraft
    @Binding var isFocused: Bool
    let projects: [Project]
    let placeholder: String
    /// Changing this moves the keyboard into the field.
    let focusRequest: Int
    let tokenColor: (QuickAddDraft.Token) -> NSColor
    /// Returns `true` if the composer handled the key.
    let onCommand: (Command) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TokenTextView {
        let textView = TokenTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = TokenTextView.font
        textView.typingAttributes = TokenTextView.baseAttributes
        textView.setAccessibilityLabel(placeholder)
        textView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            Task { @MainActor in coordinator?.parent.isFocused = isFocused }
        }
        context.coordinator.render(draft, in: textView, isUserEdit: false)
        return textView
    }

    func updateNSView(_ textView: TokenTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if draft != coordinator.lastDraft {
            coordinator.render(draft, in: textView, isUserEdit: false)
        }
        if focusRequest != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = focusRequest
            textView.requestFocus()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: TokenTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        return CGSize(width: width, height: textView.height(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickAddField
        /// The draft the text view is showing.
        var lastDraft: QuickAddDraft?
        var lastFocusRequest = 0
        /// The field's own undo history, so clearing it doesn't touch the window's.
        private let undoManager = UndoManager()
        private var isRendering = false

        init(parent: QuickAddField) {
            self.parent = parent
        }

        /// Shows `draft`. A user edit keeps the caret the same distance from the end and can be undone;
        /// anything else puts the caret at the end and starts a fresh undo history.
        func render(_ draft: QuickAddDraft, in textView: TokenTextView, isUserEdit: Bool) {
            isRendering = true
            defer { isRendering = false }
            let text = attributedString(for: draft)
            let oldLength = (textView.string as NSString).length
            let distanceFromEnd = oldLength - textView.selectedRange().upperBound
            if isUserEdit {
                if textView.shouldChangeText(in: NSRange(location: 0, length: oldLength), replacementString: text.string) {
                    textView.textStorage?.setAttributedString(text)
                    textView.didChangeText()
                }
                textView.setSelectedRange(NSRange(location: max(0, text.length - distanceFromEnd), length: 0))
            } else {
                textView.textStorage?.setAttributedString(text)
                textView.setSelectedRange(NSRange(location: text.length, length: 0))
                undoManager.removeAllActions()
            }
            textView.typingAttributes = TokenTextView.baseAttributes
            textView.invalidateIntrinsicContentSize()
            lastDraft = draft
        }

        private func attributedString(for draft: QuickAddDraft) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for segment in draft.segments {
                switch segment {
                case .text(let text, let isLiteral):
                    var attributes = TokenTextView.baseAttributes
                    if isLiteral {
                        attributes[.literalText] = true
                    }
                    result.append(NSAttributedString(string: text, attributes: attributes))
                case .token(let token):
                    let attachment = TokenAttachment(token: token, color: parent.tokenColor(token))
                    let block = NSMutableAttributedString(attachment: attachment)
                    block.addAttributes(TokenTextView.baseAttributes, range: NSRange(location: 0, length: block.length))
                    result.append(block)
                }
            }
            return result
        }

        private static func draft(from text: NSAttributedString) -> QuickAddDraft {
            var segments: [QuickAddDraft.Segment] = []
            let string = text.string as NSString
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                if let attachment = attributes[.attachment] as? TokenAttachment {
                    segments.append(.token(attachment.token))
                } else {
                    let run = string.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
                    segments.append(.text(run, isLiteral: attributes[.literalText] != nil))
                }
            }
            return QuickAddDraft(segments: segments)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isRendering, let textView = notification.object as? TokenTextView, let storage = textView.textStorage else {
                return
            }
            var draft = Self.draft(from: storage)
            // Leave undone text alone, or undoing a block would just make it again; and wait out input-method composition.
            let isUndoing = undoManager.isUndoing || undoManager.isRedoing
            if !isUndoing && !textView.hasMarkedText() {
                let converted = draft.converted(projects: parent.projects, dates: DateParser(), includingTrailing: false)
                if converted != draft {
                    draft = converted
                    render(draft, in: textView, isUserEdit: true)
                }
            }
            textView.invalidateIntrinsicContentSize()
            lastDraft = draft
            parent.draft = draft
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // New typing is never literal, even right after a reverted block.
            (notification.object as? NSTextView)?.typingAttributes = TokenTextView.baseAttributes
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            // One line: pasted or dictated newlines become spaces.
            guard let text, text.contains(where: \.isNewline) else { return true }
            textView.insertText(text.replacing(/\s*\n\s*/, with: " "), replacementRange: range)
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return parent.onCommand(.submit)
            case #selector(NSResponder.insertTab(_:)):
                if !parent.onCommand(.tab) {
                    textView.window?.selectNextKeyView(nil)
                }
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommand(.moveDown)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCommand(.escape)
            default:
                return false
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
    }
}

extension NSAttributedString.Key {
    /// Marks text that came from a reverted block, or an existing task's name, so it's never turned into a block.
    static let literalText = NSAttributedString.Key("OstraconLiteralText")
}

/// The text view behind `QuickAddField`.
final class TokenTextView: NSTextView {
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

    var onFocusChange: ((Bool) -> Void)?
    private var wantsFocus = false

    func requestFocus() {
        if let window {
            window.makeFirstResponder(self)
        } else {
            wantsFocus = true
        }
    }

    /// The height the text needs when laid out `width` points wide.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let textContainer, let layoutManager else { return 0 }
        if textContainer.containerSize.width != width {
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let lineHeight = layoutManager.defaultLineHeight(for: Self.font)
        return ceil(max(layoutManager.usedRect(for: textContainer).height, lineHeight))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus, let window {
            wantsFocus = false
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocusChange?(true) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusChange?(false) }
        return didResign
    }

    /// Blocks only come from typing; pasted text arrives plain and is then recognised like typing.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    /// Backspacing right after a block turns it back into its words, which then stay as text.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0, let textStorage,
              let attachment = textStorage.attribute(.attachment, at: selection.location - 1, effectiveRange: nil) as? TokenAttachment
        else {
            super.deleteBackward(sender)
            return
        }
        var attributes = Self.baseAttributes
        attributes[.literalText] = true
        let words = NSAttributedString(string: attachment.token.text, attributes: attributes)
        let range = NSRange(location: selection.location - 1, length: 1)
        guard shouldChangeText(in: range, replacementString: words.string) else { return }
        textStorage.replaceCharacters(in: range, with: words)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + words.length, length: 0))
    }
}

/// A block in the task name, holding the token it stands for.
@MainActor
final class TokenAttachment: NSTextAttachment {
    let token: QuickAddDraft.Token

    init(token: QuickAddDraft.Token, color: NSColor) {
        self.token = token
        super.init(data: nil, ofType: nil)
        attachmentCell = TokenAttachmentCell(label: token.text, color: color, font: TokenTextView.font)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Draws a block as its words on a tinted rounded rectangle, sitting on the text's baseline.
final class TokenAttachmentCell: NSTextAttachmentCell {
    nonisolated private static let horizontalPadding = 4.0

    nonisolated private let label: String
    nonisolated private let color: NSColor
    // Immutable after init, and only drawn on the main thread.
    nonisolated(unsafe) private let labelFont: NSFont

    init(label: String, color: NSColor, font: NSFont) {
        self.label = label
        self.color = color
        self.labelFont = font
        super.init(textCell: label)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func cellSize() -> NSSize {
        let textSize = (label as NSString).size(withAttributes: [.font: labelFont])
        return NSSize(width: ceil(textSize.width) + Self.horizontalPadding * 2, height: ceil(labelFont.ascender - labelFont.descender))
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: labelFont.descender)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let block = cellFrame.insetBy(dx: 0.5, dy: 0)
        color.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: block, xRadius: 4, yRadius: 4).fill()
        let textRect = block.insetBy(dx: Self.horizontalPadding - 0.5, dy: 0)
        (label as NSString).draw(in: textRect, withAttributes: [.font: labelFont, .foregroundColor: color])
    }

    override func wantsToTrackMouse() -> Bool {
        false
    }
}
