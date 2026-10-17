import Testing
@testable import AgentPet

@MainActor
struct LayoutTests {
    @Test func windowIsWideEnoughForTheBubble() {
        let columns = [PetColumn(agent: "claude", hasBubble: true, listRows: 0)]
        #expect(PetRowLayout.windowSize(columns: columns).width >= PopoverMetrics.bubbleWidth)
    }

    @Test func windowIsWideEnoughForTheList() {
        let columns = [PetColumn(agent: "claude", hasBubble: false, listRows: 2)]
        #expect(PetRowLayout.windowSize(columns: columns).width >= PopoverMetrics.listWidth)
    }
}
