import Foundation

public enum RepositoryError: Error, LocalizedError {
    case missingInbox
    case emptyName
    case notADatabase(URL)

    public var errorDescription: String? {
        switch self {
        case .missingInbox: "The Inbox project is missing from the database."
        case .emptyName: "A name is required."
        case .notADatabase(let url): "\(url.lastPathComponent) isn't an Ostracon database."
        }
    }
}
