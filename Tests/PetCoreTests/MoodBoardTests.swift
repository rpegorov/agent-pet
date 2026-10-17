import Foundation
import Testing
@testable import PetCore

struct MoodBoardTests {
    private let base = 1_000_000.0

    private func event(_ agent: String, _ session: String, _ mood: Signal, at offset: Double = 0, label: String = "") -> PetEvent {
        PetEvent(agent: agent, session: session, mood: mood, label: label, ts: base + offset)
    }

    private func at(_ offset: Double) -> Date { Date(timeIntervalSince1970: base + offset) }

    @Test func workingDecaysToIdle() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working))
        #expect(board.pets(at: at(MoodBoard.workingTimeout)).first?.mood == .working)
        #expect(board.pets(at: at(MoodBoard.workingTimeout + 1)).isEmpty)
    }

    @Test func completeDecaysToIdle() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .complete))
        #expect(board.pets(at: at(MoodBoard.completeTimeout)).first?.mood == .complete)
        #expect(board.pets(at: at(MoodBoard.completeTimeout + 1)).isEmpty)
    }

    @Test func attentionPersistsThenDisappears() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .attention))
        #expect(board.pets(at: at(MoodBoard.attentionTimeout - 1)).first?.mood == .attention)
        #expect(board.pets(at: at(MoodBoard.attentionTimeout + 1)).isEmpty)
    }

    @Test func idleSessionIsInvisible() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .idle))
        #expect(board.pets(at: at(1)).isEmpty)
        #expect(board.sessions(at: at(1)).isEmpty)
    }

    @Test func staleSessionIsDropped() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working))
        #expect(board.pets(at: at(MoodBoard.sessionTimeout + 1)).isEmpty)
    }

    @Test func endedRemovesSession() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working))
        board.apply(event("claude", "s", .ended, at: 1))
        #expect(board.pets(at: at(2)).isEmpty)
    }

    @Test func priorityAcrossSessionsAndLabelOfWinner() throws {
        var board = MoodBoard()
        board.apply(event("claude", "a", .complete, label: "done"))
        board.apply(event("claude", "b", .working, label: "Bash"))
        var pet = try #require(board.pets(at: at(1)).first)
        #expect(pet.mood == .working)
        #expect(pet.label == "Bash")
        #expect(pet.sessions == 2)
        board.apply(event("claude", "c", .attention, at: 1, label: "Edit"))
        pet = try #require(board.pets(at: at(2)).first)
        #expect(pet.mood == .attention)
        #expect(pet.label == "Edit")
    }

    @Test func petsSortedByAgentName() {
        var board = MoodBoard()
        board.apply(event("glm", "x", .working))
        board.apply(event("claude", "y", .working))
        #expect(board.pets(at: at(1)).map(\.agent) == ["claude", "glm"])
    }

    @Test func olderEventDoesNotOverwriteNewer() {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working, at: 5))
        board.apply(event("claude", "s", .idle, at: 1))
        #expect(board.pets(at: at(6)).first?.mood == .working)
    }

    @Test func endedAfterCompleteKeepsPetVisibleUntilCompleteDecays() {
        var board = MoodBoard()
        board.apply(event("codex", "s", .complete))
        board.apply(event("codex", "s", .ended, at: 0.07))
        #expect(board.pets(at: at(1)).first?.mood == .complete)
        #expect(board.pets(at: at(MoodBoard.completeTimeout + 1)).isEmpty)
    }

    @Test func endedAfterAttentionLingersThenDrops() {
        var board = MoodBoard()
        board.apply(event("codex", "s", .attention))
        board.apply(event("codex", "s", .ended, at: 1))
        #expect(board.pets(at: at(1 + MoodBoard.endedLingerTimeout)).first?.mood == .attention)
        #expect(board.pets(at: at(1 + MoodBoard.endedLingerTimeout + 1)).isEmpty)
    }

    @Test func eventAfterEndedRevivesSession() {
        var board = MoodBoard()
        board.apply(event("codex", "s", .complete))
        board.apply(event("codex", "s", .ended, at: 1))
        board.apply(event("codex", "s", .working, at: 2))
        #expect(board.pets(at: at(MoodBoard.completeTimeout + 5)).first?.mood == .working)
    }

    @Test func agentWithOnlyIdleSessionsIsOmittedAndDoesNotCount() throws {
        var board = MoodBoard()
        board.apply(event("claude", "a", .idle))
        board.apply(event("claude", "b", .working))
        board.apply(event("glm", "c", .idle))
        let pets = board.pets(at: at(1))
        #expect(pets.map(\.agent) == ["claude"])
        #expect(try #require(pets.first).sessions == 1)
    }

    @Test func sessionsAreOrderedAttentionWorkingCompleteThenNewestFirst() {
        var board = MoodBoard()
        board.apply(event("claude", "done", .complete, at: 5))
        board.apply(event("claude", "old", .working, at: 1))
        board.apply(event("codex", "new", .working, at: 3))
        board.apply(event("claude", "ask", .attention, at: 0))
        #expect(board.sessions(at: at(6)).map(\.session) == ["ask", "new", "old", "done"])
    }

    @Test func sessionStateCarriesOriginAndPermission() throws {
        var board = MoodBoard()
        var ask = event("claude", "s", .attention, at: 2, label: "Bash")
        ask.cwd = "/work/repo"
        ask.app = "com.apple.Terminal"
        ask.tty = "/dev/ttys004"
        ask.detail = "Bash: rm -rf x"
        ask.permission = "req-1"
        board.apply(ask)
        let state = try #require(board.sessions(at: at(3)).first)
        #expect(state.id == "claude:s")
        #expect(state.mood == .attention)
        #expect(state.cwd == "/work/repo")
        #expect(state.app == "com.apple.Terminal")
        #expect(state.tty == "/dev/ttys004")
        #expect(state.detail == "Bash: rm -rf x")
        #expect(state.permission == "req-1")
        #expect(state.updatedAt == at(2))
    }

    @Test func laterEventWithoutOriginKeepsEarlierOrigin() throws {
        var board = MoodBoard()
        var first = event("claude", "s", .working)
        first.cwd = "/work/repo"
        first.app = "com.apple.Terminal"
        board.apply(first)
        board.apply(event("claude", "s", .working, at: 1))
        let state = try #require(board.sessions(at: at(2)).first)
        #expect(state.cwd == "/work/repo")
        #expect(state.app == "com.apple.Terminal")
    }

    @Test func permissionIsClearedWhenSessionResumes() throws {
        var board = MoodBoard()
        var ask = event("claude", "s", .attention)
        ask.permission = "req-1"
        board.apply(ask)
        board.apply(event("claude", "s", .working, at: 1))
        let state = try #require(board.sessions(at: at(2)).first)
        #expect(state.permission == nil)
    }

    @Test func startedAtIsFirstWorkingEventOfTheActivity() throws {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working, at: 0))
        board.apply(event("claude", "s", .working, at: 30))
        board.apply(event("claude", "s", .attention, at: 40))
        board.apply(event("claude", "s", .working, at: 50))
        #expect(try #require(board.sessions(at: at(51)).first).startedAt == at(0))
        board.apply(event("claude", "s", .complete, at: 60))
        #expect(try #require(board.sessions(at: at(61)).first).startedAt == at(0))
        board.apply(event("claude", "s", .working, at: 70))
        #expect(try #require(board.sessions(at: at(71)).first).startedAt == at(70))
    }

    @Test func startedAtResetsAfterWorkingGoesStale() throws {
        var board = MoodBoard()
        board.apply(event("claude", "s", .working, at: 0))
        board.apply(event("claude", "s", .working, at: MoodBoard.workingTimeout + 5))
        let state = try #require(board.sessions(at: at(MoodBoard.workingTimeout + 6)).first)
        #expect(state.startedAt == at(MoodBoard.workingTimeout + 5))
    }
}
