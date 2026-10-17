import CoreGraphics
import Testing
@testable import AgentPet

struct PanelPlacementTests {
    private let main = CGRect(x: 0, y: 62, width: 2560, height: 1348)
    private let side = CGRect(x: -1512, y: -65, width: 1512, height: 950)
    private let margin: CGFloat = 24

    @Test func anchorOnASecondDisplayIsKept() {
        let saved = CGPoint(x: -300, y: 100)
        #expect(PanelPlacement.restoredAnchor(saved, visibleFrames: [main, side], fallback: main, margin: margin) == saved)
    }

    @Test func anchorOfAnUnpluggedDisplayFallsBackToTheMainOne() {
        let saved = CGPoint(x: -300, y: 100)
        let anchor = PanelPlacement.restoredAnchor(saved, visibleFrames: [main], fallback: main, margin: margin)
        #expect(anchor.x >= main.minX && anchor.x <= main.maxX)
        #expect(anchor.y >= main.minY)
        let frame = CGRect(x: anchor.x - 300, y: anchor.y, width: 300, height: 280)
        let placed = PanelPlacement.clamped(frame, visibleFrames: [main], fallback: main)
        #expect(main.contains(placed))
    }

    @Test func frameIsClampedIntoTheDisplayHoldingItsCorner() {
        let frame = CGRect(x: -400, y: -50, width: 300, height: 280)
        let placed = PanelPlacement.clamped(frame, visibleFrames: [main, side], fallback: main)
        #expect(side.contains(placed))
        #expect(placed.minY == -50)
    }

    @Test func anchorBelowTheDockIsRaisedByTheMargin() {
        let saved = CGPoint(x: 2000, y: 10)
        let anchor = PanelPlacement.restoredAnchor(saved, visibleFrames: [main], fallback: main, margin: margin)
        #expect(anchor.y == main.minY + margin)
    }
}
