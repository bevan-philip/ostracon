import Foundation
import OstraconCore

// ostracon-cli: Ostracon's projects and tasks from the shell, through the same tools as ostracon-mcp.
// Run it with --help for the commands. Set OSTRACON_DATABASE to use a different database, as with the app.

let program = URL(fileURLWithPath: CommandLine.arguments.first ?? "ostracon-cli").lastPathComponent

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("\(program): \(message)\n".utf8))
    exit(status)
}

let repository: TaskRepository
do {
    repository = try TaskRepository.openDefault()
} catch {
    fail("Couldn't open the Ostracon database: \(error.localizedDescription)", status: 1)
}

// Deletions ask first when someone is at the keyboard; scripts pass --yes.
let askOnTerminal: (String) -> Bool = { question in
    FileHandle.standardError.write(Data("\(question) [y/N] ".utf8))
    return ["y", "yes"].contains(readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "")
}
let cli = CommandLineInterface(
    repository: repository,
    program: program,
    confirm: isatty(STDIN_FILENO) != 0 ? askOnTerminal : nil
)

do {
    print(try cli.run(Array(CommandLine.arguments.dropFirst())))
} catch let error as CLIError {
    fail(error.message, status: error.exitCode)
} catch {
    fail(error.localizedDescription, status: 1)
}
