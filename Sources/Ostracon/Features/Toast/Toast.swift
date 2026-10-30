import Foundation

/// A transient message shown at the bottom of the window, optionally offering to undo.
struct Toast: Identifiable, Equatable {
    enum UndoAction: Equatable {
        case reopen(taskIDs: [Int64])
    }

    let id = UUID()
    var message: String
    var undo: UndoAction?
}
