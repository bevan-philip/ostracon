import OstraconCore

/// The state of the add/edit project sheet.
struct ProjectDraft: Identifiable, Equatable {
    /// `nil` when creating a new project.
    var projectID: Int64?
    var name: String
    var color: ProjectColor

    var id: String { projectID.map { "project-\($0)" } ?? "new-project" }
    var isNew: Bool { projectID == nil }

    static let new = ProjectDraft(projectID: nil, name: "", color: .charcoal)
}
