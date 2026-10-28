import Foundation
import Network

/// Active while our Chrome extension reports being in a Meet call (heartbeat every 10 s).
final class MeetSignal: Signal {
    let name = "meet"
    let token: String
    private var lastBeat: Date?
    private let listener: NWListener

    static func authorized(requestHead: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let lines = requestHead.components(separatedBy: "\r\n")
        guard lines.first?.hasPrefix("POST /meet ") == true else { return false }
        return lines.dropFirst().contains { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            return parts.count == 2
                && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "x-autostart-token"
                && parts[1].trimmingCharacters(in: .whitespaces) == token
        }
    }

    init(port: UInt16 = 47615, token: String) throws {
        self.token = token
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.stateUpdateHandler = { state in
            // Exit so launchd's KeepAlive retries; staying up would leave Meet silently dead.
            if case .failed(let e) = state { log("meet listener failed, exiting: \(e)"); exit(1) }
        }
        listener.start(queue: .main)
    }

    func isActive(now: Date) -> Bool {
        guard let b = lastBeat else { return false }
        return now.timeIntervalSince(b) < 20
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ok = Self.authorized(requestHead: head, token: self.token)
            if ok { self.lastBeat = Date() }
            let status = ok ? "204 No Content" : "403 Forbidden"
            let resp = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }
}
