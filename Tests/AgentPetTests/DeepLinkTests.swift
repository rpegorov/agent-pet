import Foundation
import Testing
@testable import AgentPet

struct DeepLinkTests {
    @Test func codexThreadAcceptsUUIDs() {
        let id = "5e9d6b1a-77c2-4c3e-9a0f-1a2b3c4d5e6f"
        #expect(DeepLink.codexThread(id)?.absoluteString == "codex://threads/\(id)")
    }

    @Test func codexThreadRefusesPathTricks() {
        #expect(DeepLink.codexThread("../settings") == nil)
        #expect(DeepLink.codexThread("a/b") == nil)
        #expect(DeepLink.codexThread("a?x=1") == nil)
        #expect(DeepLink.codexThread("") == nil)
    }

    @Test func claudeSessionNeedsLocalPrefix() {
        #expect(DeepLink.claudeSession(local: "local_1ef5a85a-8ed4")?.absoluteString
            == "claude://code/continue?session=local_1ef5a85a-8ed4")
        #expect(DeepLink.claudeSession(local: "1ef5a85a") == nil)
        #expect(DeepLink.claudeSession(local: "local_a&b") == nil)
    }

    @Test func activatorOnlyKnowsListedApps() {
        #expect(AppActivator.allowedBundleIDs.contains("com.apple.Terminal"))
        #expect(!AppActivator.allowedBundleIDs.contains("com.apple.systempreferences"))
    }

    @Test func ttyGetsDevicePrefixOnce() {
        #expect(TerminalTabSelector.normalized("ttys003") == "/dev/ttys003")
        #expect(TerminalTabSelector.normalized("/dev/ttys003") == "/dev/ttys003")
    }

    @Test func tabScriptsEmbedTheEscapedTTY() {
        let script = TerminalTabSelector.script(tty: "/dev/tty\"s", bundleID: TerminalTabSelector.terminalBundleID)
        #expect(script?.contains("tty of t is \"/dev/tty\\\"s\"") == true)
        #expect(TerminalTabSelector.script(tty: "/dev/ttys1", bundleID: "com.example.other") == nil)
    }
}
