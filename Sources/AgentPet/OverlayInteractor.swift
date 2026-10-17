import AppKit
import PetCore

/// Turns clicks on the pets, the list and the bubble into store changes and side effects.
@MainActor
final class OverlayInteractor: PetActionHandling {
    private let store: PetStore
    private let jumper: SessionJumper
    private let menu: OverlayMenu

    init(store: PetStore, jumper: SessionJumper, menu: OverlayMenu) {
        self.store = store
        self.jumper = jumper
        self.menu = menu
    }

    func petClicked(agent: String) {
        let sessions = store.sessions(of: agent)
        if sessions.count == 1, let only = sessions.first {
            Log.interaction.info("pet \(agent, privacy: .public) has one session: jumping")
            jump(to: only)
        } else {
            Log.interaction.info("pet \(agent, privacy: .public) has \(sessions.count) sessions: toggling the list")
            toggleSessions(agent: agent)
        }
    }

    func toggleSessions(agent: String) {
        store.expandedAgent = store.expandedAgent == agent ? nil : agent
    }

    func showMenu(agent: String, event: NSEvent, in view: NSView) {
        NSMenu.popUpContextMenu(menu.makePetMenu(agent: agent), with: event, for: view)
    }

    func jump(to session: SessionState) {
        Log.interaction.info("row selected: \(session.agent, privacy: .public) \(session.session, privacy: .public)")
        store.expandedAgent = nil
        jumper.jump(to: session)
    }

    func answer(_ bubble: PermissionBubble, decision: PermissionDecision) {
        store.answer(bubble, decision: decision)
    }

    func showNextRequest(agent: String) {
        store.showNextRequest(agent: agent)
    }
}
