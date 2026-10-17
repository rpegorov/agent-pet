import Foundation

public final class EventLogTailer: @unchecked Sendable { // lint-allow: sw-unchecked-sendable mutable state is confined to the serial queue
    public static let replayWindow: TimeInterval = 30 * 60
    private static let pollInterval: DispatchTimeInterval = .milliseconds(150)
    private static let newline = UInt8(ascii: "\n")

    private struct Stream {
        let handle: FileHandle
        let inode: UInt64
    }

    private let url: URL
    private let onEvents: @Sendable ([PetEvent]) -> Void
    private let queue = DispatchQueue(label: "agent-pet.tailer")
    private var timer: DispatchSourceTimer?
    // The properties below are only touched on `queue`.
    private var stream: Stream?
    private var offset: UInt64 = 0
    private var replaying = true

    public init(url: URL = EventLog.defaultURL, onEvents: @escaping @Sendable ([PetEvent]) -> Void) {
        self.url = url
        self.onEvents = onEvents
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: Self.pollInterval)
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            closeStream()
        }
    }

    private func poll() {
        var info = stat()
        let pathInode = stat(url.path, &info) == 0 ? UInt64(info.st_ino) : nil
        if let current = stream, current.inode != pathInode {
            // The path now names another file: finish the old one before switching.
            deliver(readNewLines(from: current.handle))
            closeStream()
            replaying = false
        }
        if stream == nil, let pathInode { openStream(inode: pathInode) }
        if let current = stream { deliver(readNewLines(from: current.handle)) }
    }

    private func openStream(inode: UInt64) {
        do {
            stream = Stream(handle: try FileHandle(forReadingFrom: url), inode: inode)
            offset = 0
        } catch {
            report("open failed", error)
        }
    }

    private func closeStream() {
        guard let current = stream else { return }
        do {
            try current.handle.close()
        } catch {
            report("close failed", error)
        }
        stream = nil
        offset = 0
    }

    // A failed read leaves the offset unchanged, so the next poll retries.
    private func readNewLines(from handle: FileHandle) -> [PetEvent] {
        do {
            let size = try handle.seekToEnd()
            if size < offset { offset = 0 }
            guard size > offset else { return [] }
            try handle.seek(toOffset: offset)
            guard let chunk = try handle.read(upToCount: Int(size - offset)),
                  let lastNewline = chunk.lastIndex(of: Self.newline) else { return [] }
            let complete = chunk[chunk.startIndex...lastNewline]
            offset += UInt64(complete.count)
            return parse(complete)
        } catch {
            report("read failed", error)
            return []
        }
    }

    private func parse(_ data: Data) -> [PetEvent] {
        let decoder = JSONDecoder()
        return data.split(separator: Self.newline).compactMap {
            try? decoder.decode(PetEvent.self, from: Data($0)) // lint-allow: sw-try-optional malformed lines in a shared log are skipped
        }
    }

    private func deliver(_ events: [PetEvent]) {
        var batch = events
        if replaying, !events.isEmpty {
            let cutoff = Date().timeIntervalSince1970 - Self.replayWindow
            batch = batch.filter { $0.ts >= cutoff }
            replaying = false
        }
        if !batch.isEmpty { onEvents(batch) }
    }

    private func report(_ what: String, _ error: Error) {
        FileHandle.standardError.write(Data("agent-pet: tailer \(what): \(error)\n".utf8))
    }
}
