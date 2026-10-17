import Foundation
import PetCore

private let maxPayloadBytes = 1 << 20
private let stdinChunk = 64 * 1024

func readStdin() -> Data {
    var data = Data()
    while data.count < maxPayloadBytes {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: stdinChunk), !chunk.isEmpty else { break } // lint-allow: sw-try-optional a closed or broken stdin just ends the payload
        data.append(chunk)
    }
    return data.prefix(maxPayloadBytes)
}

func options(from args: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var index = 0
    while index + 1 < args.count {
        if args[index].hasPrefix("--") {
            result[String(args[index].dropFirst(2))] = args[index + 1]
            index += 2
        } else {
            index += 1
        }
    }
    return result
}

func record(_ event: PetEvent) {
    do {
        try EventLog.append(event)
    } catch {
        FileHandle.standardError.write(Data("agent-pet-emit: \(error)\n".utf8))
    }
}

func withOrigin(_ event: PetEvent) -> PetEvent {
    let origin = ProcessOrigin.capture()
    var result = event
    result.app = origin.app
    result.tty = origin.tty
    return result
}
