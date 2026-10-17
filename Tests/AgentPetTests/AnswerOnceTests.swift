import Foundation
import PetCore
import Testing
@testable import AgentPet

@MainActor
struct AnswerOnceTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func fixture(expiresAt: Double) throws -> (PermissionBubble, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pet-answer-\(UUID().uuidString)", isDirectory: true)
        let request = PermissionRequest(
            agent: "claude", session: "s1", tool: "Bash", summary: "x", ts: 900, toolInput: "ls", expiresAt: expiresAt)
        try PermissionBroker.submit(request, in: directory)
        let session = SessionState(agent: "claude", session: "s1", mood: .attention, label: "", startedAt: now, updatedAt: now)
        return (PermissionBubble(request: request, session: session, position: 1, total: 1), directory)
    }

    @Test func secondAnswerDoesNotFlipTheVerdict() throws {
        let (bubble, directory) = try fixture(expiresAt: 1_100)
        let store = PetStore()
        store.answer(bubble, decision: .deny, now: now, directory: directory)
        store.answer(bubble, decision: .allow, now: now, directory: directory)
        #expect(PermissionBroker.decision(for: bubble.request.id, in: directory) == .deny)
    }

    @Test func answerFromAnotherStoreCannotOverwriteEither() throws {
        let (bubble, directory) = try fixture(expiresAt: 1_100)
        try PermissionBroker.answer(id: bubble.request.id, decision: .deferToAgent, in: directory)
        PetStore().answer(bubble, decision: .allow, now: now, directory: directory)
        #expect(PermissionBroker.decision(for: bubble.request.id, in: directory) == .deferToAgent)
    }

    @Test func answerAfterExpiryWritesNothing() throws {
        let (bubble, directory) = try fixture(expiresAt: 999)
        PetStore().answer(bubble, decision: .allow, now: now, directory: directory)
        #expect(PermissionBroker.decision(for: bubble.request.id, in: directory) == nil)
    }
}
