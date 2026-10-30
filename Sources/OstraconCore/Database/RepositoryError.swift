import Foundation

public enum RepositoryError: Error, LocalizedError {
    case missingInbox
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .missingInbox: "The Inbox project is missing from the database."
        case .emptyName: "A name is required."
        }
    }
}
