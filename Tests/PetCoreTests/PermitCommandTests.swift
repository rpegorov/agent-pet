import Foundation
import Testing
@testable import PetCore

private final class BundleToken {}

private let allowOutput = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
private let denyOutput = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from agent-pet"}}}"#
private let payload = #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"rm -rf build"},"cwd":"/work"}"#
private let appearTimeout: TimeInterval = 5
private let pollInterval: UInt64 = 20_000_000

private struct Sandbox {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pet-permit-\(UUID().uuidString)", isDirectory: true)
    var log: URL { root.appendingPathComponent("events.jsonl") }
    var permissions: URL { root.appendingPathComponent("permissions", isDirectory: true) }

    var events: [PetEvent] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(PetEvent.self, from: Data($0.utf8)) }
    }
}

private struct Run {
    let process: Process
    let stdout: Pipe

    func finish() throws -> String {
        process.waitUntilExit()
        let data = try stdout.fileHandleForReading.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

private func startPermit(in sandbox: Sandbox, wait: String? = nil, payload: String = payload) throws -> Run {
    let binary = Bundle(for: BundleToken.self).bundleURL
        .deletingLastPathComponent().appendingPathComponent("agent-pet-emit")
    let process = Process()
    process.executableURL = binary
    process.arguments = ["permit", "--agent", "claude"]
    var environment = ProcessInfo.processInfo.environment
    environment["AGENT_PET_LOG"] = sandbox.log.path
    environment["AGENT_PET_PERMIT_WAIT"] = wait
    process.environment = environment
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    try process.run()
    stdin.fileHandleForWriting.write(Data(payload.utf8))
    try stdin.fileHandleForWriting.close()
    return Run(process: process, stdout: stdout)
}

private func awaitRequest(in sandbox: Sandbox) async -> PermissionRequest? {
    let deadline = Date().addingTimeInterval(appearTimeout)
    while Date() < deadline {
        if let request = PermissionBroker.pending(in: sandbox.permissions).first { return request }
        try? await Task.sleep(nanoseconds: pollInterval) // lint-allow: test-sleep polling step bounded by a deadline
    }
    return nil
}

struct PermitCommandTests {
    @Test func withoutOverlayExitsQuicklyWithoutOutput() throws {
        let sandbox = Sandbox()
        let started = Date()
        let output = try startPermit(in: sandbox, wait: "30").finish()
        #expect(output.isEmpty)
        #expect(Date().timeIntervalSince(started) < 3)
        let events = sandbox.events
        #expect(events.count == 1)
        #expect(events.first?.mood == .attention)
        #expect(events.first?.detail == "Bash: rm -rf build")
        #expect(events.first?.permission == nil)
        #expect(events.first?.cwd == "/work")
    }

    @Test func allowAnswerPrintsAllowDecision() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "10")
        let request = try #require(await awaitRequest(in: sandbox))
        #expect(request.tool == "Bash")
        #expect(request.summary == "Bash: rm -rf build")
        try PermissionBroker.answer(id: request.id, decision: .allow, in: sandbox.permissions)
        #expect(try run.finish() == allowOutput + "\n")
        #expect(PermissionBroker.pending(in: sandbox.permissions).isEmpty)
        #expect(PermissionBroker.decision(for: request.id, in: sandbox.permissions) == nil)
        let events = sandbox.events
        #expect(events.first?.permission == request.id)
        #expect(events.last?.mood == .working)
        #expect(events.last?.permission == nil)
    }

