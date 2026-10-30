import Foundation

/// What the inline task composer is doing.
enum ComposerMode: Hashable {
    /// Adding a new task, optionally as a subtask of `parentID`.
    case add(parentID: Int64?)
    /// Editing an existing task in place.
    case edit(taskID: Int64)
}
