import Foundation

/// Brings the terminal tab that owns a tty to the front, for terminals that script it.
enum TerminalTabSelector {
    static let terminalBundleID = "com.apple.Terminal"
    static let iTermBundleID = "com.googlecode.iterm2"
    private static let devicePrefix = "/dev/"

    /// Selects the tab, then calls `completion` on the main actor whether or not a tab matched.
    static func select(tty: String, in bundleID: String, completion: @escaping @MainActor @Sendable () -> Void) {
        guard let source = script(tty: normalized(tty), bundleID: bundleID) else {
            DispatchQueue.main.async { MainActor.assumeIsolated { completion() } }
            return
        }
        AppleScriptRunner.run(source) { _ in completion() }
    }

    static func normalized(_ tty: String) -> String {
        tty.hasPrefix(devicePrefix) ? tty : devicePrefix + tty
    }

    static func script(tty: String, bundleID: String) -> String? {
        let literal = ScriptQuoting.appleScript(tty)
        switch bundleID {
        case terminalBundleID:
            return """
            tell application id "\(terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(literal)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case iTermBundleID:
            return """
            tell application id "\(iTermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(literal)" then
                                select w
                                tell w to select t
                                tell t to select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}
