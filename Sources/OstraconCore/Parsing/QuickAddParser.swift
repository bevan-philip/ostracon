import Foundation

/// Parses Todoist-style quick-add text, where `#Project Name` files a task into a project,
/// and dates and `!reminders` are picked out by `DateParser`.
public enum QuickAddParser {
    /// Reads a whole piece of text as if it had been typed into the composer and submitted.
    /// Pass `dates: nil` to recognise projects only.
    public static func parse(_ text: String, projects: [Project], dates: DateParser? = DateParser()) -> QuickAddResult {
        var draft = QuickAddDraft(text: text)
        draft.convert(projects: projects, dates: dates, includingTrailing: true)
        return draft.result(dates: dates ?? DateParser())
    }

    /// `#Project` tokens naming an existing project, preferring the longest name, so "#Work Admin" beats "#Work".
    static func projectMatches(in text: String, projects: [Project]) -> [(range: Range<String.Index>, project: Project)] {
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
        return matches
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
