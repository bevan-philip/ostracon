import Foundation
import Network

/// MCP's stdio transport: one JSON-RPC message per line on stdin, replies on stdout, logs on stderr.
@MainActor
enum StdioTransport {
    static func run(_ server: MCPServer) {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let response = server.handle(Data(line.utf8)) else { continue }
            FileHandle.standardOutput.write(response.encoded() + Data("\n".utf8))
        }
    }
}

/// MCP's Streamable HTTP transport, reduced to what a stateless server needs: POST a message, get JSON back.
///
/// Listens on the loopback interface only and rejects requests whose Host or Origin isn't local,
/// so web pages can't reach it through DNS rebinding. There is no other authentication.
@MainActor
final class HTTPTransport {
    private let server: MCPServer
    private let listener: NWListener
    private static let maximumRequestSize = 4 * 1024 * 1024

    init(server: MCPServer, port: UInt16) throws {
        self.server = server
        guard let port = NWEndpoint.Port(rawValue: port) else { throw ToolError("Invalid port \(port).") }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    func start(onReady: @escaping @MainActor () -> Void) {
        listener.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                switch state {
                case .ready: onReady()
                case .failed(let error):
                    log("Couldn't listen: \(error)")
                    exit(1)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { self.accept(connection) }
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(parsing: buffer) {
                    self.respond(to: request, on: connection)
                } else if error != nil || isComplete || buffer.count > Self.maximumRequestSize {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let response: HTTPResponse
        if !Self.isLocal(request.headers["host"]) || (request.headers["origin"].map { !Self.isLocal($0) } ?? false) {
            response = HTTPResponse(status: 403, reason: "Forbidden", body: Data("Only local requests are accepted.".utf8))
        } else if request.path != "/mcp" {
            response = HTTPResponse(status: 404, reason: "Not Found", body: Data("MCP is served at /mcp.".utf8))
        } else if request.method != "POST" {
            // No server-initiated stream and no sessions to end.
            response = HTTPResponse(status: 405, reason: "Method Not Allowed", headers: ["Allow": "POST"])
        } else if let reply = server.handle(request.body) {
            response = HTTPResponse(status: 200, reason: "OK", headers: ["Content-Type": "application/json"], body: reply.encoded())
        } else {
            response = HTTPResponse(status: 202, reason: "Accepted")
        }
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// `localhost`, `127.0.0.1` or `[::1]`, with or without a scheme and port.
    private static func isLocal(_ value: String?) -> Bool {
        guard var host = value?.lowercased() else { return false }
        if let range = host.range(of: "://") { host = String(host[range.upperBound...]) }
        if host.hasPrefix("[") {
            host = String(host.prefix { $0 != "]" }) + "]"
        } else if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        return ["localhost", "127.0.0.1", "[::1]"].contains(host)
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    /// `nil` until the head and the whole `Content-Length` body have arrived.
    init?(parsing data: Data) {
        guard let headEnd = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headEnd.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1].prefix { $0 != "?" })
        headers = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap { Int($0) } ?? 0
        let bodyStart = headEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        body = data[bodyStart..<(bodyStart + length)]
    }
}

private struct HTTPResponse {
    var status: Int
    var reason: String
    var headers: [String: String] = [:]
    var body = Data()

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("ostracon-mcp: \(message)\n".utf8))
}
