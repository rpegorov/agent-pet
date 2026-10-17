import Foundation
import PetCore

/// Tracks how long each session has been asking for attention and reports what deserves a signal.
@MainActor
final class AttentionMonitor {
    static let freshWindow: TimeInterval = 5
    static let notifyAfter: TimeInterval = 3 * 60

    struct Outcome {
        var entered: [SessionState] = []
        var overdue: [SessionState] = []
    }

    private struct Entry {
        let since: Date
        var notified: Bool
    }

    private var entries: [String: Entry] = [:]

    /// While `quiet`, sessions are still tracked but nothing is reported.
    func update(sessions: [SessionState], now: Date, quiet: Bool) -> Outcome {
        let waiting = sessions.filter { $0.mood == .attention }
        entries = entries.filter { id, _ in waiting.contains { $0.id == id } }
        var outcome = Outcome()
        for session in waiting {
            if var entry = entries[session.id] {
                if !entry.notified, !quiet, now.timeIntervalSince(entry.since) >= Self.notifyAfter {
                    entry.notified = true
                    entries[session.id] = entry
                    outcome.overdue.append(session)
                }
            } else {
                // A session already waiting when first seen is a replayed state, not a new request.
                let fresh = now.timeIntervalSince(session.updatedAt) <= Self.freshWindow
                entries[session.id] = Entry(since: fresh ? session.updatedAt : now, notified: false)
                if fresh, !quiet { outcome.entered.append(session) }
            }
        }
        return outcome
    }
}
