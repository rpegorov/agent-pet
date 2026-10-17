import Foundation

/// Target hue per agent; `nil` keeps the original green sheet.
enum AgentPalette {
    static let knownHues: [String: Double?] = [
        "claude": 18,
        "codex": nil,
        "chatgpt": 175,
        "deepseek": 222,
        "glm": 268,
        "dsh": 195,
    ]

    static func targetHue(for agent: String) -> Double? {
        let key = agent.lowercased()
        if let known = knownHues[key] { return known }
        return TintMath.hue(forName: key)
    }
}
