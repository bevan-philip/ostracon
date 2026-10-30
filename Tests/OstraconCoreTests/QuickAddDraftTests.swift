import Foundation
import OstraconCore
import Testing

struct QuickAddDraftTests {
    let projects = [
        Project(id: 1, name: "Inbox", color: .blue, sortOrder: 0, isInbox: true),
        Project(id: 2, name: "Work", color: .red, sortOrder: 0, isInbox: false),
        Project(id: 3, name: "Work Admin", color: .teal, sortOrder: 1, isInbox: false)
    ]
    let parser: DateParser

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        // Friday 30 October 2026, 10:00.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10)))
        parser = DateParser(now: now, calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    /// Types `text` a character at a time, converting as the composer does after each keystroke.
    private func type(_ text: String, into draft: QuickAddDraft = QuickAddDraft()) -> QuickAddDraft {
        var draft = draft
        for character in text {
            var segments = draft.segments
            if case .text(let last, false)? = segments.last {
                segments[segments.count - 1] = .text(last + String(character), isLiteral: false)
            } else {
                segments.append(.text(String(character), isLiteral: false))
            }
            draft = QuickAddDraft(segments: segments)
            draft.convert(projects: projects, dates: parser, includingTrailing: false)
        }
        return draft
    }

    /// The draft written as text, with blocks in [brackets] and literal text in «guillemets».
    private func render(_ draft: QuickAddDraft) -> String {
        draft.segments.map { segment in
            switch segment {
            case .text(let text, false): text
            case .text(let text, true): "«\(text)»"
            case .token(let token): "[\(token.text)]"
            }
        }.joined()
    }

    private func revertLastToken(_ draft: inout QuickAddDraft) {
        if let index = draft.segments.lastIndex(where: { if case .token = $0 { true } else { false } }) {
            draft.revertToken(at: index)
        }
    }

    @Test func wordsBecomeBlocksOnceFinished() {
        #expect(render(type("Call fri")) == "Call fri", "Still typing — might become friday")
        #expect(render(type("Call friday")) == "Call friday")
        #expect(render(type("Call friday ")) == "Call [friday] ")
        #expect(render(type("Call next friday ")) == "Call [next friday] ")
    }

    @Test func blocksGrowWithTheWordsAfterThem() {
        #expect(render(type("Call tomorrow at 5pm ")) == "Call [tomorrow at 5pm] ")
        #expect(render(type("Call at 5 pm ")) == "Call [at 5 pm] ", "A bare hour picks up its am/pm")
        #expect(render(type("Renew jan 27 2027 ")) == "Renew [jan 27 2027] ")
        #expect(render(type("Dentist !30 min before ")) == "Dentist [!30 min before] ")
        #expect(render(type("Dentist tomorrow and call ")) == "Dentist [tomorrow] and call ")
    }

    @Test func backspacedBlocksStayAsText() {
        var draft = type("Plan Monday ")
        #expect(render(draft) == "Plan [Monday] ")
        revertLastToken(&draft)
        #expect(render(draft) == "Plan «Monday» ")

        draft = type("standup tomorrow ", into: draft)
        #expect(render(draft) == "Plan «Monday» standup [tomorrow] ", "Literal text isn't re-read, new text still is")
        let result = draft.result(dates: parser)
        #expect(result.content == "Plan Monday standup")
        #expect(result.dueDate == DueDate(year: 2026, month: 10, day: 31))
    }

    @Test func aNewDateRevertsTheOldOne() {
        let draft = type("Move monday meeting to friday ")
        #expect(render(draft) == "Move «monday» meeting to [friday] ")
    }

    @Test func aLoneTimeAndDayStayTogether() {
        let draft = type("5pm call mum tomorrow ")
        #expect(render(draft) == "[5pm] call mum [tomorrow] ")
        #expect(draft.result(dates: parser).dueDate == DueDate(year: 2026, month: 10, day: 31, time: TimeOfDay(hour: 17)))
    }

    @Test func projectsWaitUntilTheNameCantGrow() {
        #expect(render(type("Report #Work ")) == "Report #Work ", "Could still become #Work Admin")
        #expect(render(type("Report #Work Admin ")) == "Report [#Work Admin] ")
        #expect(render(type("Report #Work today ")) == "Report [#Work] [today] ")
        #expect(type("Report #Work").result(dates: parser).projectID == nil)
        #expect(type("Report #Work").converted(projects: projects, dates: parser, includingTrailing: true)
            .result(dates: parser).projectID == 2, "Submitting takes it")
    }

    @Test func autocompleteMakesABlock() {
        var draft = type("Report #wo")
        #expect(draft.activeProjectQuery == "wo")
        draft.complete(with: projects[2])
        #expect(render(draft) == "Report [#Work Admin] ")
        #expect(draft.activeProjectQuery == nil)
    }

    @Test func submittingConvertsTheLastWord() {
        let draft = type("Call mum tomorrow")
        #expect(draft.result(dates: parser).dueDate == nil)
        let submitted = draft.converted(projects: projects, dates: parser, includingTrailing: true)
        #expect(render(submitted) == "Call mum [tomorrow]")
        #expect(submitted.result(dates: parser).content == "Call mum")
    }

    @Test func existingNamesLoadAsLiteral() {
        let draft = type(" tomorrow ", into: QuickAddDraft(text: "Review Monday notes", isLiteral: true))
        #expect(render(draft) == "«Review Monday notes» [tomorrow] ")
    }

    @Test func removingAndRevertingByKind() {
        var draft = type("Pay rent #Work today !9am ")
        #expect(render(draft) == "Pay rent [#Work] [today] [!9am] ")
        draft.removeTokens { if case .due = $0 { true } else { false } }
        #expect(render(draft) == "Pay rent [#Work]  [!9am] ")
        draft.revertTokens { if case .project = $0 { true } else { false } }
        #expect(render(draft) == "Pay rent «#Work»  [!9am] ")
    }
}
