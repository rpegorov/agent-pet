import Foundation

/// Quoting for text embedded in a shell command line and in an AppleScript string literal.
enum ScriptQuoting {
    static func shell(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A shell command line safe to place inside an AppleScript `do script "…"` literal.
    static func appleScriptShellCommand(_ command: String) -> String {
        "\"" + appleScript(command) + "\""
    }
}
