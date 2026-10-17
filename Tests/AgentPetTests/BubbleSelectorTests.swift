import Foundation
import PetCore
import Testing
@testable import AgentPet

struct BubbleSelectorTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func session(_ id: String, agent: String = "claude") -> SessionState {
        SessionState(agent: agent, session: id, mood: .attention, label: "", startedAt: now, updatedAt: now)
    }

    private func request(_ id: String, session: String, ts: Double, agent: String = "claude", expires: Double = 1_100) -> PermissionRequest {
        PermissionRequest(id: id, agent: agent, session: session, tool: "Bash", summary: id, ts: ts, expiresAt: expires)
    }

    @Test func bubblesJoinSessionsByAgentAndSession() {
        let result = BubbleSelector.select(
            requests: [request("r1", session: "s2", ts: 10)],
            sessions: [session("s1"), session("s2")], shown: [:], now: now)
        #expect(result.bubbles["claude"]?.session.session == "s2")
    }

    @Test func requestWithoutVisibleSessionIsNotShown() {
        let result = BubbleSelector.select(
            requests: [request("r1", session: "gone", ts: 10)], sessions: [session("s1")], shown: [:], now: now)
        #expect(result.bubbles.isEmpty)
    }

    @Test func newerRequestNeverReplacesTheShownOne() {
        let sessions = [session("s1"), session("s2")]
        let first = BubbleSelector.select(
            requests: [request("old", session: "s1", ts: 10)], sessions: sessions, shown: [:], now: now)
        let second = BubbleSelector.select(
            requests: [request("old", session: "s1", ts: 10), request("new", session: "s2", ts: 20)],
            sessions: sessions, shown: first.shown, now: now)
        #expect(second.bubbles["claude"]?.request.id == "old")
        #expect(second.bubbles["claude"]?.total == 2)
    }

    @Test func nextRequestAppearsOnceTheShownOneIsGone() {
        let sessions = [session("s1"), session("s2")]
        let result = BubbleSelector.select(
            requests: [request("new", session: "s2", ts: 20)], sessions: sessions, shown: ["claude": "old"], now: now)
        #expect(result.bubbles["claude"]?.request.id == "new")
    }

    @Test func expiredRequestsAreDropped() {
        let result = BubbleSelector.select(
            requests: [request("r1", session: "s1", ts: 10, expires: 999)], sessions: [session("s1")], shown: [:], now: now)
        #expect(result.bubbles.isEmpty)
    }

    @Test func nextCyclesThroughTheQueue() {
        let sessions = [session("s1"), session("s2")]
        let requests = [request("a", session: "s1", ts: 10), request("b", session: "s2", ts: 20)]
        #expect(BubbleSelector.next(after: "a", requests: requests, sessions: sessions, agent: "claude") == "b")
        #expect(BubbleSelector.next(after: "b", requests: requests, sessions: sessions, agent: "claude") == "a")
        #expect(BubbleSelector.next(after: "a", requests: [requests[0]], sessions: sessions, agent: "claude") == nil)
    }

    @Test func agentsKeepSeparateQueues() {
        let sessions = [session("s1"), session("c1", agent: "codex")]
        let result = BubbleSelector.select(
            requests: [request("r1", session: "s1", ts: 10), request("r2", session: "c1", ts: 11, agent: "codex")],
            sessions: sessions, shown: [:], now: now)
        #expect(result.bubbles["claude"]?.request.id == "r1")
        #expect(result.bubbles["codex"]?.request.id == "r2")
    }
}
