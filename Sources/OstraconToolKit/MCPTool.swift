import Foundation

/// One callable tool: its advertised definition and what it does. The MCP server and the CLI share these.
public struct MCPTool {
    public var name: String
    public var title: String
    public var description: String
    public var properties: [String: JSONValue] = [:]
    public var required: [String] = []
    public var readOnly = false
    public var destructive = false
    /// Does the work, throwing `ToolError` for anything the caller should fix.
    public var run: (ToolArguments) throws -> JSONValue

    public var definition: JSONValue {
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
    public func call(_ arguments: JSONValue) -> JSONValue {
        do {
            guard case .object(let values) = arguments else { throw ToolError("Arguments must be an object.") }
            let output = try run(ToolArguments(values: values))
            return ["content": [["type": "text", "text": .string(output.prettyString())]], "isError": false]
        } catch {
            return ["content": [["type": "text", "text": .string(error.localizedDescription)]], "isError": true]
        }
    }
}

public struct ToolError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Typed access to a tool call's arguments.
public struct ToolArguments {
    public var values: [String: JSONValue]

    public init(values: [String: JSONValue]) { self.values = values }

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
