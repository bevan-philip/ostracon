import Foundation

/// Answers MCP's JSON-RPC requests. Transport-agnostic: stdio and HTTP both hand it decoded messages.
///
/// There is no authentication: anything that can reach the transport can read and change every task.
@MainActor
final class MCPServer {
    static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let tools: [String: MCPTool]
    private let toolOrder: [String]

    init(tools: [MCPTool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        toolOrder = tools.map(\.name)
    }

    /// Handles one message or a batch. Returns `nil` when nothing should be sent back (notifications).
    func handle(_ message: JSONValue) -> JSONValue? {
        if let batch = message.arrayValue {
            let responses = batch.compactMap(handleSingle)
            return responses.isEmpty ? nil : .array(responses)
        }
        return handleSingle(message)
    }

    /// Handles raw bytes, replying with a parse error when they aren't JSON.
    func handle(_ data: Data) -> JSONValue? {
        guard let message = try? JSONValue.decode(data) else {
            return Self.error(id: .null, code: -32700, message: "Parse error")
        }
        return handle(message)
    }

    private func handleSingle(_ message: JSONValue) -> JSONValue? {
        guard case .object = message, let method = message["method"]?.stringValue else {
            // A response to something we sent (we send nothing), or junk.
            return message["id"] == nil ? nil : Self.error(id: message["id"] ?? .null, code: -32600, message: "Invalid request")
        }
        guard let id = message["id"] else { return nil } // A notification, such as notifications/initialized.

        let params = message["params"] ?? [:]
        switch method {
        case "initialize":
            return Self.result(id: id, initialize(params))
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(toolOrder.compactMap { tools[$0]?.definition })])
        case "tools/call":
            guard let name = params["name"]?.stringValue, let tool = tools[name] else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(params["name"]?.stringValue ?? "(none)")")
            }
            return Self.result(id: id, tool.call(params["arguments"] ?? [:]))
        case "resources/list":
            return Self.result(id: id, ["resources": []])
        case "prompts/list":
            return Self.result(id: id, ["prompts": []])
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func initialize(_ params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue ?? ""
        let version = Self.supportedProtocolVersions.contains(requested) ? requested : Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "ostracon", "title": "Ostracon", "version": "1.0.0"],
            "instructions": """
                Ostracon is the user's task manager. Every task belongs to a project; the Inbox always exists. \
                Tasks can have subtasks (parent_id), a due date and reminders. Dates accept natural language \
                such as "tomorrow 5pm", "next fri" or "jan 27", or ISO "2026-01-27" / "2026-01-27T17:00", \
                read in the user's local time zone. Completing a task also completes its subtasks.
                """
        ]
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}

/// One callable tool: its advertised definition and what it does.
struct MCPTool {
    var name: String
    var title: String
    var description: String
    var properties: [String: JSONValue] = [:]
    var required: [String] = []
    var readOnly = false
    var destructive = false
    var run: (ToolArguments) throws -> JSONValue

    var definition: JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
                "additionalProperties": false
            ],
            "annotations": [
                "title": .string(title),
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(readOnly),
                "openWorldHint": false
            ]
        ]
    }

    /// Runs the tool. Failures are reported as tool errors so the model can see and correct them.
    func call(_ arguments: JSONValue) -> JSONValue {
        do {
            guard case .object(let values) = arguments else { throw ToolError("Arguments must be an object.") }
            let output = try run(ToolArguments(values: values))
            return ["content": [["type": "text", "text": .string(output.prettyString())]], "isError": false]
        } catch {
            return ["content": [["type": "text", "text": .string(error.localizedDescription)]], "isError": true]
        }
    }
}

struct ToolError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Typed access to a tool call's arguments.
struct ToolArguments {
    var values: [String: JSONValue]

    /// `true` when the key was sent, even as `null` (which some tools read as "clear this").
    func has(_ key: String) -> Bool { values[key] != nil }

    func string(_ key: String) throws -> String? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let string = value.stringValue else { throw ToolError("\(key) must be a string.") }
        return string
    }

    func requiredString(_ key: String) throws -> String {
        guard let string = try string(key) else { throw ToolError("\(key) is required.") }
        return string
    }

    func id(_ key: String) throws -> Int64? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let id = value.int64Value else { throw ToolError("\(key) must be an integer ID.") }
        return id
    }

    func requiredID(_ key: String) throws -> Int64 {
        guard let id = try id(key) else { throw ToolError("\(key) is required.") }
        return id
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let bool = value.boolValue else { throw ToolError("\(key) must be true or false.") }
        return bool
    }

    func strings(_ key: String) throws -> [String]? {
        guard let value = values[key], !value.isNull else { return nil }
        guard let array = value.arrayValue else { throw ToolError("\(key) must be an array of strings.") }
        return try array.map {
            guard let string = $0.stringValue else { throw ToolError("\(key) must be an array of strings.") }
            return string
        }
    }
}
