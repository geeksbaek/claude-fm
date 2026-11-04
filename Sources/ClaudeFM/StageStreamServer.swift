import Foundation
import Network

/// TV 가 무대 영상을 가져가도록 HTTP 로 내준다. 같은 네트워크의 모든 주소에서 듣고,
/// 무작위 열쇠가 든 경로로 온 요청에만 답한다. TV 로 보내는 동안만 켠다.
final class StageStreamServer: @unchecked Sendable {
    let store: StageSegmentStore
    let token: String
    var basePath: String { "/live/\(token)/" }

    private let queue = DispatchQueue(label: "io.github.geeksbaek.claude-fm.stream.server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var stopped = false
    private let counters = NSLock()
    private var remoteCount = 0
    private var remoteAt: TimeInterval?
    private var portNumber: UInt16?

    /// 끝없는 MP4 손님이 이만큼 못 받아 가면 끊는다.
    private static let streamBacklogLimit = 24 * 1024 * 1024

    init(store: StageSegmentStore, token: String = StageStreamServer.makeToken()) {
        self.store = store
        self.token = token
    }

    static func makeToken() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// 이 Mac 이 아닌 기기(TV)에서 온 요청 수와 마지막 시각.
    var remoteRequests: (count: Int, last: TimeInterval?) {
        counters.lock()
        defer { counters.unlock() }
        return (remoteCount, remoteAt)
    }

    var port: UInt16? {
        counters.lock()
        defer { counters.unlock() }
        return portNumber
    }

    /// 정한 문(8765)을 먼저 열어 보고, 막혀 있으면 아무 문이나 연다. 끝나면 열린 문 번호를 서버 큐에서 알린다.
    func start(preferredPort: UInt16 = 8765, completion: @escaping (UInt16?) -> Void) {
        queue.async {
            var reported = false
            let report = { (port: UInt16?) in
                guard !reported else { return }
                reported = true
                completion(port)
            }
            if let port = NWEndpoint.Port(rawValue: preferredPort) {
                self.listen(on: port, fallback: true, report: report)
            } else {
                self.listen(on: .any, fallback: false, report: report)
            }
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.listener?.cancel()
            self.listener = nil
            for client in self.clients.values { self.drop(client) }
            self.clients.removeAll()
        }
    }

    private func listen(on port: NWEndpoint.Port, fallback: Bool, report: @escaping (UInt16?) -> Void) {
        guard !stopped else { return report(nil) }
        // 문을 남과 나눠 쓰지 않는다. 8765 가 쓰이고 있으면 실패하고 아무 문이나 연다.
        guard let listener = try? NWListener(using: .tcp, on: port) else {
            if fallback { listen(on: .any, fallback: false, report: report) } else { report(nil) }
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                let number = listener.port?.rawValue
                self.counters.lock()
                self.portNumber = number
                self.counters.unlock()
                report(number)
            case .failed:
                listener.cancel()
                self.listener = nil
                if fallback, !self.stopped {
                    self.listen(on: .any, fallback: false, report: report)
                } else {
                    report(nil)
                }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    // MARK: - 손님

    private final class Client {
        let connection: NWConnection
        var answered = false
        var subscription: Int?
        var pending = 0

        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { return connection.cancel() }
        let client = Client(connection)
        let id = ObjectIdentifier(client)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled:
                self.drop(client)
                self.clients[ObjectIdentifier(client)] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        read(client, buffer: [])
        // 머리를 끝까지 보내지 않는 손님은 오래 붙잡지 않는다.
        queue.asyncAfter(deadline: .now() + 15) { [weak client] in
            guard let client, !client.answered else { return }
            client.connection.cancel()
        }
    }

    private func read(_ client: Client, buffer: [UInt8]) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(contentsOf: data) }
            switch StageHTTPRequest.parse(buffer) {
            case .request(let request):
                self.respond(to: request, client: client)
            case .invalid:
                self.finish(client, with: StageHTTPRouter.plain(400), includeBody: true)
            case .incomplete:
                if isComplete || error != nil {
                    client.connection.cancel()
                } else {
                    self.read(client, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: StageHTTPRequest, client: Client) {
        client.answered = true
        // 우리 길을 아는 요청만 TV 가 받아 간 것으로 센다. 같은 망의 다른 기기가 두드린 것은 세지 않는다.
        if request.path.hasPrefix(basePath), Self.isRemote(client.connection.endpoint) {
            counters.lock()
            remoteCount += 1
            remoteAt = ProcessInfo.processInfo.systemUptime
            counters.unlock()
        }
        let response = StageHTTPRouter.respond(to: request, store: store, basePath: basePath)
        guard response.streams, request.method == "GET" else {
            finish(client, with: response, includeBody: request.method != "HEAD")
            return
        }
        // 끝없는 MP4: 머리와 첫머리·최근 조각을 보내고, 새 조각이 나올 때마다 이어 보낸다.
        guard let subscription = store.subscribe(lead: 2, { [weak self, weak client] data in
            self?.queue.async {
                guard let self, let client else { return }
                self.push(data, to: client)
            }
        }) else {
            finish(client, with: StageHTTPRouter.plain(503, extra: [("Retry-After", "1")]), includeBody: true)
            return
        }
        client.subscription = subscription.id
        var payload = response.head()
        payload.append(subscription.backlog)
        push(payload, to: client)
    }

    private func push(_ data: Data, to client: Client) {
        guard clients[ObjectIdentifier(client)] != nil else { return }
        guard client.pending + data.count <= Self.streamBacklogLimit else {
            client.connection.cancel()
            return
        }
        client.pending += data.count
        client.connection.send(content: data, completion: .contentProcessed { [weak self, weak client] error in
            self?.queue.async {
                guard let client else { return }
                client.pending -= data.count
                if error != nil { client.connection.cancel() }
            }
        })
    }

    private func finish(_ client: Client, with response: StageHTTPResponse, includeBody: Bool) {
        client.answered = true
        var payload = response.head()
        if includeBody { payload.append(response.body) }
        client.connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                               completion: .contentProcessed { _ in client.connection.cancel() })
    }

    private func drop(_ client: Client) {
        if let id = client.subscription {
            store.unsubscribe(id)
            client.subscription = nil
        }
        client.connection.cancel()
    }

    /// 켜져 있는 네트워크(Wi-Fi·이더넷)의 IPv4 주소. TV 연결에서 주소를 못 읽었을 때 쓴다. en0 을 앞에 둔다.
    static func localIPv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [(name: String, address: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard let socket = entry.pointee.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let address = socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            // 169.254 는 이어진 네트워크가 없을 때 스스로 붙인 주소다.
            guard bytes.count == 4, !(bytes[0] == 169 && bytes[1] == 254) else { continue }
            found.append((String(cString: entry.pointee.ifa_name), bytes.map(String.init).joined(separator: ".")))
        }
        return found.sorted { ($0.name == "en0" ? 0 : 1, $0.name) < ($1.name == "en0" ? 0 : 1, $1.name) }.map(\.address)
    }

    /// 이 Mac 자신에서 온 요청인지.
    static func isRemote(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return true }
        switch host {
        case .ipv4(let address):
            return !address.isLoopback
        case .ipv6(let address):
            if address.isLoopback { return false }
            let raw = [UInt8](address.rawValue)
            // ::ffff:127.x.x.x
            if raw.count == 16, raw[0..<10].allSatisfy({ $0 == 0 }), raw[10] == 0xFF, raw[11] == 0xFF { return raw[12] != 127 }
            return true
        default:
            return true
        }
    }
}
