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

    private(set) var hiddenUntil: Date?
    private(set) var fullScreenActive = false
    private(set) var clickThrough: Bool
    private(set) var answerPermissions: Bool

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var spaceObserver: NSObjectProtocol?
    @ObservationIgnored private var fullScreenCheck: Task<Void, Never>?

    /// True while the overlay is invisible, so it must not make noise.
    var isSuppressed: Bool { hiddenUntil != nil || fullScreenActive }

    /// Agents may wait for a verdict from the pet only while it can be seen and clicked.
    var canAnswerPermissions: Bool { !isSuppressed && !clickThrough && answerPermissions }

    init() {
        clickThrough = defaults.bool(forKey: Self.clickThroughKey)
        answerPermissions = defaults.object(forKey: Self.answerPermissionsKey) as? Bool ?? true
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

    func tick(now: Date) {
        if let until = hiddenUntil, now >= until {
            hiddenUntil = nil
        }
        checkFullScreen()
    }

    // The window list is read off the main thread; one check runs at a time.
    private func checkFullScreen() {
        guard fullScreenCheck == nil else { return }
        guard let snapshot = FullScreenDetector.snapshot() else {
            setFullScreen(false)
            return
        }
        fullScreenCheck = Task { [weak self] in
            let covering = await Task.detached { FullScreenDetector.isCovering(snapshot) }.value
            guard let self, !Task.isCancelled else { return }
            setFullScreen(covering)
            fullScreenCheck = nil
        }
    }

    private func setFullScreen(_ value: Bool) {
        guard value != fullScreenActive else { return }
        fullScreenActive = value
        withdrawPresenceIfUnavailable()
    }

    private func withdrawPresenceIfUnavailable() {
        if !canAnswerPermissions { OverlayPresence.clear() }
    }
}
