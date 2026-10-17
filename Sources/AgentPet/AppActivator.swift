import AppKit

enum AppActivator {
    static let allowedBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.codex",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
        "com.microsoft.VSCode",
    ]

    /// Brings a known application forward, launching it when it is not running; other bundle ids are ignored.
    @MainActor static func activate(bundleID: String) {
        guard allowedBundleIDs.contains(bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.interaction.info("not activating \(bundleID, privacy: .public): not allowed or not installed")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Log.interaction.error("could not activate \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                Log.interaction.info("activated \(bundleID, privacy: .public)")
            }
        }
    }
}
