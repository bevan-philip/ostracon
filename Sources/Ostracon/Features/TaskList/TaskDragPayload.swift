import CoreTransferable
import UniformTypeIdentifiers

/// Tasks being dragged, such as onto a project in the sidebar.
struct TaskDragPayload: Codable, Transferable {
    /// In outline order, so the tasks arrive in the order they left.
    var taskIDs: [Int64]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ostraconTasks)
    }
}

extension UTType {
    /// Private to the app, so text dragged in from elsewhere is never mistaken for tasks.
    /// Declared in Info.plist by `scripts/build-app.sh`.
    static let ostraconTasks = UTType(exportedAs: "uk.bphilip.ostracon.tasks")
}
