import Foundation

/// Maps a Claude Code CLI session id to the id the Claude desktop app uses in its deep links.
enum ClaudeDesktopSessions {
    private static let sessionsPath = "Library/Application Support/Claude/claude-code-sessions"
    private static let filePrefix = "local_"

    static func localSessionID(forCLISession cliSession: String) -> String? {
        guard DeepLink.isCLISessionID(cliSession) else { return nil }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(sessionsPath)
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        let needle = Data(cliSession.utf8)
        for case let file as URL in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix(filePrefix) {
            if let local = localID(in: file, matching: cliSession, needle: needle) { return local }
        }
        return nil
    }

    private static func localID(in file: URL, matching cliSession: String, needle: Data) -> String? {
        do {
            let data = try Data(contentsOf: file)
            guard data.range(of: needle) != nil,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["cliSessionId"] as? String == cliSession,
                  object["isArchived"] as? Bool != true,
                  let local = object["sessionId"] as? String,
                  DeepLink.isLocalSessionID(local) else { return nil }
            return local
        } catch {
            NSLog("agent-pet: could not read \(file.lastPathComponent): \(error)")
            return nil
        }
    }
}
