import Foundation
import OstraconCore
import OstraconToolKit

/// Ostracon's MCP tools as shell commands. Each command turns its arguments into one tool's,
/// then prints what the tool returns readably, or as the tool's own JSON with --json.
@MainActor
struct CommandLineInterface {
    let repository: TaskRepository
    let program: String
    let now: () -> Date
    /// Asks a yes/no question before deleting anything, unless --yes was given. `nil` when there's no one to ask.
    let confirm: ((String) -> Bool)?
    private let tools: [String: MCPTool]

    init(
        repository: TaskRepository,
        program: String = "ostracon-cli",
        now: @escaping () -> Date = { .now },
        confirm: ((String) -> Bool)?
    ) {
        self.repository = repository
        self.program = program
        self.now = now
        self.confirm = confirm
        tools = Dictionary(uniqueKeysWithValues: OstraconTools.all(repository: repository, now: now).map { ($0.name, $0) })
    }

    /// Runs one command line (without the program name), returning what to print.
    func run(_ arguments: [String]) throws -> String {
        // --json and --help work anywhere before a "--".
        let end = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let json = arguments[..<end].contains("--json")
        let help = arguments[..<end].contains { $0 == "--help" || $0 == "-h" }
        let arguments = arguments[..<end].filter { !["--json", "--help", "-h"].contains($0) } + arguments[end...]

        guard let command = arguments.first, command != "help", !help else { return usage }
        let (output, render) = try perform(command, Array(arguments.dropFirst()))
        return json ? output.prettyString() : render(output)
    }

    private typealias Result = (output: JSONValue, render: (JSONValue) -> String)

    private func perform(_ command: String, _ arguments: [String]) throws -> Result {
        let printer = TaskPrinter(now: now())
        switch command {
        case "projects":
            try ParsedArguments(arguments).expectPositionals(0)
            return (try call("list_projects"), printer.projects)

        case "list", "ls":
            let parsed = try ParsedArguments(arguments, options: ["--project", "--search", "--due-by"], flags: ["--today", "--all"])
            try parsed.expectPositionals(0)
            if parsed.has("--today"), parsed.value("--due-by") != nil { throw CLIError.usage("Use --today or --due-by, not both.") }
            var values: [String: JSONValue] = ["include_completed": .bool(parsed.has("--all"))]
            if let project = parsed.value("--project") { values["project_id"] = try projectID(project) }
            if let search = parsed.value("--search") { values["search"] = .string(search) }
            if let dueBy = parsed.has("--today") ? "today" : parsed.value("--due-by") { values["due_by"] = .string(dueBy) }
            let grouped = values["project_id"] == nil
            return (try call("list_tasks", values), { printer.tasks($0, showingProjects: grouped) })

        case "show":
            let parsed = try ParsedArguments(arguments)
            try parsed.expectPositionals(1)
            return (try call("get_task", ["id": try id(parsed.positionals[0])]), printer.detail)

        case "add":
            let parsed = try ParsedArguments(
                arguments, options: ["--project", "--parent", "--due", "--remind", "--details"], flags: ["--literal"]
            )
            let content = parsed.positionals.joined(separator: " ")
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { throw CLIError.usage("add needs the task's text.") }
            var values: [String: JSONValue] = ["content": .string(content), "quick_add": .bool(!parsed.has("--literal"))]
            if let project = parsed.value("--project") { values["project_id"] = try projectID(project) }
            if let parent = parsed.value("--parent") { values["parent_id"] = try id(parent) }
            if let due = parsed.value("--due") { values["due"] = .string(due) }
            if !parsed.all("--remind").isEmpty { values["reminders"] = .array(parsed.all("--remind").map(JSONValue.string)) }
            if let details = parsed.value("--details") { values["details"] = .string(details) }
            return (try call("add_task", values), { "Added " + printer.line($0, showingProject: true) })

        case "edit":
            let parsed = try ParsedArguments(
                arguments, options: ["--content", "--details", "--due", "--remind", "--project"], flags: ["--no-due", "--no-reminders"]
            )
            try parsed.expectPositionals(1)
            if parsed.has("--no-due"), parsed.value("--due") != nil { throw CLIError.usage("Use --due or --no-due, not both.") }
            if parsed.has("--no-reminders"), !parsed.all("--remind").isEmpty {
                throw CLIError.usage("Use --remind or --no-reminders, not both.")
            }
            var values: [String: JSONValue] = ["id": try id(parsed.positionals[0])]
            if let content = parsed.value("--content") { values["content"] = .string(content) }
            if let details = parsed.value("--details") { values["details"] = .string(details) }
            if let due = parsed.value("--due") { values["due"] = .string(due) }
            if parsed.has("--no-due") { values["due"] = .null }
            if !parsed.all("--remind").isEmpty { values["reminders"] = .array(parsed.all("--remind").map(JSONValue.string)) }
            if parsed.has("--no-reminders") { values["reminders"] = [] }
            if let project = parsed.value("--project") { values["project_id"] = try projectID(project) }
            guard values.count > 1 else { throw CLIError.usage("Nothing to change. See \(program) --help for edit's options.") }
            return (try call("update_task", values), { "Updated " + printer.line($0, showingProject: true) })

        case "done", "complete", "reopen":
            let parsed = try ParsedArguments(arguments)
            guard !parsed.positionals.isEmpty else { throw CLIError.usage("\(command) needs at least one task ID.") }
            let completed = command != "reopen"
            // Check every ID first so a typo doesn't leave the list half done.
            let ids = try parsed.positionals.map(id)
            for id in ids { _ = try call("get_task", ["id": id]) }
            let outputs = try ids.map { try call("complete_task", ["id": $0, "completed": .bool(completed)]) }
            let verb = completed ? "Completed " : "Reopened "
            return (outputs.count == 1 ? outputs[0] : .array(outputs), { _ in
                outputs.map { verb + printer.line($0, showingProject: true) }.joined(separator: "\n")
            })

        case "delete", "rm":
            let parsed = try ParsedArguments(arguments, flags: ["--yes"])
            try parsed.expectPositionals(1)
            let id = try id(parsed.positionals[0])
            let task = try call("get_task", ["id": id])
            let subtasks = task["subtask_count"]?.int64Value ?? 0
            let what = "task \(id.int64Value ?? 0) \"\(task["content"]?.stringValue ?? "")\""
                + (subtasks > 0 ? " and its \(subtasks) subtask\(subtasks == 1 ? "" : "s")" : "")
            try confirm("Delete \(what)?", skip: parsed.has("--yes"))
            return (try call("delete_task", ["id": id]), { _ in "Deleted \(what)." })

        case "project":
            guard let subcommand = arguments.first else { throw CLIError.usage("project needs add, edit or delete.") }
            return try performProject(subcommand, Array(arguments.dropFirst()), printer: printer)

        default:
            throw CLIError.usage("Unknown command \"\(command)\". Run \(program) --help to see the commands.")
        }
    }

