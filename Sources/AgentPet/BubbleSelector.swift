import Foundation
import PetCore

/// One pending permission request, attached to the session that raised it.
struct PermissionBubble: Equatable, Identifiable {
    var id: String { request.id }
    let request: PermissionRequest
    let session: SessionState
    let position: Int
    let total: Int
}

/// Chooses which pending request each pet shows. The shown request stays put until it is gone,
/// so a newer request can never swap the buttons under the cursor.
enum BubbleSelector {
    struct Selection: Equatable {
        var bubbles: [String: PermissionBubble] = [:]
        var shown: [String: String] = [:]
    }

    static func select(
        requests: [PermissionRequest], sessions: [SessionState], shown: [String: String], now: Date
    ) -> Selection {
        let live = requests
            .filter { $0.expiresAt > now.timeIntervalSince1970 }
            .sorted { $0.ts < $1.ts }
        var selection = Selection()
        for agent in Set(live.map(\.agent)) {
            let queue = live.filter { $0.agent == agent && session(for: $0, in: sessions) != nil }
            guard let first = queue.first else { continue }
            let chosen = queue.first { $0.id == shown[agent] } ?? first
            guard let owner = session(for: chosen, in: sessions),
                  let index = queue.firstIndex(of: chosen) else { continue }
            selection.shown[agent] = chosen.id
            selection.bubbles[agent] = PermissionBubble(
                request: chosen, session: owner, position: index + 1, total: queue.count)
        }
        return selection
    }

    /// The id that follows `current` in the agent's queue, wrapping around.
    static func next(
        after current: String, requests: [PermissionRequest], sessions: [SessionState], agent: String
    ) -> String? {
        let queue = requests
            .filter { $0.agent == agent && session(for: $0, in: sessions) != nil }
            .sorted { $0.ts < $1.ts }
        guard let index = queue.firstIndex(where: { $0.id == current }), queue.count > 1 else { return nil }
        return queue[(index + 1) % queue.count].id
    }

    private static func session(for request: PermissionRequest, in sessions: [SessionState]) -> SessionState? {
        sessions.first { $0.agent == request.agent && $0.session == request.session }
    }
}
