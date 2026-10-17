import Foundation
import Observation
import PetCore

/// Owns the mood board, feeds it from the event log and re-evaluates decay on a timer.
@MainActor
@Observable
final class PetStore {
    static let refreshInterval: Duration = .seconds(1)
    static let recentDirectoryLimit = 8

    private(set) var pets: [PetState] = []
    private(set) var sessions: [SessionState] = []
    private(set) var bubbles: [String: PermissionBubble] = [:]
    private(set) var recentDirectories: [String] = []
    private(set) var hops: [String: Int] = [:]
    var expandedAgent: String?

    @ObservationIgnored var onRefresh: (@MainActor (Date) -> Void)?
    @ObservationIgnored private var board = MoodBoard()
    @ObservationIgnored private var tailer: EventLogTailer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var answered: Set<String> = []
    @ObservationIgnored private var pendingRequests: [PermissionRequest] = []
    @ObservationIgnored private var shownRequests: [String: String] = [:]

    func start() {
        let tailer = EventLogTailer { [weak self] events in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ingest(events) } }
        }
        tailer.start()
        self.tailer = tailer
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
                guard let self else { return }
                refresh()
            }
        }
    }

    func stop() {
        tailer?.stop()
        tailer = nil
        ticker?.cancel()
        ticker = nil
    }

    func ingest(_ events: [PetEvent]) {
        for event in events {
            board.apply(event)
            remember(directory: event.cwd)
        }
        refresh()
    }

    func sessions(of agent: String) -> [SessionState] {
        sessions.filter { $0.agent == agent }
    }

    func columns() -> [PetColumn] {
        pets.map { pet in
            let expanded = expandedAgent == pet.agent
            return PetColumn(
                agent: pet.agent,
                hasBubble: bubbles[pet.agent] != nil,
                listRows: expanded ? SessionListLayout.rowCount(sessions: sessions(of: pet.agent).count) : 0
            )
        }
    }

    func registerHop(agent: String) {
        hops[agent, default: 0] += 1
    }

    /// Writes the verdict once: a second click, or a click after expiry, writes nothing.
    func answer(
        _ bubble: PermissionBubble, decision: PermissionDecision,
        now: Date = Date(), directory: URL = PermissionBroker.directory
    ) {
        let id = bubble.request.id
        guard !answered.contains(id), bubble.request.expiresAt > now.timeIntervalSince1970,
              PermissionBroker.decision(for: id, in: directory) == nil else { return }
        do {
            try PermissionBroker.answer(id: id, decision: decision, in: directory)
        } catch {
            NSLog("agent-pet: could not record the permission answer: \(error)")
            return
        }
        answered.insert(id)
        refresh()
    }

    /// Shows the next pending request of the agent, if there is more than one.
    func showNextRequest(agent: String) {
        guard let current = shownRequests[agent],
              let next = BubbleSelector.next(after: current, requests: pendingRequests, sessions: sessions, agent: agent) else { return }
        shownRequests[agent] = next
        refresh()
    }

    private func remember(directory: String?) {
        guard let directory, SafeDirectory.isSafe(directory) else { return }
        recentDirectories.removeAll { $0 == directory }
        recentDirectories.insert(directory, at: 0)
        if recentDirectories.count > Self.recentDirectoryLimit {
            recentDirectories.removeLast(recentDirectories.count - Self.recentDirectoryLimit)
        }
    }

    private func refresh() {
        let now = Date()
        assignIfChanged(&pets, board.pets(at: now))
        assignIfChanged(&sessions, board.sessions(at: now))
        assignIfChanged(&bubbles, makeBubbles(now: now))
        if let expanded = expandedAgent, sessions(of: expanded).isEmpty {
            expandedAgent = nil
        }
        onRefresh?(now)
    }

    private func assignIfChanged<Value: Equatable>(_ target: inout Value, _ value: Value) {
        if target != value { target = value }
    }

    private func makeBubbles(now: Date) -> [String: PermissionBubble] {
        let pending = PermissionBroker.pending(now: now)
        answered.formIntersection(pending.map(\.id))
        pendingRequests = pending.filter { !answered.contains($0.id) }
        let selection = BubbleSelector.select(
            requests: pendingRequests, sessions: sessions, shown: shownRequests, now: now)
        shownRequests = selection.shown
        return selection.bubbles
    }
}
