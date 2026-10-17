import AppKit

/// Starts a fresh agent session in the desktop apps, the DSH web app or Terminal.
@MainActor
struct NewSessionLauncher {
    enum TerminalAgent {
        case claude, codex

        var command: String {
            switch self {
            case .claude: "claude"
            case .codex: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
            }
        }
    }

    func newClaudeSession() {
        open("claude://code/new")
    }

    func newCodexSession() {
        if !open("codex://threads/new") {
            AppActivator.activate(bundleID: SessionJumper.codexApp)
        }
    }

    func newDshChat() {
        Task { await DshBridge.newChat() } // lint-allow: sw-unowned-task one HTTP round trip bounded by a request timeout
    }

    func start(_ agent: TerminalAgent, in directory: String) {
        guard SafeDirectory.isSafe(directory) else { return }
        let command = "cd \(ScriptQuoting.shell(directory)) && \(ScriptQuoting.shell(agent.command))"
        AppleScriptRunner.run("""
        tell application id "\(TerminalTabSelector.terminalBundleID)"
            activate
            do script \(ScriptQuoting.appleScriptShellCommand(command))
        end tell
        """)
    }

    @discardableResult
    private func open(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
