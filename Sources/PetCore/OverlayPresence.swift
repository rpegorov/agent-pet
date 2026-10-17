import Foundation

// The overlay proves it is running by touching a file; the emitter only blocks on a verdict while it is fresh.
public enum OverlayPresence {
    private static let fileName = "overlay.alive"
    private static let nanosecondsPerSecond = 1e9

    private static func url(in directory: URL) -> URL { directory.appendingPathComponent(fileName) }

    public static func beat(in directory: URL = EventLog.directory) {
        let path = url(in: directory).path
        if utimes(path, nil) == 0 { return }
        do {
            try EventLog.prepareDirectory(directory)
        } catch {
            FileHandle.standardError.write(Data("agent-pet: cannot create \(directory.path): \(error)\n".utf8))
            return
        }
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    public static func clear(in directory: URL = EventLog.directory) {
        unlink(url(in: directory).path)
    }

    public static func isAlive(maxAge: TimeInterval, in directory: URL = EventLog.directory) -> Bool {
        var info = stat()
        guard stat(url(in: directory).path, &info) == 0 else { return false }
        let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / nanosecondsPerSecond
        return Date().timeIntervalSince1970 - modified <= maxAge
    }
}
