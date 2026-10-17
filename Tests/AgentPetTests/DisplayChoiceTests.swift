import Foundation
import Testing
@testable import AgentPet

struct DisplayChoiceTests {
    private let main = DisplayInfo(id: 1, name: "Main")
    private let side = DisplayInfo(id: 2, name: "Side")

    @Test func allDisplaysGetAPanel() {
        #expect(DisplayResolver.targets(choice: .all, displays: [main, side], main: main) == [main, side])
    }

    @Test func chosenDisplayIsFoundByID() {
        let choice = DisplayChoice.screen(id: 2, name: "Side")
        #expect(DisplayResolver.targets(choice: choice, displays: [main, side], main: main) == [side])
    }

    @Test func renumberedDisplayIsFoundByName() {
        let choice = DisplayChoice.screen(id: 9, name: "Side")
        #expect(DisplayResolver.targets(choice: choice, displays: [main, side], main: main) == [side])
    }

    @Test func missingDisplayFallsBackToMain() {
        let choice = DisplayChoice.screen(id: 9, name: "Gone")
        #expect(DisplayResolver.targets(choice: choice, displays: [main], main: main) == [main])
    }

    @Test func ambiguousNameFallsBackToMain() {
        let twin = DisplayInfo(id: 3, name: "Side")
        let choice = DisplayChoice.screen(id: 9, name: "Side")
        #expect(DisplayResolver.targets(choice: choice, displays: [main, side, twin], main: main) == [main])
    }

    @Test func choiceSurvivesEncoding() throws {
        let choice = DisplayChoice.screen(id: 2, name: "Side")
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(DisplayChoice.self, from: data) == choice)
    }

    @Test func bubbleGoesToThePointerDisplay() {
        #expect(DisplayResolver.bubbleHost(targets: [main, side], covered: [], pointerDisplay: 2, main: 1) == 2)
    }

    @Test func bubbleFallsBackToMainWithoutPointer() {
        #expect(DisplayResolver.bubbleHost(targets: [main, side], covered: [], pointerDisplay: nil, main: 1) == 1)
        #expect(DisplayResolver.bubbleHost(targets: [main, side], covered: [], pointerDisplay: 7, main: 1) == 1)
    }

    @Test func bubbleAvoidsCoveredDisplays() {
        #expect(DisplayResolver.bubbleHost(targets: [main, side], covered: [2], pointerDisplay: 2, main: 1) == 1)
        #expect(DisplayResolver.bubbleHost(targets: [main, side], covered: [1, 2], pointerDisplay: 2, main: 1) == nil)
    }
}
