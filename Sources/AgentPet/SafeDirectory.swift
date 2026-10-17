import Foundation

/// Directories that are safe to paste into a shell command line and an AppleScript literal.
enum SafeDirectory {
    static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && path.rangeOfCharacter(from: .controlCharacters) == nil
    }
}
