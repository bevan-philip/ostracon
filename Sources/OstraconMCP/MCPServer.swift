import Foundation
import OstraconToolKit

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
