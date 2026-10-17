import AppKit
import Testing
@testable import AgentPet

struct FullScreenTests {
    private let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let right = CGRect(x: 1000, y: 0, width: 1200, height: 900)

    private typealias Screen = FullScreenDetector.Screen

    @Test func onlyTheDisplayWithAFillingWindowIsCovered() {
        let screens = [Screen(id: 1, frame: left), Screen(id: 2, frame: right)]
        #expect(FullScreenDetector.covered(screens: screens, windows: [right]) == [2])
        #expect(FullScreenDetector.covered(screens: screens, windows: [left, right]) == [1, 2])
        #expect(FullScreenDetector.covered(screens: screens, windows: []).isEmpty)
    }

    @Test func partialWindowDoesNotCover() {
        let screens = [Screen(id: 1, frame: left)]
        #expect(FullScreenDetector.covered(screens: screens, windows: [CGRect(x: 0, y: 0, width: 900, height: 700)]).isEmpty)
    }

    @MainActor @Test func panelStyleShowsOverFullScreenSpaces() {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.applyOverlayStyle()
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.level.rawValue >= NSWindow.Level.floating.rawValue)
        #expect(!panel.canBecomeKey)
    }
}
