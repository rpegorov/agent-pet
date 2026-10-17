import Foundation
import PetCore

/// Feeds synthetic events so the overlay can be checked without real agents.
@MainActor
final class DemoFeeder {
    static let agents = ["claude", "codex", "deepseek", "glm"]
    static let stepDuration: Duration = .seconds(5)
    static let labels: [Mood: String] = [
        .idle: "", .working: "Bash", .attention: "needs approval", .complete: "done",
    ]

    private let store: PetStore
    private var task: Task<Void, Never>?

    init(store: PetStore) {
        self.store = store
    }

    func run() {
        task?.cancel()
        task = Task { [store] in
            let moods = Mood.allCases
            for step in 0..<moods.count {
                let events = Self.agents.enumerated().map { offset, agent in
                    let mood = moods[(step + offset) % moods.count]
                    return PetEvent(
                        agent: agent, session: "demo-\(agent)",
                        mood: Self.signal(for: mood), label: Self.labels[mood] ?? ""
                    )
                }
                store.ingest(events)
                do {
                    try await Task.sleep(for: Self.stepDuration)
                } catch {
                    return
                }
            }
            store.ingest(Self.agents.map {
                PetEvent(agent: $0, session: "demo-\($0)", mood: .ended)
            })
        }
    }

    private static func signal(for mood: Mood) -> Signal {
        switch mood {
        case .idle: .idle
        case .working: .working
        case .attention: .attention
        case .complete: .complete
        }
    }
}
