/// A top-level task and everything shown beneath it — subtasks, and the composer if it is among them —
/// drawn together as one card.
struct TaskCardGroup: Identifiable, Equatable {
    /// Named after the top-level task, so the card keeps its identity while that task is being edited.
    let id: String
    var items: [TaskListItem]

    /// The composer adding a top-level task is a card of its own, so it isn't wrapped in another.
    var isStandaloneComposer: Bool {
        if items.count == 1, case .composer = items[0] {
            return true
        }
        return false
    }
}
