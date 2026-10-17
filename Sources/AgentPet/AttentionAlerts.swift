import AppKit

/// Sound and system notification for sessions that need the user.
enum AttentionAlerts {
    private static let soundName = "Tink"
    private static let notificationTitle = "Agent Pet"

    @MainActor static func playSound() {
        NSSound(named: soundName)?.play()
    }

    @MainActor static func notify(_ message: String) {
        let script = "display notification \"\(ScriptQuoting.appleScript(message))\" with title \"\(notificationTitle)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("agent-pet: could not post a notification: \(error)")
        }
    }
}
