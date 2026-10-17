import AppKit
import Observation

/// The persisted display choice and the displays currently connected.
@MainActor
@Observable
final class DisplaySettings {
    private static let choiceKey = "overlay.display.choice"

    private(set) var choice: DisplayChoice
    private(set) var screensRevision = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        if let data = defaults.data(forKey: Self.choiceKey) {
            do {
                choice = try JSONDecoder().decode(DisplayChoice.self, from: data)
            } catch {
                Log.interaction.error("stored display choice is unreadable: \(error.localizedDescription, privacy: .public)")
                choice = .all
            }
        } else {
            choice = .all
        }
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensRevision += 1 }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func select(_ newChoice: DisplayChoice) {
        choice = newChoice
        do {
            defaults.set(try JSONEncoder().encode(newChoice), forKey: Self.choiceKey)
        } catch {
            Log.interaction.error("could not store the display choice: \(error.localizedDescription, privacy: .public)")
        }
    }

    var displays: [DisplayInfo] {
        _ = screensRevision
        return NSScreen.screens.compactMap(\.displayInfo)
    }

    var mainDisplay: DisplayInfo? {
        _ = screensRevision
        return NSScreen.screens.first?.displayInfo
    }

    var targets: [DisplayInfo] {
        DisplayResolver.targets(choice: choice, displays: displays, main: mainDisplay)
    }
}
