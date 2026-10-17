import Foundation
import Testing
@testable import PetCore

struct HookMappingTests {
    private func map(_ json: String, agent: String = "claude") -> PetEvent? {
        HookMapping.event(agent: agent, payload: Data(json.utf8), now: Date(timeIntervalSince1970: 100))
    }

    @Test(arguments: [
        ("SessionStart", Signal.idle, ""),
        ("UserPromptSubmit", .working, "thinking"),
        ("Stop", .complete, "done"),
        ("SessionEnd", .ended, ""),
    ])
    func simpleEvents(name: String, mood: Signal, label: String) throws {
        let event = try #require(map(#"{"hook_event_name":"\#(name)","session_id":"s1"}"#))
        #expect(event.mood == mood)
        #expect(event.label == label)
        #expect(event.session == "s1")
        #expect(event.ts == 100)
        #expect(event.v == 1)
    }

    @Test(arguments: [("PreToolUse", Signal.working), ("PostToolUse", .working), ("PermissionRequest", .attention)])
    func toolEvents(name: String, mood: Signal) throws {
        let event = try #require(map(#"{"hook_event_name":"\#(name)","session_id":"s","tool_name":"Bash"}"#))
        #expect(event.mood == mood)
        #expect(event.label == "Bash")
    }

    @Test func codexSamplePayload() throws {
        let json = """
        {"session_id":"abc","turn_id":"t1","cwd":"/tmp","hook_event_name":"PreToolUse","model":"gpt",\
        "tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"u1"}
        """
        let event = try #require(map(json, agent: "codex"))
        #expect(event == PetEvent(agent: "codex", session: "abc", mood: .working, label: "Bash", ts: 100, cwd: "/tmp"))
    }

    @Test func notificationBecomesAttentionWithTruncatedMessage() throws {
        let message = String(repeating: "x", count: 100)
        let event = try #require(map(#"{"hook_event_name":"Notification","session_id":"s","message":"\#(message)"}"#))
        #expect(event.mood == .attention)
        #expect(event.label.count == HookMapping.maxLabelLength)
    }

    @Test func idlePromptNotificationIsIdle() throws {
        let event = try #require(map(#"{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"waiting"}"#))
        #expect(event.mood == .idle)
    }

    @Test func mcpToolNameIsShortened() throws {
        let event = try #require(map(#"{"hook_event_name":"PreToolUse","tool_name":"mcp__server__search_notes"}"#))
        #expect(event.label == "search_notes")
    }

    @Test func missingSessionFallsBackToDefault() throws {
        let event = try #require(map(#"{"hook_event_name":"Stop"}"#))
        #expect(event.session == "default")
    }

    @Test func unknownAndMalformedPayloadsAreIgnored() {
        #expect(map(#"{"hook_event_name":"SubagentStop","session_id":"s"}"#) == nil)
        #expect(map(#"{"hook_event_name":"PreCompact"}"#) == nil)
        #expect(map("not json") == nil)
        #expect(map("[]") == nil)
        #expect(map("") == nil)
    }
}

struct HookMappingOriginTests {
    private func map(_ json: String) -> PetEvent? {
        HookMapping.event(agent: "claude", payload: Data(json.utf8))
    }

    @Test func cwdIsTakenFromPayload() {
        let event = map(#"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","cwd":"/work/repo"}"#)
        #expect(event?.cwd == "/work/repo")
    }

    @Test func permissionRequestCarriesSummaryOfCommand() {
        let event = map(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"rm -rf x","description":"d"}}"#)
        #expect(event?.detail == "Bash: rm -rf x")
        #expect(event?.permission == nil)
    }

    @Test func summaryPrefersFilePathAndFallsBackToFirstStringField() {
        let file = map(#"{"hook_event_name":"PermissionRequest","tool_name":"Edit","tool_input":{"file_path":"/a/b.txt","old_string":"x"}}"#)
        #expect(file?.detail == "Edit: /a/b.txt")
        let other = map(#"{"hook_event_name":"PermissionRequest","tool_name":"Task","tool_input":{"count":3,"prompt":"go"}}"#)
        #expect(other?.detail == "Task: go")
        let none = map(#"{"hook_event_name":"PermissionRequest","tool_name":"Task","tool_input":{}}"#)
        #expect(none?.detail == "Task")
    }

    @Test func summaryIsTruncated() throws {
        let long = String(repeating: "a", count: 500)
        let event = map(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"\#(long)"}}"#)
        #expect(try #require(event?.detail).count == HookMapping.maxDetailLength)
    }

    @Test func nonPermissionEventsHaveNoDetail() {
        #expect(map(#"{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#)?.detail == nil)
    }

    @Test func toolInputKeepsSlashesUnescaped() {
        let root: [String: Any] = ["tool_input": ["file_path": "/a/b.txt"]]
        #expect(HookMapping.toolInputText(root).text.contains(#""file_path" : "/a/b.txt""#))
    }

    @Test func unreadableToolInputIsFlaggedTruncated() {
        let notObject: [String: Any] = ["tool_input": "rm -rf /"]
        #expect(HookMapping.toolInputText(notObject) == ("", true))
        let unserialisable: [String: Any] = ["tool_input": ["when": Date()]]
        #expect(HookMapping.toolInputText(unserialisable) == ("", true))
    }

    @Test func absentToolInputIsEmptyAndNotTruncated() {
        #expect(HookMapping.toolInputText([:]) == ("", false))
    }
}
