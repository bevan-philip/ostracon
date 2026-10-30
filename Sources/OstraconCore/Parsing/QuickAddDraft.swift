import Foundation

/// The composer's task name as Todoist shows it: text interleaved with blocks for the recognised project,
/// due date and reminders.
///
/// Backspacing over a block turns it back into its words as *literal* text, which is never recognised again,
/// so a title can still say "Monday".
public struct QuickAddDraft: Hashable, Sendable {
    public enum Segment: Hashable, Sendable {
        /// Typed text. Literal text is left exactly as it is.
        case text(String, isLiteral: Bool)
        case token(Token)
    }

    public struct Token: Hashable, Sendable {
        public enum Value: Hashable, Sendable {
            case project(Int64)
            case due(DateFragment)
            case reminder(ReminderFragment)
        }

        /// The words as typed, which a reverted block turns back into.
        public var text: String
        public var value: Value

        public init(text: String, value: Value) {
            self.text = text
            self.value = value
        }
    }

    public private(set) var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = Self.normalised(segments)
    }

    public init(text: String, isLiteral: Bool = false) {
        self.init(segments: [.text(text, isLiteral: isLiteral)])
    }

    public var isEmpty: Bool {
        segments.isEmpty
    }

    /// The whole name with blocks shown as their words.
    public var plainText: String {
        segments.map { segment in
            switch segment {
            case .text(let text, _): text
            case .token(let token): token.text
            }
        }.joined()
    }

    // MARK: - Recognition

    /// Turns recognised words in non-literal text into blocks.
    ///
    /// While typing, words convert only once whitespace follows them, so "fri" isn't taken before "friday" is
    /// finished; `includingTrailing` converts everything, for submitting. A date or reminder block absorbs finished
    /// words typed straight after it that extend it ("tomorrow" then "at 5pm"). Only the latest project and date
    /// stay as blocks (plus a lone time or day that completes the date); older ones revert to literal text.
    /// Pass `dates: nil` to recognise projects only.
    public mutating func convert(projects: [Project], dates: DateParser?, includingTrailing: Bool) {
        if let dates {
            extendTokens(dates: dates, includingTrailing: includingTrailing)
        }
        segments = segments.flatMap { segment -> [Segment] in
            guard case .text(let text, false) = segment else { return [segment] }
            return Self.convert(text, projects: projects, dates: dates, includingTrailing: includingTrailing)
        }
        keepLatestTokens()
        segments = Self.normalised(segments)
    }

    public func converted(projects: [Project], dates: DateParser?, includingTrailing: Bool) -> QuickAddDraft {
        var draft = self
        draft.convert(projects: projects, dates: dates, includingTrailing: includingTrailing)
        return draft
    }

    /// Turns a block back into its words, as literal text.
    public mutating func revertToken(at index: Int) {
        guard segments.indices.contains(index), case .token(let token) = segments[index] else { return }
        segments[index] = .text(token.text, isLiteral: true)
        segments = Self.normalised(segments)
    }

    /// Turns matching blocks back into literal text.
    public mutating func revertTokens(where predicate: (Token.Value) -> Bool) {
        for index in segments.indices {
            if case .token(let token) = segments[index], predicate(token.value) {
                segments[index] = .text(token.text, isLiteral: true)
            }
        }
        segments = Self.normalised(segments)
    }

    /// Deletes matching blocks and their words.
    public mutating func removeTokens(where predicate: (Token.Value) -> Bool) {
        segments.removeAll { segment in
            if case .token(let token) = segment { predicate(token.value) } else { false }
        }
        segments = Self.normalised(segments)
    }

    /// The task the blocks describe.
    public func result(dates: DateParser) -> QuickAddResult {
        var texts: [String] = []
        var projectID: Int64?
        var due: DateFragment?
        var dueTexts: [String] = []
        var reminders: [ReminderFragment] = []
        for segment in segments {
            switch segment {
            case .text(let text, _):
                texts.append(text)
            case .token(let token):
                switch token.value {
                case .project(let id):
                    projectID = id
                case .due(let fragment):
                    due = due.map { $0.complements(fragment) ? $0.combined(with: fragment) : fragment } ?? fragment
                    dueTexts.append(token.text)
                case .reminder(let fragment):
                    reminders.append(fragment)
                }
            }
        }
        let dueDate = due.map(dates.resolve)
        return QuickAddResult(
            content: Self.normalise(texts.joined(separator: " ")),
            projectID: projectID,
            dueDate: dueDate,
            reminders: reminders.map { dates.resolve($0, due: dueDate) },
            dueText: dueTexts.isEmpty ? nil : dueTexts.joined(separator: " … ")
        )
    }

    // MARK: - Project autocomplete

    /// The partial project name after a `#` at the end of the name, if any.
    public var activeProjectQuery: String? {
        guard case .text(let text, false) = segments.last else { return nil }
        return QuickAddParser.activeProjectQuery(in: text)
    }

    /// Replaces the trailing `#query` with a block for `project`.
    public mutating func complete(with project: Project) {
        guard case .text(let text, false) = segments.last,
              let query = QuickAddParser.activeProjectQuery(in: text)
        else { return }
        let prefix = String(text.dropLast(query.count + 1))
        segments.removeLast()
        segments += [
            .text(prefix, isLiteral: false),
            .token(Token(text: "#\(project.name)", value: .project(project.id))),
            .text(" ", isLiteral: false)
        ]
        keepLatestTokens()
        segments = Self.normalised(segments)
    }

    // MARK: - Helpers

    /// Lets a date or reminder block grow into finished words typed after it, e.g. "at 5" then "pm".
    private mutating func extendTokens(dates: DateParser, includingTrailing: Bool) {
        var index = 0
        while index < segments.count - 1 {
            defer { index += 1 }
            guard case .token(var token) = segments[index],
                  case .text(var text, false) = segments[index + 1]
            else { continue }
            let words = Self.finishedWords(in: text, includingTrailing: includingTrailing).prefix(3)
            for end in words.reversed() {
                let extended = token.text + text[..<end]
                let value: Token.Value? = switch token.value {
                case .due: dates.dateFragment(from: extended).map(Token.Value.due)
                case .reminder: dates.reminderFragment(from: extended).map(Token.Value.reminder)
                case .project: nil
                }
                if let value {
                    token = Token(text: extended, value: value)
                    text = String(text[end...])
                    segments[index] = .token(token)
                    segments[index + 1] = .text(text, isLiteral: false)
                    break
                }
            }
        }
    }

    /// The end of each word in `text` that has been finished: followed by whitespace, or the last one
    /// when `includingTrailing` is set.
    private static func finishedWords(in text: String, includingTrailing: Bool) -> [String.Index] {
        var ends: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            let end = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            if end < text.endIndex || includingTrailing {
                ends.append(end)
            }
            index = end
        }
        return ends
    }

    /// Splits text into plain runs and blocks for every finished project, date and reminder in it.
    private static func convert(_ text: String, projects: [Project], dates: DateParser?, includingTrailing: Bool) -> [Segment] {
        func isFinished(_ range: Range<String.Index>) -> Bool {
            range.upperBound < text.endIndex ? text[range.upperBound].isWhitespace : includingTrailing
        }

        let projectMatches = QuickAddParser.projectMatches(in: text, projects: projects)
        var found: [(range: Range<String.Index>, value: Token.Value)] = []
        for match in projectMatches where isFinished(match.range) {
            // "#Work " might yet become "#Work Admin"; wait until the name can't grow into a longer one.
            let typed = (match.project.name + text[match.range.upperBound...]).lowercased()
            let couldGrow = projects.contains { $0.name.count > match.project.name.count && $0.name.lowercased().hasPrefix(typed) }
            if includingTrailing || !couldGrow {
                found.append((match.range, .project(match.project.id)))
            }
        }
        for phrase in dates?.phrases(in: text) ?? [] where isFinished(phrase.range) {
            // Words inside a project's name ("#Work Monday") aren't dates.
            guard !projectMatches.contains(where: { $0.range.overlaps(phrase.range) }) else { continue }
            switch phrase.value {
            case .due(let fragment): found.append((phrase.range, .due(fragment)))
            case .reminder(let fragment): found.append((phrase.range, .reminder(fragment)))
            }
        }

        var segments: [Segment] = []
        var position = text.startIndex
        for match in found.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) where match.range.lowerBound >= position {
            segments.append(.text(String(text[position..<match.range.lowerBound]), isLiteral: false))
            segments.append(.token(Token(text: String(text[match.range]), value: match.value)))
            position = match.range.upperBound
        }
        segments.append(.text(String(text[position...]), isLiteral: false))
        return segments
    }

    /// One project block and one date block (or a day and a time that complete each other); the rest revert.
    private mutating func keepLatestTokens() {
        var keep = Set<Int>()
        var latestDue: DateFragment?
        var keptDayAndTime = false
        var hasProject = false
        for index in segments.indices.reversed() {
            guard case .token(let token) = segments[index] else { continue }
            switch token.value {
            case .reminder:
                keep.insert(index)
            case .project:
                if !hasProject { keep.insert(index) }
                hasProject = true
            case .due(let fragment):
                if let latest = latestDue {
                    if !keptDayAndTime && latest.complements(fragment) {
                        keep.insert(index)
                        keptDayAndTime = true
                    }
                } else {
                    keep.insert(index)
                    latestDue = fragment
                }
            }
        }
        for index in segments.indices where !keep.contains(index) {
            if case .token(let token) = segments[index] {
                segments[index] = .text(token.text, isLiteral: true)
            }
        }
    }

    /// Joins neighbouring text of the same kind and drops empty text.
    private static func normalised(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            if case .text(let text, let isLiteral) = segment {
                guard !text.isEmpty else { continue }
                if case .text(let previous, isLiteral)? = result.last {
                    result[result.count - 1] = .text(previous + text, isLiteral: isLiteral)
                    continue
                }
            }
            result.append(segment)
        }
        return result
    }

    private static func normalise(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
