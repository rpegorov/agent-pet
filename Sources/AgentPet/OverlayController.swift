import AppKit
import SwiftUI

/// Owns one panel per target display, shows them while pets exist and keeps one panel as the bubble host.
@MainActor
final class OverlayController {
    private static let screenMargin: CGFloat = 24
    private static let exitAnimation: Duration = .milliseconds(300)

    private let store: PetStore
    private let quiet: QuietMode
    private let settings: DisplaySettings
    private let actions: any PetActionHandling
    private var hosts: [UInt32: PanelHost] = [:]
    private var bubbleHost: UInt32?

    init(store: PetStore, quiet: QuietMode, settings: DisplaySettings, actions: any PetActionHandling) {
        self.store = store
        self.quiet = quiet
        self.settings = settings
        self.actions = actions
        quiet.targetDisplays = { [settings] in Set(settings.targets.map(\.id)) }
        observe()
    }

    func stop() {
        for host in hosts.values { host.stop() }
        hosts.removeAll()
    }

    /// Re-arms itself after each change, so the panels follow the store, the quiet modes and the display choice.
    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() } // lint-allow: sw-unowned-task single hop that re-arms observation
        }
    }

    private func update() {
        let targets = settings.targets
        let targetIDs = Set(targets.map(\.id))
        for (id, host) in hosts where !targetIDs.contains(id) {
            host.stop()
            hosts[id] = nil
        }
        let anyBubble = !store.bubbles.isEmpty
        bubbleHost = anyBubble ? chooseBubbleHost(targets: targets) : nil
        for target in targets {
            let host = hosts[target.id] ?? makeHost(for: target.id)
            let showBubbles = bubbleHost == target.id
            host.context.showsBubbles = showBubbles
            host.update(
                columns: store.columns(showBubbles: showBubbles),
                hidden: quiet.isHidden(on: target.id),
                exitDelay: Self.exitAnimation)
        }
    }

    // The host is chosen when a bubble first appears and kept while the bubbles last, so it does not hop between panels.
    private func chooseBubbleHost(targets: [DisplayInfo]) -> UInt32? {
        let covered = quiet.coveredDisplays
        if let current = bubbleHost, targets.contains(where: { $0.id == current }), !covered.contains(current) {
            return current
        }
        return DisplayResolver.bubbleHost(
            targets: targets, covered: covered, pointerDisplay: pointerDisplay(), main: settings.mainDisplay?.id)
    }

    private func pointerDisplay() -> UInt32? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }?.displayID
    }

    private func makeHost(for display: UInt32) -> PanelHost {
        let host = PanelHost(display: display, margin: Self.screenMargin, store: store, quiet: quiet, actions: actions)
        hosts[display] = host
        return host
    }
}
