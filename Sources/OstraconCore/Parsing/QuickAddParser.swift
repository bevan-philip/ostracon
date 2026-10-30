import Foundation

/// Parses Todoist-style quick-add text, where `#Project Name` files a task into a project.
public enum QuickAddParser {
    /// Strips any `#Project` tokens that name an existing project.
    /// If several are present, the last one wins.
    public static func parse(_ text: String, projects: [Project]) -> QuickAddResult {
        // Longest names first, so "#Work Admin" beats "#Work".
        let candidates = projects.sorted { $0.name.count > $1.name.count }
        var matches: [(range: Range<String.Index>, project: Project)] = []

        for hashIndex in hashTokenStarts(in: text) {
            let nameStart = text.index(after: hashIndex)
            let remainder = text[nameStart...]
            for project in candidates where remainder.count >= project.name.count {
                let nameEnd = remainder.index(nameStart, offsetBy: project.name.count)
                let isWholeToken = nameEnd == text.endIndex || text[nameEnd].isWhitespace
                if isWholeToken, text[nameStart..<nameEnd].caseInsensitiveCompare(project.name) == .orderedSame {
                    matches.append((hashIndex..<nameEnd, project))
                    break
                }
            }
        }

        var content = text
        for match in matches.reversed() {
            content.removeSubrange(match.range)
        }
        let normalised = content.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return QuickAddResult(content: normalised, projectID: matches.last?.project.id)
    }

    /// The partial project name being typed after a trailing `#`, if any, used to drive autocomplete.
    public static func activeProjectQuery(in text: String) -> String? {
        guard let hashIndex = hashTokenStarts(in: text).last else { return nil }
        let query = String(text[text.index(after: hashIndex)...])
        return query.contains(where: \.isNewline) ? nil : query
    }

    /// Projects matching a partially typed name, best matches first.
    public static func suggestions(for query: String, in projects: [Project]) -> [Project] {
        guard !query.isEmpty else { return projects }
        let matching = projects.filter { $0.name.localizedStandardContains(query) }
        let prefixed = matching.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
        return prefixed + matching.filter { !prefixed.contains($0) }
    }

    /// Replaces the trailing `#query` with the full project name and a following space.
    public static func complete(_ text: String, with project: Project) -> String {
        guard let hashIndex = hashTokenStarts(in: text).last else { return text }
        return String(text[..<hashIndex]) + "#\(project.name) "
    }

    /// Positions of `#` characters that begin a token, i.e. at the start or after whitespace.
    private static func hashTokenStarts(in text: String) -> [String.Index] {
        text.indices.filter { index in
            text[index] == "#" && (index == text.startIndex || text[text.index(before: index)].isWhitespace)
        }
    }
}
