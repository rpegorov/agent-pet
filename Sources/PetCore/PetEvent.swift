import Foundation

public enum Mood: String, Codable, Sendable, CaseIterable {
    case idle, working, attention, complete
}

public enum Signal: String, Codable, Sendable {
    case idle, working, attention, complete, ended
}

public struct PetEvent: Codable, Sendable, Equatable {
    public static let protocolVersion = 1

    public var v: Int
    public var agent: String
    public var session: String
    public var mood: Signal
    public var label: String
    public var ts: Double
    public var cwd: String?
    public var app: String?
    public var tty: String?
    public var detail: String?
    public var permission: String?

    public init(
        agent: String,
        session: String,
        mood: Signal,
        label: String = "",
        ts: Double = Date().timeIntervalSince1970,
        cwd: String? = nil,
        app: String? = nil,
        tty: String? = nil,
        detail: String? = nil,
        permission: String? = nil
    ) {
        self.v = Self.protocolVersion
        self.agent = agent
        self.session = session
        self.mood = mood
        self.label = label
        self.ts = ts
        self.cwd = cwd
        self.app = app
        self.tty = tty
        self.detail = detail
        self.permission = permission
    }
}

public struct SessionState: Equatable, Sendable, Identifiable {
    public var id: String { agent + ":" + session }
    public let agent: String
    public let session: String
    public let mood: Mood
    public let label: String
    public let cwd: String?
    public let app: String?
    public let tty: String?
    public let detail: String?
    public let permission: String?
    public let startedAt: Date
    public let updatedAt: Date

    public init(
        agent: String, session: String, mood: Mood, label: String,
        cwd: String? = nil, app: String? = nil, tty: String? = nil,
        detail: String? = nil, permission: String? = nil,
        startedAt: Date, updatedAt: Date
    ) {
        self.agent = agent
        self.session = session
        self.mood = mood
        self.label = label
        self.cwd = cwd
        self.app = app
        self.tty = tty
        self.detail = detail
        self.permission = permission
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

public struct PetState: Equatable, Sendable, Identifiable {
    public var id: String { agent }
    public let agent: String
    public let mood: Mood
    public let label: String
    public let sessions: Int

    public init(agent: String, mood: Mood, label: String, sessions: Int) {
        self.agent = agent
        self.mood = mood
        self.label = label
        self.sessions = sessions
    }
}
