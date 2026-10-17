import Foundation

public enum EventLog {
    public static let rotationThreshold = 512 * 1024
    private static let logEnvironmentKey = "AGENT_PET_LOG"
    private static let defaultRelativePath = ".agent-pet/events.jsonl"
    private static let rotatedSuffix = ".1"
    private static let lockSuffix = ".lock"
    private static let filePermissions: mode_t = 0o600
    private static let directoryPermissions = 0o700
    private static let newline = UInt8(ascii: "\n")

    public struct WriteError: Error, CustomStringConvertible {
        public let description: String
    }

    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment[logEnvironmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultRelativePath)
    }

    public static var directory: URL { defaultURL.deletingLastPathComponent() }

    // The log holds prompts' tool names and working directories, so the directory is owner-only.
    public static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: directoryPermissions])
    }

    public static func append(_ event: PetEvent, to url: URL = defaultURL) throws {
        var line = try JSONEncoder().encode(event)
        line.append(newline)
        try prepareDirectory(url.deletingLastPathComponent())
        let lock = open(url.path + lockSuffix, O_RDWR | O_CREAT, filePermissions)
        guard lock >= 0 else { throw WriteError(description: "lock open failed: errno \(errno)") }
        // Closing the descriptor releases the lock; it keeps rotate and append atomic across emitters.
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw WriteError(description: "lock failed: errno \(errno)") }
        try rotateIfNeeded(url)
        try writeAppending(line, to: url)
    }

    private static func rotateIfNeeded(_ url: URL) throws {
        var info = stat()
        guard stat(url.path, &info) == 0, Int(info.st_size) > rotationThreshold else { return }
        // rename(2) replaces any previous rotated file atomically.
        guard rename(url.path, url.path + rotatedSuffix) == 0 || errno == ENOENT else {
            throw WriteError(description: "rotate failed: errno \(errno)")
        }
    }

    private static func writeAppending(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, filePermissions)
        guard fd >= 0 else { throw WriteError(description: "open failed: errno \(errno)") }
        defer { close(fd) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == data.count else { throw WriteError(description: "write failed: errno \(errno)") }
    }
}
