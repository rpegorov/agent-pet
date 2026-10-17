import Foundation
import PetCore

// Handles the PermissionRequest hook: shows the prompt in the overlay and relays the verdict to the agent.
enum PermitCommand {
    private static let overlayMaxAge: TimeInterval = 6
    private static let defaultWaitSeconds: TimeInterval = 30
    // Must stay below the agent-side hook timeout in scripts/hooks_common.py (checked by Tests/scripts).
    private static let maxWaitSeconds: TimeInterval = 40
    private static let waitEnvironmentKey = "AGENT_PET_PERMIT_WAIT"
    private static let pollIntervalMicroseconds: UInt32 = 100_000
    private static let terminationSignals = [SIGTERM, SIGINT, SIGHUP]
    // Tools that ask the user something: allowing them from a bubble would skip the question itself.
    private static let interactiveToolLabels = ["AskUserQuestion": "question", "ExitPlanMode": "plan"]
    private static let denyMessage = "Denied from agent-pet"

    static func run(agent: String, payload: Data) {
        signal(SIGPIPE, SIG_IGN)
        guard let root = HookMapping.parseObject(payload),
              let parsed = HookMapping.event(agent: agent, payload: payload) else { return }
        var event = withOrigin(parsed)
        if let label = interactiveToolLabels[(root["tool_name"] as? String) ?? ""] {
            event.label = label
            event.detail = nil
            record(event)
            return
        }
        guard OverlayPresence.isAlive(maxAge: overlayMaxAge) else {
            record(event)
            return
        }
        let wait = waitSeconds()
        let input = HookMapping.toolInputText(root)
        let request = PermissionRequest(
            agent: agent, session: event.session, tool: (root["tool_name"] as? String) ?? "",
            summary: event.detail ?? event.label, toolInput: input.text, truncated: input.truncated,
            expiresAt: Date().addingTimeInterval(wait).timeIntervalSince1970)
        do {
            try PermissionBroker.submit(request)
        } catch {
            FileHandle.standardError.write(Data("agent-pet-emit: \(error)\n".utf8))
            record(event)
            return
        }
        let cleared = followUp(to: event, verdict: nil)
        let sources = cancelOnTermination(id: request.id, cleared: cleared)
        event.permission = request.id
        record(event)
        let verdict = withExtendedLifetime(sources) { awaitVerdict(for: request.id, seconds: wait) }
        PermissionBroker.remove(id: request.id)
        print(verdict: verdict)
        record(followUp(to: event, verdict: verdict))
    }

    // A killed hook must not leave a dead Allow/Deny bubble behind.
    private static func cancelOnTermination(id: String, cleared: PetEvent) -> [any DispatchSourceSignal] {
        let queue = DispatchQueue(label: "agent-pet-emit.signals")
        return terminationSignals.map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                PermissionBroker.remove(id: id)
                var event = cleared
                event.ts = Date().timeIntervalSince1970
                record(event)
                exit(0)
            }
            source.resume()
            return source
        }
    }

    // Stops early when the overlay disappears: nobody can answer, so the native dialog takes over.
    private static func awaitVerdict(for id: String, seconds: TimeInterval) -> PermissionDecision? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let verdict = PermissionBroker.decision(for: id) { return verdict }
            guard OverlayPresence.isAlive(maxAge: overlayMaxAge) else { return nil }
            usleep(pollIntervalMicroseconds)
        }
        return PermissionBroker.decision(for: id)
    }

    private static func waitSeconds() -> TimeInterval {
        let requested = ProcessInfo.processInfo.environment[waitEnvironmentKey].flatMap(TimeInterval.init)
        return min(requested ?? defaultWaitSeconds, maxWaitSeconds)
    }

    private static func print(verdict: PermissionDecision?) {
        let decision: String
        switch verdict {
        case .allow: decision = #"{"behavior":"allow"}"#
        case .deny: decision = #"{"behavior":"deny","message":"\#(denyMessage)"}"#
        case .deferToAgent, nil: return
        }
        let output = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":\#(decision)}}"#
        do {
            try FileHandle.standardOutput.write(contentsOf: Data((output + "\n").utf8))
        } catch {
            FileHandle.standardError.write(Data("agent-pet-emit: stdout closed: \(error)\n".utf8))
        }
    }

    // After a verdict the agent resumes; without one the native dialog is still open.
    private static func followUp(to event: PetEvent, verdict: PermissionDecision?) -> PetEvent {
        var next = event
        next.ts = Date().timeIntervalSince1970
        next.permission = nil
        next.detail = nil
        if verdict == .allow || verdict == .deny { next.mood = .working }
        return next
    }
}
