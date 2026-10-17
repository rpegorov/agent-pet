import AppKit
import Testing
@testable import AgentPet

struct FullScreenTests {
    private let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let right = CGRect(x: 1000, y: 0, width: 1200, height: 900)

    @Test func windowOnAnotherDisplayDoesNotHideThePanel() {
        let panel = CGRect(x: 100, y: 500, width: 300, height: 280)
        #expect(!FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [right]))
    }

    @Test func windowFillingThePanelsDisplayHidesIt() {
        let panel = CGRect(x: 1500, y: 500, width: 300, height: 280)
        #expect(FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [right]))
        #expect(!FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [left]))
    }

    @Test func partialWindowDoesNotCount() {
        let panel = CGRect(x: 100, y: 100, width: 300, height: 280)
        #expect(!FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [CGRect(x: 0, y: 0, width: 900, height: 700)]))
    }

    @Test func panelStraddlingDisplaysUsesTheLargerOverlap() {
        let panel = CGRect(x: 900, y: 100, width: 300, height: 280)
        #expect(FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [right]))
    }

    @Test func panelOutsideEveryDisplayNeverHides() {
        let panel = CGRect(x: 5000, y: 5000, width: 300, height: 280)
        #expect(!FullScreenDetector.covers(panelFrame: panel, screens: [left, right], windows: [left, right]))
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
