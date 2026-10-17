import Foundation
import PetCore

/// Per-second housekeeping: quiet-mode checks, the presence heartbeat and attention signals.
@MainActor
final class OverlayCoordinator {
    private static let beatInterval: TimeInterval = 2
    private static let quietCheckInterval: TimeInterval = 2

    private let store: PetStore
    private let quiet: QuietMode
    private let monitor = AttentionMonitor()
    private var lastBeat = Date.distantPast
    private var lastQuietCheck = Date.distantPast

    init(store: PetStore, quiet: QuietMode) {
        self.store = store
        self.quiet = quiet
        store.onRefresh = { [weak self] now in self?.tick(now) }
    }

    private func tick(_ now: Date) {
        if now.timeIntervalSince(lastQuietCheck) >= Self.quietCheckInterval {
            lastQuietCheck = now
            quiet.tick(now: now)
        }
        beatIfDue(now)
        signal(now)
        SpriteRegistry.shared.refreshAll()
    }

    // Agents only wait for the overlay while it can be seen and clicked.
    private func beatIfDue(_ now: Date) {
        guard quiet.canAnswerPermissions,
              now.timeIntervalSince(lastBeat) >= Self.beatInterval else { return }
        lastBeat = now
        OverlayPresence.beat()
    }

    private func signal(_ now: Date) {
        let outcome = monitor.update(sessions: store.sessions, now: now, quiet: quiet.isSuppressed)
        for session in outcome.entered {
            store.registerHop(agent: session.agent)
        }
        if !outcome.entered.isEmpty {
            AttentionAlerts.playSound()
        }
        for session in outcome.overdue {
            AttentionAlerts.notify("\(session.agent) is waiting for you in \(SessionPresentation.projectName(of: session))")
        }
    }
}