    @Test func denyAnswerPrintsDenyDecision() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "10")
        let request = try #require(await awaitRequest(in: sandbox))
        try PermissionBroker.answer(id: request.id, decision: .deny, in: sandbox.permissions)
        #expect(try run.finish() == denyOutput + "\n")
    }

    @Test func unansweredRequestTimesOutSilently() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let output = try startPermit(in: sandbox, wait: "1").finish()
        #expect(output.isEmpty)
        #expect(PermissionBroker.pending(in: sandbox.permissions).isEmpty)
        let last = try #require(sandbox.events.last)
        #expect(last.mood == .attention)
        #expect(last.permission == nil)
    }

    @Test func answerForAnotherRequestDoesNotResolveThisOne() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "2")
        let request = try #require(await awaitRequest(in: sandbox))
        let forged = sandbox.permissions.appendingPathComponent(request.id + ".answer")
        let other = UUID().uuidString
        try PermissionBroker.answer(id: other, decision: .allow, in: sandbox.permissions)
        try FileManager.default.moveItem(
            at: sandbox.permissions.appendingPathComponent(other + ".answer"), to: forged)
        #expect(try run.finish().isEmpty)
    }

    @Test func sigtermRemovesRequestAndClearsPermission() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "30")
        let request = try #require(await awaitRequest(in: sandbox))
        run.process.terminate()
        #expect(try run.finish().isEmpty)
        #expect(run.process.terminationStatus == 0)
        #expect(PermissionBroker.pending(in: sandbox.permissions).isEmpty)
        let file = sandbox.permissions.appendingPathComponent(request.id + ".request")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let last = try #require(sandbox.events.last)
        #expect(last.mood == .attention)
        #expect(last.permission == nil)
    }

    @Test func deferAnswerPrintsNothingAndClearsPermission() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "30")
        let request = try #require(await awaitRequest(in: sandbox))
        let started = Date()
        try PermissionBroker.answer(id: request.id, decision: .deferToAgent, in: sandbox.permissions)
        #expect(try run.finish().isEmpty)
        #expect(Date().timeIntervalSince(started) < 3)
        let last = try #require(sandbox.events.last)
        #expect(last.mood == .attention)
        #expect(last.permission == nil)
    }

    @Test func overlayGoingAwayEndsTheWaitWithoutOutput() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let started = Date()
        let run = try startPermit(in: sandbox, wait: "30")
        _ = try #require(await awaitRequest(in: sandbox))
        OverlayPresence.clear(in: sandbox.root)
        #expect(try run.finish().isEmpty)
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(PermissionBroker.pending(in: sandbox.permissions).isEmpty)
    }

    @Test func requestCarriesDeadlineCappedAtMaximumWait() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "1000")
        let request = try #require(await awaitRequest(in: sandbox))
        let remaining = request.expiresAt - Date().timeIntervalSince1970
        #expect(remaining > 30 && remaining <= 40)
        run.process.terminate()
        _ = try run.finish()
    }

    @Test func requestCarriesFullToolInput() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let run = try startPermit(in: sandbox, wait: "10")
        let request = try #require(await awaitRequest(in: sandbox))
        #expect(request.toolInput.contains(#""command" : "rm -rf build""#))
        #expect(!request.truncated)
        run.process.terminate()
        _ = try run.finish()
    }

    @Test func oversizedToolInputIsCappedAndFlagged() async throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let big = String(repeating: "x", count: HookMapping.maxToolInputBytes * 2)
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"\#(big)"}}"#
        let run = try startPermit(in: sandbox, wait: "10", payload: json)
        let request = try #require(await awaitRequest(in: sandbox))
        #expect(request.truncated)
        #expect(request.toolInput.utf8.count <= HookMapping.maxToolInputBytes)
        run.process.terminate()
        _ = try run.finish()
    }

    @Test(arguments: [("AskUserQuestion", "question"), ("ExitPlanMode", "plan")])
    func interactiveToolsNeverBecomeABubble(tool: String, label: String) throws {
        let sandbox = Sandbox()
        OverlayPresence.beat(in: sandbox.root)
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"\#(tool)","tool_input":{"questions":[]}}"#
        let started = Date()
        let output = try startPermit(in: sandbox, wait: "30", payload: json).finish()
        #expect(output.isEmpty)
        #expect(Date().timeIntervalSince(started) < 3)
        #expect(PermissionBroker.pending(in: sandbox.permissions).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sandbox.permissions.path))
        let events = sandbox.events
        #expect(events.count == 1)
        #expect(events.first?.mood == .attention)
        #expect(events.first?.label == label)
        #expect(events.first?.permission == nil)
    }
}
