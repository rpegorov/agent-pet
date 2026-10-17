import AppKit

struct DisplayInfo: Equatable, Hashable, Sendable {
    let id: UInt32
    let name: String
}

/// Which displays carry a panel. The stored choice is never rewritten when a display disappears,
/// so it applies again once the display returns.
enum DisplayChoice: Equatable, Codable, Sendable {
    case all
    case screen(id: UInt32, name: String)
}

enum DisplayResolver {
    /// Displays that get a panel; a chosen display that is gone falls back to the main one.
    static func targets(choice: DisplayChoice, displays: [DisplayInfo], main: DisplayInfo?) -> [DisplayInfo] {
        switch choice {
        case .all:
            return displays
        case let .screen(id, name):
            if let byID = displays.first(where: { $0.id == id }) { return [byID] }
            let sameName = displays.filter { $0.name == name }
            if sameName.count == 1, let match = sameName.first { return [match] }
            return (main ?? displays.first).map { [$0] } ?? []
        }
    }

    /// The single panel that shows permission bubbles: the display under the pointer, else the main one.
    static func bubbleHost(
        targets: [DisplayInfo], covered: Set<UInt32>, pointerDisplay: UInt32?, main: UInt32?
    ) -> UInt32? {
        let candidates = targets.map(\.id).filter { !covered.contains($0) }
        if let pointerDisplay, candidates.contains(pointerDisplay) { return pointerDisplay }
        if let main, candidates.contains(main) { return main }
        return candidates.first
    }
}

extension NSScreen {
    static let numberKey = NSDeviceDescriptionKey("NSScreenNumber")

    var displayID: UInt32? {
        (deviceDescription[Self.numberKey] as? NSNumber)?.uint32Value
    }

    var displayInfo: DisplayInfo? {
        displayID.map { DisplayInfo(id: $0, name: localizedName) }
    }
}
