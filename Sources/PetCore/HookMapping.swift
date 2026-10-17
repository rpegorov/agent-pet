import Foundation

public enum HookMapping {
    public static let maxLabelLength = 40
    public static let maxDetailLength = 200
    public static let maxToolInputBytes = 8 * 1024
    private static let defaultSession = "default"
    private static let mcpSeparator = "__"
    private static let mcpPrefix = "mcp__"
    private static let idlePromptType = "idle_prompt"
    private static let preferredInputKeys = ["command", "file_path", "url"]

    public static func event(agent: String, payload: Data, now: Date = Date()) -> PetEvent? {
        guard let root = parseObject(payload),
              let name = root["hook_event_name"] as? String,
              let (mood, label) = signal(for: name, in: root) else { return nil }
        let session = (root["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultSession
        return PetEvent(
            agent: agent, session: session, mood: mood, label: label, ts: now.timeIntervalSince1970,
            cwd: (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            detail: name == "PermissionRequest" ? permissionSummary(root) : nil)
    }

    public static func parseObject(_ payload: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] // lint-allow: sw-try-optional a malformed payload must never fail the calling agent
    }

    // The whole tool input, so the user can judge a prompt before allowing it. An input that cannot be shown in
    // full (oversized, not an object, unserialisable) is flagged truncated so the overlay withholds Allow.
    public static func toolInputText(_ root: [String: Any]) -> (text: String, truncated: Bool) {
        guard let input = root["tool_input"] else { return ("", false) }
        guard input is [String: Any], JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data( // lint-allow: sw-try-optional an unserialisable input is reported as truncated
                  withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return ("", true) }
        guard data.count > maxToolInputBytes else { return (String(decoding: data, as: UTF8.self), false) }
        let cut = String(decoding: data.prefix(maxToolInputBytes), as: UTF8.self)
        return (cut.hasSuffix("\u{FFFD}") ? String(cut.dropLast()) : cut, true)
    }

    // Tool name plus the most telling input field, so the prompt is recognisable without the native dialog.
    public static func permissionSummary(_ root: [String: Any]) -> String {
        let tool = (root["tool_name"] as? String) ?? ""
        let input = root["tool_input"] as? [String: Any] ?? [:]
        let keys = preferredInputKeys + input.keys.sorted()
        let value = keys.lazy.compactMap { input[$0] as? String }.first { !$0.isEmpty }
        return String(((value.map { "\(tool): \($0)" }) ?? tool).prefix(maxDetailLength))
    }

    private static func signal(for hook: String, in root: [String: Any]) -> (Signal, String)? {
        let tool = toolLabel(root["tool_name"] as? String)
        switch hook {
        case "SessionStart": return (.idle, "")
        case "UserPromptSubmit": return (.working, "thinking")
        case "PreToolUse", "PostToolUse": return (.working, tool)
        case "PermissionRequest": return (.attention, tool)
        case "Notification": return notification(root)
        case "Stop": return (.complete, "done")
        case "SessionEnd": return (.ended, "")
        default: return nil
        }
    }

    private static func notification(_ root: [String: Any]) -> (Signal, String) {
        if root["notification_type"] as? String == idlePromptType { return (.idle, "") }
        return (.attention, truncated((root["message"] as? String) ?? ""))
    }

    private static func toolLabel(_ name: String?) -> String {
        guard let name else { return "" }
        if name.hasPrefix(mcpPrefix), let last = name.components(separatedBy: mcpSeparator).last, !last.isEmpty {
            return truncated(last)
        }
        return truncated(name)
    }

    private static func truncated(_ text: String) -> String {
        String(text.prefix(maxLabelLength))
    }
}