    private func performProject(_ subcommand: String, _ arguments: [String], printer: TaskPrinter) throws -> Result {
        switch subcommand {
        case "add":
            let parsed = try ParsedArguments(arguments, options: ["--color"])
            let name = parsed.positionals.joined(separator: " ")
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CLIError.usage("project add needs a name.") }
            var values: [String: JSONValue] = ["name": .string(name)]
            if let color = parsed.value("--color") { values["color"] = .string(colorName(color)) }
            return (try call("add_project", values), { "Added project " + printer.project($0) })

        case "edit":
            let parsed = try ParsedArguments(arguments, options: ["--name", "--color"])
            var values: [String: JSONValue] = ["id": try projectID(parsed.positionals.joined(separator: " "))]
            if let name = parsed.value("--name") { values["name"] = .string(name) }
            if let color = parsed.value("--color") { values["color"] = .string(colorName(color)) }
            guard values.count > 1 else { throw CLIError.usage("Nothing to change. Pass --name or --color.") }
            return (try call("update_project", values), { "Updated project " + printer.project($0) })

        case "delete", "rm":
            let parsed = try ParsedArguments(arguments, flags: ["--yes"])
            let id = try projectID(parsed.positionals.joined(separator: " "))
            let project = try repository.projects().first { $0.id == id.int64Value }
            if let project, !project.isInbox {
                let tasks = try repository.tasks().count { $0.projectID == project.id }
                try confirm(
                    "Delete project \"\(project.name)\"" + (tasks > 0 ? " and its \(tasks) task\(tasks == 1 ? "" : "s")?" : "?"),
                    skip: parsed.has("--yes")
                )
            }
            return (try call("delete_project", ["id": id]), { output in
                let tasks = output["tasks_deleted"]?.int64Value ?? 0
                return "Deleted project \"\(output["name"]?.stringValue ?? "")\""
                    + (tasks > 0 ? " and its \(tasks) task\(tasks == 1 ? "" : "s")." : ".")
            })

        default:
            throw CLIError.usage("Unknown project command \"\(subcommand)\". Use add, edit or delete.")
        }
    }

    // MARK: - Helpers

    private func call(_ name: String, _ values: [String: JSONValue] = [:]) throws -> JSONValue {
        guard let tool = tools[name] else { throw ToolError("No tool called \(name).") }
        return try tool.run(ToolArguments(values: values))
    }

    private func id(_ text: String) throws -> JSONValue {
        guard let id = Int64(text.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")) else {
            throw CLIError.usage("\"\(text)\" isn't a task ID.")
        }
        return .number(Double(id))
    }

    /// A project by ID or by name, ignoring case and a leading "#".
    private func projectID(_ text: String) throws -> JSONValue {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw CLIError.usage("Give a project's ID or name.") }
        if let id = Int64(text) { return .number(Double(id)) }
        let name = String(text.trimmingPrefix("#"))
        guard let project = try repository.projects().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ToolError("No project called \"\(name)\". Run \(program) projects to see them.")
        }
        return .number(Double(project.id))
    }

    /// Accepts "lime green", "Lime-Green" and the like for limeGreen; anything else goes to the tool to reject.
    private func colorName(_ text: String) -> String {
        let key = text.lowercased().filter(\.isLetter)
        return ProjectColor.allCases.first { $0.rawValue.lowercased() == key }?.rawValue ?? text
    }

    private func confirm(_ question: String, skip: Bool) throws {
        guard !skip else { return }
        guard let confirm else { throw CLIError.usage("Pass --yes to delete without being asked.") }
        guard confirm(question) else { throw CLIError(message: "Nothing deleted.", exitCode: 1) }
    }

    var usage: String {
        """
        Usage: \(program) <command> [options]

        Tasks
          list [--project P] [--search TEXT] [--due-by DATE | --today] [--all]
                List open tasks in outline order; --all includes completed ones
          show ID
                Show a task with its details, reminders and subtasks
          add TEXT... [--project P] [--parent ID] [--due DATE] [--remind R]... [--details TEXT] [--literal]
                Add a task, by default to the Inbox. TEXT may use quick-add syntax, as in
                \(program) add 'Pay rent tomorrow 9am #Home !1h'. --literal keeps it as typed
          edit ID [--content TEXT] [--details TEXT] [--due DATE | --no-due] [--remind R]... [--no-reminders] [--project P]
                Change a task; --remind replaces every reminder. Moving project moves its subtasks too
          done ID...
                Complete tasks along with their subtasks
          reopen ID...
                Reopen tasks, and any completed parents
          delete ID [--yes]
                Delete a task and its subtasks

        Projects
          projects
                List projects with their IDs and open task counts
          project add NAME... [--color C]
          project edit P [--name NAME] [--color C]
          project delete P [--yes]

        P is a project's ID or name. DATE is natural language such as "tomorrow 5pm", "next fri" or "in 3 days",
        or ISO "2026-01-27" / "2026-01-27T17:00". R is a reminder: "30min" before the due time, or "tomorrow 9am".
        C is one of: \(ProjectColor.allCases.map(\.rawValue).joined(separator: ", ")).
        Single-quote TEXT so the shell leaves # and ! alone.

        Options
          --json       Print the tool's JSON output instead of text
          -h, --help   Show this help
          Short forms: -p --project, -d --due, -r --remind, -a --all, -y --yes

        Set OSTRACON_DATABASE=/path.sqlite to use a database other than the app's.
        """
    }
}

