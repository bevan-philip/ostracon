import Foundation
import OstraconCore
import OstraconToolKit

// An MCP server for Ostracon's tasks, sharing the app's SQLite database.
//
//   ostracon-mcp                 stdio, for clients that launch the server themselves
//   ostracon-mcp --http [port]   HTTP on 127.0.0.1 (default port 8765), served at /mcp
//
// Neither transport is authenticated. Set OSTRACON_DATABASE to use a different database, as with the app.

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
        Usage: ostracon-mcp [--http [port]]

        Serves Ostracon's projects and tasks over the Model Context Protocol, without authentication.
        By default it speaks MCP over stdio. With --http it listens on http://127.0.0.1:<port>/mcp (default 8765).
        Set OSTRACON_DATABASE=/path.sqlite to use a database other than the app's.
        """)
    exit(0)
}

let repository: TaskRepository
do {
    repository = try TaskRepository.openDefault()
} catch {
    log("Couldn't open the Ostracon database: \(error.localizedDescription)")
    exit(1)
}

let server = MCPServer(tools: OstraconTools.all(repository: repository))

if let flag = arguments.firstIndex(of: "--http") {
    let portArgument = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : nil
    guard let port = UInt16(portArgument ?? "8765") else {
        log("Invalid port \(portArgument ?? "")")
        exit(64)
    }
    let transport: HTTPTransport
    do {
        transport = try HTTPTransport(server: server, port: port)
    } catch {
        log("Couldn't listen on port \(port): \(error.localizedDescription)")
        exit(1)
    }
    transport.start { log("Listening on http://127.0.0.1:\(port)/mcp (no authentication)") }
    dispatchMain()
} else {
    StdioTransport.run(server)
}
