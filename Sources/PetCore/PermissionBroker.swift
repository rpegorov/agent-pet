import Foundation

public enum PermissionDecision: String, Codable, Sendable {
    case allow, deny, deferToAgent = "defer"
}

public struct PermissionRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let agent: String
    public let session: String
    public let tool: String
    public let summary: String
    public let ts: Double
    public let toolInput: String
    public let truncated: Bool
    public let expiresAt: Double

    public init(
        id: String = UUID().uuidString, agent: String, session: String,
        tool: String, summary: String, ts: Double = Date().timeIntervalSince1970,
        toolInput: String = "", truncated: Bool = false, expiresAt: Double? = nil
    ) {
        self.id = id
        self.agent = agent
        self.session = session
        self.tool = tool
        self.summary = summary
        self.ts = ts
        self.toolInput = toolInput
        self.truncated = truncated
        self.expiresAt = expiresAt ?? ts + PermissionBroker.staleAfter
    }
}

// File-based mailbox between the emitter (waits for a verdict) and the overlay (collects it).
public enum PermissionBroker {
    public static let staleAfter: TimeInterval = 120
    private static let directoryName = "permissions"
    private static let requestSuffix = ".request"
    private static let answerSuffix = ".answer"
    private static let temporarySuffix = ".tmp"
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    public struct BrokerError: Error, CustomStringConvertible {
        public let description: String
    }

    private struct Answer: Codable {
        let id: String
        let decision: PermissionDecision
    }

    public static var directory: URL {
        EventLog.directory.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func submit(_ request: PermissionRequest, in directory: URL = directory) throws {
        try write(JSONEncoder().encode(request), name: request.id + requestSuffix, id: request.id, in: directory)
    }

    public static func answer(id: String, decision: PermissionDecision, in directory: URL = directory) throws {
        try write(JSONEncoder().encode(Answer(id: id, decision: decision)), name: id + answerSuffix, id: id, in: directory)
    }

    // An answer naming a different id than its file is ignored.
    public static func decision(for id: String, in directory: URL = directory) -> PermissionDecision? {
        guard isValid(id),
              let answer = decodeFile(Answer.self, at: directory.appendingPathComponent(id + answerSuffix)),
              answer.id == id else { return nil }
        return answer.decision
    }

    public static func remove(id: String, in directory: URL = directory) {
        guard isValid(id) else { return }
        for suffix in [requestSuffix, answerSuffix] {
            removeFile(directory.appendingPathComponent(id + suffix))
        }
    }

    public static func pending(now: Date = Date(), in directory: URL = directory) -> [PermissionRequest] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] // lint-allow: sw-try-optional a missing directory means nothing is pending
        var requests: [PermissionRequest] = []
        for name in names {
            if name.hasSuffix(temporarySuffix) {
                removeStaleTemporary(directory.appendingPathComponent(name), now: now)
            } else if name.hasSuffix(requestSuffix) || name.hasSuffix(answerSuffix) {
                let id = String(name.prefix(while: { $0 != "." }))
                if let request = requestIfFresh(id: id, now: now, in: directory) {
                    if decision(for: id, in: directory) == nil { requests.append(request) }
                } else {
                    remove(id: id, in: directory)
                }
            }
        }
        return requests.sorted { $0.ts > $1.ts }
    }

    private static func requestIfFresh(id: String, now: Date, in directory: URL) -> PermissionRequest? {
        guard isValid(id),
              let request = decodeFile(PermissionRequest.self, at: directory.appendingPathComponent(id + requestSuffix)),
              request.id == id,
              now.timeIntervalSince1970 <= request.expiresAt else { return nil }
        return request
    }

    // Missing or malformed files are the normal "no answer yet" / "garbage" cases, not failures.
    private static func decodeFile<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil } // lint-allow: sw-try-optional absent file means no data
        return try? JSONDecoder().decode(type, from: data) // lint-allow: sw-try-optional malformed file is treated as absent
    }

    private static func removeFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            FileHandle.standardError.write(Data("agent-pet: cannot remove \(url.lastPathComponent): \(error)\n".utf8))
        }
    }

    // A writer killed between create and rename leaves its temporary file behind.
    private static func removeStaleTemporary(_ url: URL, now: Date) {
        var info = stat()
        guard stat(url.path, &info) == 0,
              now.timeIntervalSince1970 - TimeInterval(info.st_mtimespec.tv_sec) > staleAfter else { return }
        removeFile(url)
    }

    // Ids become file names, so anything but a UUID is rejected.
    private static func isValid(_ id: String) -> Bool { UUID(uuidString: id) != nil }

    private static func write(_ data: Data, name: String, id: String, in directory: URL) throws {
        guard isValid(id) else { throw BrokerError(description: "invalid request id") }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions])
        let target = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(name + temporarySuffix)
        try data.write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: temporary.path)
        guard rename(temporary.path, target.path) == 0 else {
            throw BrokerError(description: "rename failed: errno \(errno)")
        }
    }
}
