import Foundation
import Testing
@testable import PetCore

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pet-permissions-\(UUID().uuidString)", isDirectory: true)
}

struct PermissionBrokerTests {
    private func request(ts: Double = Date().timeIntervalSince1970) -> PermissionRequest {
        PermissionRequest(agent: "claude", session: "s", tool: "Bash", summary: "Bash: ls", ts: ts)
    }

    @Test func requestAnswerRoundTrip() throws {
        let dir = tempDirectory()
        let req = request()
        try PermissionBroker.submit(req, in: dir)
        #expect(PermissionBroker.pending(in: dir) == [req])
        #expect(PermissionBroker.decision(for: req.id, in: dir) == nil)
        try PermissionBroker.answer(id: req.id, decision: .allow, in: dir)
        #expect(PermissionBroker.decision(for: req.id, in: dir) == .allow)
        #expect(PermissionBroker.pending(in: dir).isEmpty)
        PermissionBroker.remove(id: req.id, in: dir)
        #expect(PermissionBroker.decision(for: req.id, in: dir) == nil)
    }

    @Test func denyIsReported() throws {
        let dir = tempDirectory()
        let req = request()
        try PermissionBroker.submit(req, in: dir)
        try PermissionBroker.answer(id: req.id, decision: .deny, in: dir)
        #expect(PermissionBroker.decision(for: req.id, in: dir) == .deny)
    }

    @Test func answerNamingAnotherIdIsIgnored() throws {
        let dir = tempDirectory()
        let req = request()
        try PermissionBroker.submit(req, in: dir)
        let other = UUID().uuidString
        try PermissionBroker.answer(id: other, decision: .allow, in: dir)
        let forged = dir.appendingPathComponent(req.id + ".answer")
        try FileManager.default.copyItem(at: dir.appendingPathComponent(other + ".answer"), to: forged)
        #expect(PermissionBroker.decision(for: req.id, in: dir) == nil)
    }

    @Test func nonUUIDIdIsRejected() {
        let dir = tempDirectory()
        #expect(throws: PermissionBroker.BrokerError.self) {
            try PermissionBroker.answer(id: "../escape", decision: .allow, in: dir)
        }
    }

    @Test func pendingIsNewestFirst() throws {
        let dir = tempDirectory()
        let now = Date().timeIntervalSince1970
        let older = request(ts: now - 10)
        let newer = request(ts: now - 1)
        try PermissionBroker.submit(older, in: dir)
        try PermissionBroker.submit(newer, in: dir)
        #expect(PermissionBroker.pending(in: dir).map(\.id) == [newer.id, older.id])
    }

    @Test func staleRequestsAreIgnoredAndCleaned() throws {
        let dir = tempDirectory()
        let stale = request(ts: Date().timeIntervalSince1970 - PermissionBroker.staleAfter - 5)
        try PermissionBroker.submit(stale, in: dir)
        try PermissionBroker.answer(id: stale.id, decision: .allow, in: dir)
        #expect(PermissionBroker.pending(in: dir).isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers.isEmpty)
    }

    @Test func expiredRequestIsDroppedEvenWhenRecent() throws {
        let dir = tempDirectory()
        let now = Date().timeIntervalSince1970
        let expired = PermissionRequest(
            agent: "claude", session: "s", tool: "Bash", summary: "x", ts: now, expiresAt: now - 1)
        try PermissionBroker.submit(expired, in: dir)
        #expect(PermissionBroker.pending(in: dir).isEmpty)
    }

    @Test func deferDecisionRoundTripsAsDeferString() throws {
        let dir = tempDirectory()
        let req = request()
        try PermissionBroker.submit(req, in: dir)
        try PermissionBroker.answer(id: req.id, decision: .deferToAgent, in: dir)
        #expect(PermissionBroker.decision(for: req.id, in: dir) == .deferToAgent)
        let text = try String(contentsOf: dir.appendingPathComponent(req.id + ".answer"), encoding: .utf8)
        #expect(text.contains(#""defer""#))
    }

    @Test func orphanTemporaryFilesAreCleanedOnceStale() throws {
        let dir = tempDirectory()
        try PermissionBroker.submit(request(), in: dir)
        let orphan = dir.appendingPathComponent(UUID().uuidString + ".request.tmp")
        try Data("x".utf8).write(to: orphan)
        _ = PermissionBroker.pending(in: dir)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
        let old = Date().addingTimeInterval(-PermissionBroker.staleAfter - 5)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: orphan.path)
        _ = PermissionBroker.pending(in: dir)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func directoryIsPrivate() throws {
        let dir = tempDirectory()
        try PermissionBroker.submit(request(), in: dir)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int)
        #expect(mode & 0o077 == 0)
    }

    @Test func defaultDirectoryFollowsEventLogLocation() {
        #expect(PermissionBroker.directory.deletingLastPathComponent().path == EventLog.directory.path)
    }
}

struct OverlayPresenceTests {
    @Test func missingBeatMeansNotAlive() {
        #expect(!OverlayPresence.isAlive(maxAge: 6, in: tempDirectory()))
    }

    @Test func clearRemovesPresenceImmediately() {
        let dir = tempDirectory()
        OverlayPresence.beat(in: dir)
        OverlayPresence.clear(in: dir)
        #expect(!OverlayPresence.isAlive(maxAge: 6, in: dir))
    }

    @Test func beatMakesItAliveAndAgeExpiresIt() throws {
        let dir = tempDirectory()
        OverlayPresence.beat(in: dir)
        #expect(OverlayPresence.isAlive(maxAge: 6, in: dir))
        let file = dir.appendingPathComponent("overlay.alive")
        let old = Date().addingTimeInterval(-60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        #expect(!OverlayPresence.isAlive(maxAge: 6, in: dir))
        OverlayPresence.beat(in: dir)
        #expect(OverlayPresence.isAlive(maxAge: 6, in: dir))
    }
}

struct ProcessOriginTests {
    @Test func outermostBundleWinsForNestedHelpers() {
        let path = "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"
        #expect(ProcessOrigin.outermostBundlePath(in: path) == "/Applications/Claude.app")
    }

    @Test func plainExecutableHasNoBundle() {
        #expect(ProcessOrigin.outermostBundlePath(in: "/usr/bin/env") == nil)
        #expect(ProcessOrigin.outermostBundlePath(in: "/Applications/X.app/Contents/Helpers/tool") == nil)
    }

    @Test func capturingOwnProcessDoesNotCrash() {
        _ = ProcessOrigin.capture()
    }
}
