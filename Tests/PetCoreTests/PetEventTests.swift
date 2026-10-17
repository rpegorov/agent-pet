import Foundation
import Testing
@testable import PetCore

struct PetEventTests {
    @Test func lineWithoutNewFieldsStillDecodes() throws {
        let line = #"{"v":1,"agent":"claude","session":"s","mood":"working","label":"Bash","ts":12.5}"#
        let event = try JSONDecoder().decode(PetEvent.self, from: Data(line.utf8))
        #expect(event.label == "Bash")
        #expect(event.cwd == nil && event.app == nil && event.tty == nil)
        #expect(event.detail == nil && event.permission == nil)
    }

    @Test func absentFieldsAreOmittedFromJSON() throws {
        let data = try JSONEncoder().encode(PetEvent(agent: "a", session: "s", mood: .idle))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys).isDisjoint(with: ["cwd", "app", "tty", "detail", "permission"]))
    }

    @Test func originFieldsRoundTrip() throws {
        let event = PetEvent(
            agent: "a", session: "s", mood: .attention, cwd: "/w", app: "com.apple.Terminal",
            tty: "/dev/ttys001", detail: "Bash: ls", permission: "p")
        let decoded = try JSONDecoder().decode(PetEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
    }
}