struct CLIError: LocalizedError {
    var message: String
    var exitCode: Int32

    /// A mistake in how the command was typed (exit status 64, EX_USAGE).
    static func usage(_ message: String) -> CLIError { CLIError(message: message, exitCode: 64) }

    var errorDescription: String? { message }
}

/// A command's arguments after its name: positionals in order, plus options by their long name.
struct ParsedArguments {
    private static let shortForms = ["-p": "--project", "-d": "--due", "-r": "--remind", "-a": "--all", "-y": "--yes"]

    private(set) var positionals: [String] = []
    private var values: [String: [String]] = [:]
    private var flags: Set<String> = []

    /// `options` take a value (`--due friday` or `--due=friday`); `flags` don't. Everything after "--" is positional.
    init(_ arguments: [String], options: Set<String> = [], flags: Set<String> = []) throws {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--" {
                positionals += remaining
                break
            }
            guard argument.hasPrefix("-"), argument.count > 1 else {
                positionals.append(argument)
                continue
            }
            var name = argument
            var inlineValue: String?
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                name = String(argument[..<equals])
                inlineValue = String(argument[argument.index(after: equals)...])
            }
            name = Self.shortForms[name] ?? name
            if options.contains(name) {
                guard let value = inlineValue ?? remaining.popFirst() else { throw CLIError.usage("\(name) needs a value.") }
                values[name, default: []].append(value)
            } else if flags.contains(name), inlineValue == nil {
                self.flags.insert(name)
            } else {
                throw CLIError.usage("Unknown option \(argument).")
            }
        }
    }

    /// The option's last value, so a later one overrides an earlier one.
    func value(_ option: String) -> String? { values[option]?.last }
    func all(_ option: String) -> [String] { values[option] ?? [] }
    func has(_ flag: String) -> Bool { flags.contains(flag) }

    func expectPositionals(_ count: Int) throws {
        guard positionals.count != count else { return }
        if positionals.count > count {
            throw CLIError.usage("Unexpected \"\(positionals[count])\".")
        }
        throw CLIError.usage(count == 1 ? "Give one ID." : "Missing arguments.")
    }
}
