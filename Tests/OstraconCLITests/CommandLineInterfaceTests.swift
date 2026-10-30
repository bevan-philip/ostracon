import Foundation
@testable import OstraconCLI
import OstraconCore
import OstraconToolKit
import Testing

@MainActor
struct CommandLineInterfaceTests {
    let repository: TaskRepository
    let inbox: Project
    /// Friday 30 October 2026, 10:00 local time.
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))!

    init() throws {
        repository = try TaskRepository.inMemory()
        inbox = try repository.inbox()
    }

    private func cli(confirming answer: Bool? = nil) -> CommandLineInterface {
        let now = now
        return CommandLineInterface(repository: repository, now: { now }, confirm: answer.map { answer in { _ in answer } })
    }

    private func run(_ arguments: String..., confirming answer: Bool? = nil) throws -> String {
        try cli(confirming: answer).run(arguments)
    }

    private func json(_ arguments: String...) throws -> JSONValue {
        try JSONValue.decode(Data(try cli().run(arguments + ["--json"]).utf8))
    }

    private func usageError(_ arguments: String...) -> Bool {
        do {
            _ = try cli().run(arguments)
            return false
        } catch let error as CLIError {
            return error.exitCode == 64
        } catch {
            return false
        }
    }

    @Test func helpListsTheCommands() throws {
        for arguments in [[], ["--help"], ["help"], ["add", "-h"]] {
            let help = try cli().run(arguments)
            #expect(help.hasPrefix("Usage: ostracon-cli"))
            #expect(help.contains("project delete"))
        }
    }

    @Test func addReadsQuickAddSyntaxAndFlags() throws {
        try repository.createProject(name: "Work Admin", color: .red)
        let task = try json("add", "File expenses tomorrow 5pm #Work Admin !30min")
        #expect(task["content"] == "File expenses")
        #expect(task["project"] == "Work Admin")
        #expect(task["due"] == "2026-10-31T17:00")
        #expect(task["reminders"] == [["minutes_before_due": 30]])

        let literal = try json("add", "Plan", "Monday", "#standup", "--literal", "-p", "work admin", "--due=2026-11-02", "-r", "1h")
        #expect(literal["content"] == "Plan Monday #standup")
        #expect(literal["project"] == "Work Admin")
        #expect(literal["due"] == "2026-11-02")
        #expect(literal["reminders"] == [["minutes_before_due": 60]])

        let text = try run("add", "--", "-dash first")
        #expect(text.hasPrefix("Added 3  [ ] -dash first"))
    }

    @Test func listGroupsByProjectAndFilters() throws {
        let home = try repository.createProject(name: "Home", color: .green)
        let parent = try repository.addTask(content: "Move house", projectID: home.id, dueDate: DueDate(year: 2026, month: 10, day: 29))
        try repository.addTask(content: "Book van", projectID: home.id, parentID: parent.id)
        try repository.addTask(content: "Someday", projectID: inbox.id)

        #expect(try run("list") == """
            Inbox
            3  [ ] Someday

            Home
            1  [ ] Move house  due yesterday, overdue · 0/1 subtasks
            2    [ ] Book van
            """)
        #expect(try run("list", "--project", "Home").hasPrefix("1  [ ] Move house"))
        #expect(try json("list", "--today")["count"] == 1)
        #expect(try json("list", "--search", "van")["count"] == 1)
        #expect(try run("list", "--search", "nothing") == "No tasks.")
        #expect(usageError("list", "--today", "--due-by", "friday"))
    }

    @Test func showIncludesRemindersDetailsAndSubtasks() throws {
        let parent = try repository.addTask(
            content: "Call mum", details: "About Sunday", projectID: inbox.id,
            dueDate: DueDate(year: 2026, month: 10, day: 31), reminders: [.before(minutes: 120)]
        )
        try repository.addTask(content: "Find number", projectID: inbox.id, parentID: parent.id)

        let text = try run("show", "1")
        #expect(text.hasPrefix("[ ] Call mum\nID 1 · #Inbox · due tomorrow\nReminders: 2 hours before\n\nAbout Sunday"))
        #expect(text.hasSuffix("Subtasks:\n  2  [ ] Find number"))
    }

    @Test func editChangesOnlyWhatIsGiven() throws {
        try repository.addTask(
            content: "Call mum", details: "About Sunday", projectID: inbox.id,
            dueDate: DueDate(year: 2026, month: 11, day: 1), reminders: [.before(minutes: 10)]
        )
        var task = try json("edit", "1", "--content", "Call mum back")
        #expect(task["details"] == "About Sunday")
        #expect(task["due"] == "2026-11-01")

        task = try json("edit", "1", "--no-due", "--no-reminders")
        #expect(task["due"] == .null)
        #expect(task["reminders"] == [])

        #expect(usageError("edit", "1"))
        #expect(usageError("edit", "1", "--due", "friday", "--no-due"))
        #expect(throws: ToolError.self) { try run("edit", "1", "--due", "blursday") }
    }

    @Test func doneAndReopenCheckEveryIDFirst() throws {
        let first = try repository.addTask(content: "First", projectID: inbox.id)
        let second = try repository.addTask(content: "Second", projectID: inbox.id)

        #expect(throws: ToolError.self) { try run("done", "1", "99") }
        #expect(try repository.task(id: first.id)?.isCompleted == false)

        #expect(try run("done", "1", "2") == "Completed 1  [x] First  #Inbox\nCompleted 2  [x] Second  #Inbox")
        _ = try run("reopen", "#2")
        #expect(try repository.task(id: second.id)?.isCompleted == false)
    }

    @Test func deleteAsksUnlessToldYes() throws {
        try repository.addTask(content: "Keep", projectID: inbox.id)

        #expect(usageError("delete", "1"), "No one to ask, so --yes is required")
        #expect(throws: CLIError.self) { try run("delete", "1", confirming: false) }
        #expect(try repository.task(id: 1) != nil)

        #expect(try run("delete", "1", confirming: true) == "Deleted task 1 \"Keep\".")
        #expect(try repository.task(id: 1) == nil)
    }

    @Test func projectsByNameOrID() throws {
        #expect(try run("project", "add", "Garden", "Jobs", "--color", "Lime Green") == "Added project 2 Garden Jobs (limeGreen)")
        #expect(try run("project", "edit", "garden jobs", "--name", "Garden") == "Updated project 2 Garden (limeGreen)")
        try repository.addTask(content: "Weed", projectID: 2)

        #expect(try run("projects") == "1  Inbox   0 open\n2  Garden  1 open")
        #expect(throws: ToolError.self) { try run("project", "delete", "Inbox", "--yes") }
        #expect(throws: ToolError.self) { try run("list", "--project", "Allotment") }
        #expect(try run("project", "delete", "2", "-y") == "Deleted project \"Garden\" and its 1 task.")
    }

    @Test func rejectsUnknownCommandsAndOptions() {
        #expect(usageError("bogus"))
        #expect(usageError("list", "--nope"))
        #expect(usageError("show"))
        #expect(usageError("show", "abc"))
        #expect(usageError("add", "--due"))
    }
}
