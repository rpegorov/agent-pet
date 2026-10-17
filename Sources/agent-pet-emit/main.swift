import Foundation
import PetCore

private func buildEvent(command: String, options: [String: String]) -> PetEvent? {
    guard let agent = options["agent"], !agent.isEmpty else { return nil }
    switch command {
    case "hook":
        return HookMapping.event(agent: agent, payload: readStdin()).map(withOrigin)
    case "send":
        guard let raw = options["mood"], let mood = Signal(rawValue: raw) else { return nil }
        return PetEvent(agent: agent, session: options["session"] ?? agent, mood: mood, label: options["label"] ?? "")
    default:
        return nil
    }
}

// The emitter runs inside agent hooks: it must never fail the caller; stdout is reserved for permit verdicts.
let args = Array(CommandLine.arguments.dropFirst())
let parsedOptions = options(from: Array(args.dropFirst()))
if args.first == "permit", let agent = parsedOptions["agent"], !agent.isEmpty {
    PermitCommand.run(agent: agent, payload: readStdin())
} else if let command = args.first, let event = buildEvent(command: command, options: parsedOptions) {
    record(event)
}
exit(0)
