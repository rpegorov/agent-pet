import AppKit
import Observation
import PetCore

/// User-chosen and automatic reasons to keep the overlay out of the way.
@MainActor
@Observable
final class QuietMode {
    static let hideDuration: TimeInterval = 60 * 60
    private static let clickThroughKey = "overlay.clickThrough"
    private static let answerPermissionsKey = "overlay.answerPermissions"
    private static let hideOverFullScreenKey = "overlay.hideOverFullScreen"

    private(set) var hiddenUntil: Date?
    private(set) var coveredDisplays: Set<UInt32> = []
    private(set) var clickThrough: Bool
    private(set) var answerPermissions: Bool
    private(set) var hideOverFullScreen: Bool

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var spaceObserver: NSObjectProtocol?
    @ObservationIgnored private var fullScreenCheck: Task<Void, Never>?
    @ObservationIgnored var targetDisplays: () -> Set<UInt32> = { [] }

    /// True while no panel is visible, so the overlay must not make noise.
    var isSuppressed: Bool {
        let targets = targetDisplays()
        return hiddenUntil != nil || (!targets.isEmpty && targets.isSubset(of: coveredDisplays))
    }

    func isHidden(on display: UInt32) -> Bool {
        hiddenUntil != nil || coveredDisplays.contains(display)
    }

    /// Agents may wait for a verdict from the pet only while it can be seen and clicked.
    var canAnswerPermissions: Bool { !isSuppressed && !clickThrough && answerPermissions }

    init() {
        clickThrough = defaults.bool(forKey: Self.clickThroughKey)
        answerPermissions = defaults.object(forKey: Self.answerPermissionsKey) as? Bool ?? true
        hideOverFullScreen = defaults.bool(forKey: Self.hideOverFullScreenKey)
    }

    func start() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(now: Date()) }
        }
        withdrawPresenceIfUnavailable()
    }

    func stop() {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        fullScreenCheck?.cancel()
        fullScreenCheck = nil
        OverlayPresence.clear()
    }

    func hide(now: Date = Date()) {
        hiddenUntil = now.addingTimeInterval(Self.hideDuration)
        withdrawPresenceIfUnavailable()
    }

    func show() {
        hiddenUntil = nil
    }

    func toggleClickThrough() {
        clickThrough.toggle()
        defaults.set(clickThrough, forKey: Self.clickThroughKey)
        withdrawPresenceIfUnavailable()
    }

    func toggleAnswerPermissions() {
        answerPermissions.toggle()
        defaults.set(answerPermissions, forKey: Self.answerPermissionsKey)
        withdrawPresenceIfUnavailable()
    }

    func toggleHideOverFullScreen() {
        hideOverFullScreen.toggle()
        defaults.set(hideOverFullScreen, forKey: Self.hideOverFullScreenKey)
        checkFullScreen()
    }

    func tick(now: Date) {
        if let until = hiddenUntil, now >= until {
            hiddenUntil = nil
        }
        checkFullScreen()
    }

    // The window list is read off the main thread; one check runs at a time.
    private func checkFullScreen() {
        guard fullScreenCheck == nil else { return }
        guard hideOverFullScreen, let snapshot = FullScreenDetector.snapshot() else {
            setCovered([])
            return
        }
        fullScreenCheck = Task { [weak self] in
            let covered = await Task.detached { FullScreenDetector.coveredDisplays(snapshot) }.value
            guard let self, !Task.isCancelled else { return }
            setCovered(covered)
            fullScreenCheck = nil
        }
    }

    private func setCovered(_ value: Set<UInt32>) {
        guard value != coveredDisplays else { return }
        coveredDisplays = value
        withdrawPresenceIfUnavailable()
    }

    private func withdrawPresenceIfUnavailable() {
        if !canAnswerPermissions { OverlayPresence.clear() }
    }
}
