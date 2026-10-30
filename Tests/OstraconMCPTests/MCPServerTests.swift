import Foundation
@testable import OstraconMCP
import OstraconCore
import Testing

@MainActor
struct MCPServerTests {
    let repository: TaskRepository
    let server: MCPServer
    let inbox: Project
    /// Friday 30 October 2026, 10:00 local time.
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))!

    init() throws {
        repository = try TaskRepository.inMemory()
        inbox = try repository.inbox()
        let now = now
        server = MCPServer(tools: OstraconTools.all(repository: repository, now: { now }))
    }

    private func request(_ method: String, _ params: JSONValue = [:]) -> JSONValue? {
        server.handle(["jsonrpc": "2.0", "id": 1, "method": .string(method), "params": params])
    }

    /// Calls a tool, returning its JSON output and whether it reported an error.
    private func call(_ name: String, _ arguments: JSONValue = [:]) throws -> (output: JSONValue?, isError: Bool) {
        let result = try #require(request("tools/call", ["name": .string(name), "arguments": arguments])?["result"])
        let text = try #require(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        return (try? JSONValue.decode(Data(text.utf8)), result["isError"] == true)
    }

    private func output(_ name: String, _ arguments: JSONValue = [:]) throws -> JSONValue {
        let (output, isError) = try call(name, arguments)
        #expect(!isError)
        return try #require(output)
    }

    @Test func initializeNegotiatesProtocolVersion() {
        let supported = request("initialize", ["protocolVersion": "2025-06-18"])?["result"]
        #expect(supported?["protocolVersion"] == "2025-06-18")
        #expect(supported?["capabilities"]?["tools"] != nil)

        let unknown = request("initialize", ["protocolVersion": "1999-01-01"])?["result"]
        #expect(unknown?["protocolVersion"] == .string(MCPServer.supportedProtocolVersions[0]))
    }

    @Test func notificationsGetNoReply() {
        #expect(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
    }

    @Test func protocolErrors() {
        #expect(request("nope")?["error"]?["code"] == -32601)
        #expect(request("tools/call", ["name": "nope"])?["error"]?["code"] == -32602)
        #expect(server.handle(Data("not json".utf8))?["error"]?["code"] == -32700)
    }

    @Test func listsEveryToolWithASchema() throws {
        let tools = try #require(request("tools/list")?["result"]?["tools"]?.arrayValue)
        #expect(tools.count == 10)
        for tool in tools {
            #expect(tool["inputSchema"]?["type"] == "object")
            #expect(tool["description"]?.stringValue?.isEmpty == false)
        }
        let deleteTask = try #require(tools.first { $0["name"] == "delete_task" })
        #expect(deleteTask["annotations"]?["destructiveHint"] == true)
    }

    @Test func addTaskReadsQuickAddSyntax() throws {
        try repository.createProject(name: "Work Admin", color: .red)
        let task = try output("add_task", ["content": "File expenses tomorrow 5pm #Work Admin !30min"])
        #expect(task["content"] == "File expenses")
        #expect(task["project"] == "Work Admin")
        #expect(task["due"] == "2026-10-31T17:00")
        #expect(task["reminders"] == [["minutes_before_due": 30]])
    }

    @Test func addTaskCanKeepContentLiteral() throws {
        let task = try output("add_task", ["content": "Plan Monday #standup", "quick_add": false, "due": "2026-11-02"])
        #expect(task["content"] == "Plan Monday #standup")
        #expect(task["project_id"] == .number(Double(inbox.id)))
        #expect(task["due"] == "2026-11-02")
    }

    @Test func subtasksJoinTheirParentsProject() throws {
        let project = try repository.createProject(name: "Home", color: .green)
        let parent = try repository.addTask(content: "Move house", projectID: project.id)
        let child = try output("add_task", ["content": "Book van", "parent_id": .number(Double(parent.id))])
        #expect(child["project_id"] == .number(Double(project.id)))
        #expect(child["parent_id"] == .number(Double(parent.id)))

        let (_, isError) = try call("add_task", [
            "content": "Misfiled", "parent_id": .number(Double(parent.id)), "project_id": .number(Double(inbox.id))
        ])
        #expect(isError)
    }

    @Test func updateTaskChangesOnlyWhatIsGiven() throws {
        let task = try repository.addTask(
            content: "Call mum", details: "About Sunday", projectID: inbox.id,
            dueDate: DueDate(year: 2026, month: 11, day: 1), reminders: [.before(minutes: 10)]
        )
        let id = JSONValue.number(Double(task.id))

        var updated = try output("update_task", ["id": id, "content": "Call mum back"])
        #expect(updated["details"] == "About Sunday")
        #expect(updated["due"] == "2026-11-01")

        updated = try output("update_task", ["id": id, "due": nil, "reminders": []])
        #expect(updated["due"] == .null)
        #expect(updated["reminders"] == [])

        let (message, isError) = try call("update_task", ["id": id, "due": "blursday"])
        #expect(isError)
        #expect(message == nil, "Errors are plain text for the model to read")
    }

    @Test func listTasksFiltersByDueDateAndCompletion() throws {
        let overdue = try repository.addTask(content: "Overdue", projectID: inbox.id, dueDate: DueDate(year: 2026, month: 10, day: 29))
        try repository.addTask(content: "Today", projectID: inbox.id, dueDate: DueDate(year: 2026, month: 10, day: 30))
        try repository.addTask(content: "Later", projectID: inbox.id, dueDate: DueDate(year: 2026, month: 12, day: 1))
        try repository.addTask(content: "Someday", projectID: inbox.id)
        let done = try repository.addTask(content: "Done", projectID: inbox.id, dueDate: DueDate(year: 2026, month: 10, day: 30))
        try repository.setCompleted(id: done.id, true)

        let today = try output("list_tasks", ["due_by": "today"])
        #expect(today["tasks"]?.arrayValue?.map { $0["content"] } == ["Overdue", "Today"])
        #expect(today["tasks"]?.arrayValue?.first?["overdue"] == true)

        let all = try output("list_tasks", ["include_completed": true])
        #expect(all["count"] == 5)

        let search = try output("list_tasks", ["search": "some"])
        #expect(search["tasks"]?.arrayValue?.map { $0["id"] } == [.number(Double(overdue.id + 3))])
    }

    @Test func completingAndReopening() throws {
        let parent = try repository.addTask(content: "Parent", projectID: inbox.id)
        let child = try repository.addTask(content: "Child", projectID: inbox.id, parentID: parent.id)

        let completed = try output("complete_task", ["id": .number(Double(parent.id))])
        #expect(completed["completed"] == true)
        #expect(try repository.task(id: child.id)?.isCompleted == true)

        _ = try output("complete_task", ["id": .number(Double(child.id)), "completed": false])
        #expect(try repository.task(id: parent.id)?.isCompleted == false, "Reopening a subtask reopens its parent")
    }

    @Test func inboxCannotBeChangedOrDeleted() throws {
        #expect(try call("delete_project", ["id": .number(Double(inbox.id))]).isError)
        #expect(try call("update_project", ["id": .number(Double(inbox.id)), "name": "Elsewhere"]).isError)
        #expect(try repository.inbox().name == "Inbox")
    }

    @Test func projectsCanBeCreatedAndDeleted() throws {
        let created = try output("add_project", ["name": "Garden", "color": "limeGreen"])
        #expect(created["color"] == "limeGreen")
        #expect(try call("add_project", ["name": "Bad", "color": "plaid"]).isError)

        let id = try #require(created["id"])
        try repository.addTask(content: "Weed", projectID: try #require(id.int64Value))
        let deleted = try output("delete_project", ["id": id])
        #expect(deleted["tasks_deleted"] == 1)
        #expect(try repository.projects().map(\.name) == ["Inbox"])
    }
}
