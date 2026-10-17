import Foundation

/// Builds deep links from session ids; ids that do not look like ids are refused.
enum DeepLink {
    private static var threadPattern: Regex<Substring> { /[A-Za-z0-9-]{1,64}/ }
    private static var localSessionPattern: Regex<Substring> { /local_[A-Za-z0-9-]{1,64}/ }

    static func codexThread(_ id: String) -> URL? {
        guard id.wholeMatch(of: threadPattern) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }

    static func claudeSession(local id: String) -> URL? {
        guard id.wholeMatch(of: localSessionPattern) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(id)")
    }

    static func isCLISessionID(_ id: String) -> Bool {
        id.wholeMatch(of: threadPattern) != nil
    }

    static func isLocalSessionID(_ id: String) -> Bool {
        id.wholeMatch(of: localSessionPattern) != nil
    }
}
