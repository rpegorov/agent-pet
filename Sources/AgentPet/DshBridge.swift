import AppKit

/// Commands for the DeepSeek Harness plugin bridge on localhost.
enum DshBridge {
    static let bridgePorts = [50399, 50400, 50401]
    static let webURL = URL(string: "http://127.0.0.1:50306")
    private static let requestTimeout: TimeInterval = 1.5
    private static let successStatuses = 200..<300

    /// True when one of the bridge ports accepted the command.
    static func send(_ command: [String: String]) async -> Bool {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: command)
        } catch {
            NSLog("agent-pet: could not encode a DSH command: \(error)")
            return false
        }
        for port in bridgePorts where await post(body, to: port) {
            return true
        }
        return false
    }

    private static func post(_ body: Data, to port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/cmd") else { return false }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
            return successStatuses.contains(status)
        } catch {
            return false
        }
    }

    @MainActor static func openWebApp() {
        if let webURL { NSWorkspace.shared.open(webURL) }
    }

    @MainActor static func openSession(_ id: String) async {
        if await send(["type": "open-session", "sessionId": id]) { return }
        openWebApp()
    }

    @MainActor static func newChat() async {
        if await send(["type": "new-chat"]) { return }
        openWebApp()
    }
}
