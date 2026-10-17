import Foundation

enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "agent-pet.applescript")

    /// Runs a script on a serial background queue; `completion` runs on the main actor.
    /// A failure (including a denied Automation permission) is logged.
    static func run(_ source: String, completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        queue.async {
            let succeeded = execute(source)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(succeeded) } }
        }
    }

    private static func execute(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var failure: NSDictionary?
        script.executeAndReturnError(&failure)
        if let failure {
            let number = failure[NSAppleScript.errorNumber] as? Int ?? 0
            let message = failure[NSAppleScript.errorMessage] as? String ?? ""
            Log.interaction.error("AppleScript failed: error \(number, privacy: .public): \(message, privacy: .private)")
            return false
        }
        return true
    }
}
