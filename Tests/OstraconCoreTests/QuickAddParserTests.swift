import OstraconCore
import Testing

struct QuickAddParserTests {
    let projects = [
        Project(id: 1, name: "Inbox", color: .blue, sortOrder: 0, isInbox: true),
        Project(id: 2, name: "Work", color: .red, sortOrder: 0, isInbox: false),
        Project(id: 3, name: "Work Admin", color: .teal, sortOrder: 1, isInbox: false),
        Project(id: 4, name: "Home", color: .green, sortOrder: 2, isInbox: false)
    ]

    @Test func plainTextHasNoProject() {
        let result = QuickAddParser.parse("Buy milk", projects: projects)
        #expect(result == QuickAddResult(content: "Buy milk", projectID: nil))
    }

    @Test func trailingHashtagSelectsProject() {
        let result = QuickAddParser.parse("Buy milk #Home", projects: projects)
        #expect(result == QuickAddResult(content: "Buy milk", projectID: 4))
    }

    @Test func leadingAndMiddleHashtags() {
        #expect(QuickAddParser.parse("#home Buy milk", projects: projects).projectID == 4)
        let middle = QuickAddParser.parse("Send #Work report", projects: projects)
        #expect(middle == QuickAddResult(content: "Send report", projectID: 2))
    }

    @Test func longestMultiWordNameWins() {
        let result = QuickAddParser.parse("File expenses #Work Admin", projects: projects)
        #expect(result == QuickAddResult(content: "File expenses", projectID: 3))
    }

    @Test func unknownOrEmbeddedHashtagsAreLeftAlone() {
        #expect(QuickAddParser.parse("Fix issue #42", projects: projects) == QuickAddResult(content: "Fix issue #42", projectID: nil))
        #expect(QuickAddParser.parse("C#Home", projects: projects).projectID == nil)
        #expect(QuickAddParser.parse("#Homework", projects: projects).projectID == nil)
    }

    @Test func lastHashtagWins() {
        let result = QuickAddParser.parse("Call #Home #Work", projects: projects)
        #expect(result == QuickAddResult(content: "Call #Home", projectID: 2), "The earlier project goes back to being text")
    }

    @Test func activeQueryTracksTrailingHashtag() {
        #expect(QuickAddParser.activeProjectQuery(in: "Buy milk") == nil)
        #expect(QuickAddParser.activeProjectQuery(in: "Buy milk #") == "")
        #expect(QuickAddParser.activeProjectQuery(in: "Buy milk #Wo") == "Wo")
        #expect(QuickAddParser.activeProjectQuery(in: "Buy milk #Work A") == "Work A")
    }

    @Test func suggestionsPreferPrefixMatches() {
        let names = QuickAddParser.suggestions(for: "o", in: projects).map(\.name)
        #expect(Set(names) == ["Inbox", "Work", "Work Admin", "Home"])
        #expect(QuickAddParser.suggestions(for: "wo", in: projects).map(\.name) == ["Work", "Work Admin"])
        #expect(QuickAddParser.suggestions(for: "Work buy", in: projects).isEmpty)
    }

    @Test func completionReplacesPartialToken() {
        let completed = QuickAddParser.complete("Buy milk #ho", with: projects[3])
        #expect(completed == "Buy milk #Home ")
        #expect(QuickAddParser.parse(completed, projects: projects).projectID == 4)
    }
}
