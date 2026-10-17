import Foundation
import Testing
@testable import PetCore

private func tempLog() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pet-tests-\(UUID().uuidString)")
        .appendingPathComponent("events.jsonl")
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [PetEvent] = []

    func add(_ batch: [PetEvent]) {
        lock.lock(); defer { lock.unlock() }
        events.append(contentsOf: batch)
    }

    var all: [PetEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    func waitFor(count: Int, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // lint-allow: test-sleep polling step bounded by a deadline
        }
        return all.count >= count
    }
}

struct EventLogTests {
    @Test func appendWritesOneValidLinePerEvent() throws {
        let url = tempLog()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .working, label: "x"), to: url)
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .complete), to: url)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        let decoded = try JSONDecoder().decode(PetEvent.self, from: Data(lines[0].utf8))
        #expect(decoded.mood == .working)
        #expect(decoded.label == "x")
    }

    @Test func rotatesWhenLargerThanThreshold() throws {
        let url = tempLog()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .idle), to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: UInt8(ascii: " "), count: EventLog.rotationThreshold))
        try handle.close()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .working), to: url)
        let rotated = URL(fileURLWithPath: url.path + ".1")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let current = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(current.count == 1)
    }
}

struct EventLogFileTests {
    @Test func logIsOwnerOnly() throws {
        let url = tempLog()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .idle), to: url)
        let file = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        let dir = try #require(FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int)
        #expect(file & 0o077 == 0)
        #expect(dir & 0o077 == 0)
    }

    @Test func concurrentAppendsAllLandAsValidLines() async throws {
        let url = tempLog()
        let writers = 40
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<writers {
                group.addTask {
                    try EventLog.append(PetEvent(agent: "a", session: "s\(index)", mood: .working), to: url)
                }
            }
            try await group.waitForAll()
        }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == writers)
        for line in lines { _ = try JSONDecoder().decode(PetEvent.self, from: Data(line.utf8)) }
    }
}

struct EventLogTailerTests {
    @Test func replaysRecentAndFollowsAppends() async throws {
        let url = tempLog()
        let old = PetEvent(agent: "a", session: "s", mood: .working, ts: Date().timeIntervalSince1970 - EventLogTailer.replayWindow - 60)
        let recent = PetEvent(agent: "a", session: "s", mood: .attention)
        try EventLog.append(old, to: url)
        try EventLog.append(recent, to: url)
        let collector = Collector()
        let tailer = EventLogTailer(url: url) { collector.add($0) }
        tailer.start()
        defer { tailer.stop() }
        #expect(await collector.waitFor(count: 1))
        #expect(collector.all == [recent])
        let next = PetEvent(agent: "b", session: "t", mood: .complete)
        try EventLog.append(next, to: url)
        #expect(await collector.waitFor(count: 2))
        #expect(collector.all.last == next)
    }

    @Test func waitsForMissingFileAndSkipsMalformedLines() async throws {
        let url = tempLog()
        let collector = Collector()
        let tailer = EventLogTailer(url: url) { collector.add($0) }
        tailer.start()
        defer { tailer.stop() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage\n".utf8).write(to: url)
        let event = PetEvent(agent: "a", session: "s", mood: .working)
        try EventLog.append(event, to: url)
        #expect(await collector.waitFor(count: 1))
        #expect(collector.all == [event])
    }

    @Test func followsAcrossRotation() async throws {
        let url = tempLog()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .idle), to: url)
        let collector = Collector()
        let tailer = EventLogTailer(url: url) { collector.add($0) }
        tailer.start()
        defer { tailer.stop() }
        #expect(await collector.waitFor(count: 1))
        try FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".1"))
        let after = PetEvent(agent: "a", session: "s", mood: .working, label: "after")
        try EventLog.append(after, to: url)
        #expect(await collector.waitFor(count: 2))
        #expect(collector.all.last == after)
    }

    @Test func eventsAppendedBeforeRotationAreStillDelivered() async throws {
        let url = tempLog()
        try EventLog.append(PetEvent(agent: "a", session: "s", mood: .idle), to: url)
        let collector = Collector()
        let tailer = EventLogTailer(url: url) { collector.add($0) }
        tailer.start()
        defer { tailer.stop() }
        #expect(await collector.waitFor(count: 1))
        let unread = PetEvent(agent: "a", session: "s", mood: .attention, label: "unread")
        let fresh = PetEvent(agent: "a", session: "s", mood: .working, label: "fresh")
        try EventLog.append(unread, to: url)
        try FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".1"))
        try EventLog.append(fresh, to: url)
        #expect(await collector.waitFor(count: 3))
        #expect(Array(collector.all.suffix(2)) == [unread, fresh])
    }
}
