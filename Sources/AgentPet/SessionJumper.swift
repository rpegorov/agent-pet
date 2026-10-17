import AppKit
import PetCore

/// Opens the app that hosts a session and, where the app allows it, the session itself.
@MainActor
struct SessionJumper {
    static let claudeDesktop = "com.anthropic.claudefordesktop"
    static let codexApp = "com.openai.codex"
    static let dsh = "dsh"

    func jump(to session: SessionState) {
        Log.interaction.info("jump: app=\(session.app ?? "none", privacy: .public) session=\(session.session, privacy: .public)")
        guard let app = session.app else { return }
        switch app {
        case Self.codexApp: openCodexThread(session.session)
        case Self.claudeDesktop: openClaudeSession(session)
        case Self.dsh: openDshSession(session.session)
        default: focusTerminal(bundleID: app, tty: session.tty)
        }
    }

    private func openCodexThread(_ id: String) {
        if let url = DeepLink.codexThread(id) {
            let opened = NSWorkspace.shared.open(url)
            Log.interaction.info("opened \(url.absoluteString, privacy: .public): \(opened)")
            if opened { return }
        }
        AppActivator.activate(bundleID: Self.codexApp)
    }

    private func openDshSession(_ id: String) {
        Task { await DshBridge.openSession(id) } // lint-allow: sw-unowned-task one HTTP round trip bounded by a request timeout
    }

    private func openClaudeSession(_ session: SessionState) {
        let cliSession = session.session
        let needsInput = session.mood == .attention
        Task { // lint-allow: sw-unowned-task one bounded directory scan, then a single URL open
            let local = await Task.detached { ClaudeDesktopSessions.localSessionID(forCLISession: cliSession) }.value
            if let local, let url = DeepLink.claudeSession(local: local) {
                Self.logOpen(url)
            } else if needsInput, let url = URL(string: "claude://code/needs-input") {
                Self.logOpen(url)
            } else {
                Log.interaction.info("no desktop id for \(cliSession, privacy: .public): activating the app")
                AppActivator.activate(bundleID: Self.claudeDesktop)
            }
        }
    }

    private static func logOpen(_ url: URL) {
        let opened = NSWorkspace.shared.open(url)
        Log.interaction.info("opened \(url.absoluteString, privacy: .public): \(opened)")
    }

    private func focusTerminal(bundleID: String, tty: String?) {
        guard let tty, !tty.isEmpty else {
            AppActivator.activate(bundleID: bundleID)
            return
        }
        TerminalTabSelector.select(tty: tty, in: bundleID) { AppActivator.activate(bundleID: bundleID) }
    }
}
