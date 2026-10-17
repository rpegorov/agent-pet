import Foundation

public struct MoodBoard: Sendable {
    public static let workingTimeout: TimeInterval = 120
    public static let completeTimeout: TimeInterval = 10
    public static let attentionTimeout: TimeInterval = 10 * 60
    public static let sessionTimeout: TimeInterval = 30 * 60
    public static let endedLingerTimeout: TimeInterval = 10

    private struct SessionKey: Hashable {
        let agent: String
        let session: String
    }

    private struct Visible {
        let key: SessionKey
        let mood: Mood
        let event: PetEvent
    }

    private var latest: [SessionKey: PetEvent] = [:]
    private var startedAt: [SessionKey: Double] = [:]
    // Sessions that ended while showing a mood worth seeing, mapped to the end timestamp.
    private var endedAt: [SessionKey: Double] = [:]

    public init() {}

    public mutating func apply(_ event: PetEvent) {
        let key = SessionKey(agent: event.agent, session: event.session)
        if event.mood == .ended {
            endSession(key, at: event.ts)
            return
        }
        // Replayed or out-of-order lines must not overwrite newer state.
        if let current = latest[key], current.ts > event.ts { return }
        startedAt[key] = activityStart(of: event, after: latest[key], key: key)
        latest[key] = Self.inheritingOrigin(event, from: latest[key])
        endedAt[key] = nil
    }

    // Agents emit the end right after Stop, so a finished or waiting session lingers until its mood decays.
    private mutating func endSession(_ key: SessionKey, at ts: Double) {
        guard let current = latest[key] else { return }
        let shown = Self.effectiveMood(of: current, age: ts - current.ts)
        if shown == .complete || shown == .attention {
            endedAt[key] = ts
        } else {
            latest[key] = nil
            startedAt[key] = nil
            endedAt[key] = nil
        }
    }

    private func activityStart(of event: PetEvent, after previous: PetEvent?, key: SessionKey) -> Double {
        guard let previous, let start = startedAt[key], event.mood != .idle,
              previous.mood == .working || previous.mood == .attention else { return event.ts }
        let window = previous.mood == .attention ? Self.attentionTimeout : Self.workingTimeout
        return event.ts - previous.ts <= window ? start : event.ts
    }

    // Hooks that do not carry the origin (manual `send`, DSH) keep what the session reported earlier.
    private static func inheritingOrigin(_ event: PetEvent, from previous: PetEvent?) -> PetEvent {
        guard let previous else { return event }
        var merged = event
        merged.cwd = event.cwd ?? previous.cwd
        merged.app = event.app ?? previous.app
        merged.tty = event.tty ?? previous.tty
        return merged
    }

    private func isHidden(_ key: SessionKey, mood: Mood, now: Double) -> Bool {
        guard let end = endedAt[key] else { return false }
        return mood == .attention ? now - end > Self.endedLingerTimeout : mood != .complete
    }

    private func visible(at nowTs: Double) -> [Visible] {
        latest.compactMap { key, event in
            guard nowTs - event.ts <= Self.sessionTimeout else { return nil }
            let mood = Self.effectiveMood(of: event, age: nowTs - event.ts)
            guard mood != .idle, !isHidden(key, mood: mood, now: nowTs) else { return nil }
            return Visible(key: key, mood: mood, event: event)
        }
    }

    public func pets(at now: Date) -> [PetState] {
        let byAgent = Dictionary(grouping: visible(at: now.timeIntervalSince1970), by: \.event.agent)
        return byAgent.keys.sorted().compactMap { agent in
            guard let live = byAgent[agent],
                  let winner = live.max(by: { Self.outranks($1, $0) }) else { return nil }
            return PetState(agent: agent, mood: winner.mood, label: winner.event.label, sessions: live.count)
        }
    }

    public func sessions(at now: Date) -> [SessionState] {
        visible(at: now.timeIntervalSince1970)
            .sorted { Self.outranks($0, $1) }
            .map { item in
                let attention = item.mood == .attention
                return SessionState(
                    agent: item.event.agent, session: item.event.session,
                    mood: item.mood, label: item.event.label,
                    cwd: item.event.cwd, app: item.event.app, tty: item.event.tty,
                    detail: attention ? item.event.detail : nil,
                    permission: attention ? item.event.permission : nil,
                    startedAt: Date(timeIntervalSince1970: startedAt[item.key] ?? item.event.ts),
                    updatedAt: Date(timeIntervalSince1970: item.event.ts))
            }
    }

    private static func effectiveMood(of event: PetEvent, age: TimeInterval) -> Mood {
        switch event.mood {
        case .working: return age > workingTimeout ? .idle : .working
        case .complete: return age > completeTimeout ? .idle : .complete
        case .attention: return age > attentionTimeout ? .idle : .attention
        case .idle, .ended: return .idle
        }
    }

    private static func priority(_ mood: Mood) -> Int {
        switch mood {
        case .attention: return 3
        case .working: return 2
        case .complete: return 1
        case .idle: return 0
        }
    }

    private static func outranks(_ lhs: Visible, _ rhs: Visible) -> Bool {
        let (lp, rp) = (priority(lhs.mood), priority(rhs.mood))
        return lp != rp ? lp > rp : lhs.event.ts > rhs.event.ts
    }
}
