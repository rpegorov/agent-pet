import AppKit
import PetCore

/// What the views ask the overlay to do; implemented by `OverlayInteractor`.
@MainActor
protocol PetActionHandling: AnyObject {
    func petClicked(agent: String)
    func toggleSessions(agent: String)
    func showMenu(agent: String, event: NSEvent, in view: NSView)
    func jump(to session: SessionState)
    func answer(_ bubble: PermissionBubble, decision: PermissionDecision)
    func showNextRequest(agent: String)
}
