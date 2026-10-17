import Foundation
import PetCore
import Testing
@testable import AgentPet

struct PresentationTests {
    private static let sessionID = "5e9d6b1a-77c2"

    private func session(cwd: String?) -> SessionState {
        SessionState(agent: "claude", session: Self.sessionID, mood: .working, label: "", cwd: cwd, startedAt: .now, updatedAt: .now)
    }

    @Test func projectIsLastPathComponent() {
        #expect(SessionPresentation.projectName(of: session(cwd: "/Users/me/agent-pet")) == "agent-pet")
    }

    @Test func projectFallsBackToSessionTail() {
        let tail = String(Self.sessionID.suffix(6))
        #expect(SessionPresentation.projectName(of: session(cwd: nil)) == tail)
        #expect(SessionPresentation.projectName(of: session(cwd: "/")) == tail)
    }

    @Test func negativeElapsedClampsToZero() {
        let start = Date(timeIntervalSince1970: 100)
        #expect(SessionPresentation.elapsed(since: start, now: start.addingTimeInterval(-5))
            == SessionPresentation.elapsed(since: start, now: start))
    }
}

@MainActor
struct AttentionMonitorTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func waiting(updatedAgo: TimeInterval) -> SessionState {
        SessionState(
            agent: "claude", session: "s1", mood: .attention, label: "",
            startedAt: now, updatedAt: now.addingTimeInterval(-updatedAgo))
    }

    @Test func freshAttentionIsReportedOnce() {
        let monitor = AttentionMonitor()
        #expect(monitor.update(sessions: [waiting(updatedAgo: 1)], now: now, quiet: false).entered.count == 1)
        #expect(monitor.update(sessions: [waiting(updatedAgo: 2)], now: now.addingTimeInterval(1), quiet: false).entered.isEmpty)
    }

    @Test func replayedAttentionStaysSilent() {
        let monitor = AttentionMonitor()
        #expect(monitor.update(sessions: [waiting(updatedAgo: 600)], now: now, quiet: false).entered.isEmpty)
    }

    @Test func quietModeSwallowsTheSignal() {
        let monitor = AttentionMonitor()
        #expect(monitor.update(sessions: [waiting(updatedAgo: 1)], now: now, quiet: true).entered.isEmpty)
    }

    @Test func persistentAttentionBecomesOverdueOnce() {
        let monitor = AttentionMonitor()
        _ = monitor.update(sessions: [waiting(updatedAgo: 1)], now: now, quiet: false)
        let later = now.addingTimeInterval(AttentionMonitor.notifyAfter + 5)
        #expect(monitor.update(sessions: [waiting(updatedAgo: 1)], now: later, quiet: false).overdue.count == 1)
        #expect(monitor.update(sessions: [waiting(updatedAgo: 1)], now: later.addingTimeInterval(1), quiet: false).overdue.isEmpty)
    }
}
