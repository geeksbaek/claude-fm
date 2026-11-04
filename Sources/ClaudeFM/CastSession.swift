import Foundation
import Network
import Security

/// 크롬캐스트 하나와 TLS(8009)로 이야기한다. 기본 미디어 수신기를 띄우고, 무대 영상을 불러오게 하고,
/// 심장 박동과 상태를 지켜본다. 일은 자기 큐에서 하고, 소식은 `callbackQueue` 로 알린다.
final class CastSession: @unchecked Sendable {
    enum Event: Equatable {
        /// TLS 가 이어졌다. TV 쪽에서 본 이 Mac 의 주소를 같이 준다.
        case connected(localHost: String?)
        /// 처음 보내는 기기라 TV 화면에서 허용을 기다린다.
        case waitingForApproval
        /// 수신기 앱이 떠서 영상을 불러올 수 있다.
        case ready
        /// BUFFERING · PLAYING · PAUSED
        case media(String)
        /// 재생이 멈췄다. FINISHED · CANCELLED · INTERRUPTED · ERROR
        case mediaIdle(String)
        /// 영상을 불러오지 못했다.
        case loadFailed(String)
        /// 끝났다. 더는 소식이 없다.
        case ended(EndReason)
    }

    enum EndReason: Equatable {
        /// 이쪽에서 멈췄다.
        case stopped
        /// TV 나 Google Home, 다른 기기에서 앱을 닫았다.
        case closedOnReceiver
        case connectFailed(String)
        case launchFailed(String)
        case lost(String)
    }

    let endpoint: NWEndpoint
    private let secure: Bool
    private let callbackQueue: DispatchQueue
    private let queue = DispatchQueue(label: "io.github.geeksbaek.claude-fm.cast")
    private let senderID = CastMessage.sender
    var onEvent: ((Event) -> Void)?

    private var connection: NWConnection?
    private var reader = CastFrameReader()
    private var requestID = 0
    private var finished = false
    private var connected = false
    private var lastHeard: TimeInterval = 0
    private var heartbeat: DispatchSourceTimer?
    private var launchRequestID: Int?
    private var launchSentAt: TimeInterval?
    private var launchDeadline: TimeInterval?
    private var launchAcknowledged = false
    private var app: CastApplication?
    private var loadRequestID: Int?
    private var loadSentAt: TimeInterval?
    private var mediaSessionID: Int?
    /// 우리 LOAD 전에 있던 미디어 세션. 이들의 소식은 우리 영상 소식이 아니다.
    private var oldMediaSessions = Set<Int>()

    /// 앱을 띄우는 데 기다리는 시간. TV 에서 허용을 기다리면 더 늘린다.
    static let launchTimeout: TimeInterval = 25
    static let approvalTimeout: TimeInterval = 90
    /// 이만큼 아무 소식이 없으면 끊긴 것으로 본다.
    static let silenceTimeout: TimeInterval = 16

    init(endpoint: NWEndpoint, secure: Bool = true, callbackQueue: DispatchQueue = .main) {
        self.endpoint = endpoint
        self.secure = secure
        self.callbackQueue = callbackQueue
    }

    func start() {
        queue.async { self.open(ipv4Only: true) }
    }

    /// 수신기에 영상을 불러오게 한다. 앞서 불러온 영상이 있으면 바꾼다.
    func load(_ media: CastMedia) {
        queue.async {
            guard !self.finished, let app = self.app else { return }
            if let current = self.mediaSessionID { self.oldMediaSessions.insert(current) }
            self.mediaSessionID = nil
            let id = self.nextRequestID()
            self.loadRequestID = id
            self.loadSentAt = self.now()
            self.send(CastRequest.load(media, sessionID: app.sessionID, requestID: id), namespace: CastNamespace.media, to: app.transportID)
        }
    }

    /// TV 의 수신기 앱을 닫고 연결을 끊는다.
    func stop() {
        queue.async { self.shutdown(.stopped, closeApp: true, completion: nil) }
    }

    /// 앱을 끝낼 때. 닫는 메시지가 나갈 때까지 잠깐 기다린다.
    func stopAndWait(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        queue.async { self.shutdown(.stopped, closeApp: true) { done.signal() } }
        _ = done.wait(timeout: .now() + timeout)
    }

    // MARK: - 연결

    private func open(ipv4Only: Bool) {
        guard !finished else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let parameters: NWParameters
        if secure {
            // 크롬캐스트는 스스로 서명한 인증서를 쓴다. 같은 네트워크의 기기라 그대로 받는다.
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
            parameters = NWParameters(tls: tls, tcp: tcp)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        // TV 가 Mac 에 되돌아올 주소가 IPv4 이도록 먼저 IPv4 로 붙어 본다.
        if ipv4Only, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state, of: connection, ipv4Only: ipv4Only)
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self, !self.finished, !self.connected, self.connection === connection else { return }
            self.retry(after: connection, ipv4Only: ipv4Only, reason: "시간 초과")
        }
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection, ipv4Only: Bool) {
        guard connection === self.connection, !finished else { return }
        switch state {
        case .ready:
            guard !connected else { return }
            connected = true
            lastHeard = now()
            emit(.connected(localHost: Self.hostText(connection.currentPath?.localEndpoint)))
            send(CastRequest.connect(), namespace: CastNamespace.connection, to: CastMessage.receiver)
            startHeartbeat()
            receive(on: connection)
            launch()
        case .waiting(let error), .failed(let error):
            if connected {
                end(.lost(error.debugDescription))
            } else {
                retry(after: connection, ipv4Only: ipv4Only, reason: error.debugDescription)
            }
        default:
            break
        }
    }

    /// IPv4 로 안 되면 아무 주소로나 한 번 더 붙어 본다.
    private func retry(after connection: NWConnection, ipv4Only: Bool, reason: String) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        self.connection = nil
        if ipv4Only {
            open(ipv4Only: false)
        } else {
            end(.connectFailed(reason))
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, connection === self.connection, !self.finished else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.reader.append(data) {
                        self.handle(message)
                        if self.finished { return }
                    }
                } catch {
                    self.end(.lost("bad frame"))
                    return
                }
            }
            if isComplete {
                self.end(.lost("closed"))
            } else if let error {
                self.end(.lost(error.debugDescription))
            } else {
                self.receive(on: connection)
            }
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, !self.finished else { return }
            if self.now() - self.lastHeard > Self.silenceTimeout {
                self.end(.lost("heartbeat"))
                return
            }
            if let deadline = self.launchDeadline, self.now() > deadline {
                self.end(.launchFailed("timeout"))
                return
            }
            self.send(CastRequest.ping(), namespace: CastNamespace.heartbeat, to: CastMessage.receiver)
        }
        timer.resume()
        heartbeat = timer
    }

    private func launch() {
        let id = nextRequestID()
        launchRequestID = id
        launchSentAt = now()
        launchDeadline = now() + Self.launchTimeout
        send(CastRequest.launch(requestID: id), namespace: CastNamespace.receiver, to: CastMessage.receiver)
    }

    // MARK: - 받은 메시지

    private func handle(_ message: CastMessage) {
        lastHeard = now()
        let (event, requestID) = CastInbound.parse(message)
        switch event {
        case .ping:
            send(CastRequest.pong(), namespace: CastNamespace.heartbeat, to: message.source)
        case .pong, .other:
            break
        case .close:
            if let app, message.source == app.transportID {
                end(.closedOnReceiver)
            } else if message.source == CastMessage.receiver {
                end(.lost("receiver closed"))
            }
        case .receiverStatus(let status):
            receiverStatus(status, requestID: requestID)
        case .launchStatus(let text):
            let upper = text.uppercased()
            if upper.contains("DENIED") || upper.contains("REJECT") {
                end(.launchFailed("denied"))
            } else if upper.contains("PENDING") {
                launchDeadline = now() + Self.approvalTimeout
                emit(.waitingForApproval)
            }
        case .launchError(let reason):
            if app == nil { end(.launchFailed(reason)) }
        case .receiverError(let reason):
            if app == nil, requestID == launchRequestID { end(.launchFailed(reason)) }
        case .mediaStatus(let list):
            guard let app, message.source == app.transportID else { return }
            mediaStatus(list, requestID: requestID)
        case .mediaError(let reason):
            guard app != nil, let loadRequestID else { return }
            if requestID == nil || requestID == 0 || requestID == loadRequestID { emit(.loadFailed(reason)) }
        }
    }

    private func receiverStatus(_ status: CastReceiverStatus, requestID: Int?) {
        let ours = status.application(CastRequest.mediaReceiverAppID)
        if let current = app {
            guard let ours, !ours.transportID.isEmpty else { return end(.closedOnReceiver) }
            guard ours.sessionID != current.sessionID else { return }
            // 늦게 온 LAUNCH 대답이 새 세션을 알리면 그쪽으로 옮겨 탄다. 아니면 다른 기기가 앱을 새로 띄운 것이다.
            guard requestID != nil, requestID == launchRequestID else { return end(.closedOnReceiver) }
            adopt(ours)
            return
        }
        guard let launchSentAt else { return }
        if requestID != nil, requestID == launchRequestID { launchAcknowledged = true }
        // LAUNCH 대답을 받았거나, 대답에 번호를 안 다는 기기라도 조금 기다린 뒤에는 떠 있는 앱을 받아들인다.
        guard let ours, !ours.transportID.isEmpty,
              launchAcknowledged || now() - launchSentAt > 4 else { return }
        adopt(ours)
    }

    private func adopt(_ application: CastApplication) {
        app = application
        launchDeadline = nil
        send(CastRequest.connect(), namespace: CastNamespace.connection, to: application.transportID)
        emit(.ready)
    }

    /// 우리 LOAD 의 대답에 실린 미디어 세션만 따라간다. 번호를 안 다는 기기라면 조금 기다린 뒤 새 세션을 받아들인다.
    private func mediaStatus(_ list: [CastMediaStatus], requestID: Int?) {
        for status in list {
            guard let loadRequestID else {
                if let id = status.mediaSessionID { oldMediaSessions.insert(id) }
                continue
            }
            if let id = status.mediaSessionID {
                if oldMediaSessions.contains(id) { continue }
                if mediaSessionID == nil {
                    let waited = loadSentAt.map { now() - $0 > 3 } ?? false
                    guard requestID == loadRequestID || waited else { continue }
                    mediaSessionID = id
                }
                guard id == mediaSessionID else { continue }
            } else if requestID != loadRequestID {
                continue
            }
            if status.playerState == "IDLE" {
                emit(.mediaIdle(status.idleReason ?? ""))
            } else {
                emit(.media(status.playerState))
            }
        }
    }

    // MARK: - 끝내기

    private func end(_ reason: EndReason) {
        shutdown(reason, closeApp: false, completion: nil)
    }

    private func shutdown(_ reason: EndReason, closeApp: Bool, completion: (() -> Void)?) {
        guard !finished else {
            completion?()
            return
        }
        finished = true
        heartbeat?.cancel()
        heartbeat = nil
        emit(.ended(reason))
        guard let connection else {
            completion?()
            return
        }
        guard connected, connection.state == .ready else {
            connection.cancel()
            self.connection = nil
            completion?()
            return
        }
        if closeApp, let app {
            send(CastRequest.stop(sessionID: app.sessionID, requestID: nextRequestID()), namespace: CastNamespace.receiver,
                 to: CastMessage.receiver)
            send(CastRequest.close(), namespace: CastNamespace.connection, to: app.transportID)
        }
        var done = false
        let close = { [weak self] in
            guard !done else { return }
            done = true
            connection.cancel()
            if self?.connection === connection { self?.connection = nil }
            completion?()
        }
        send(CastRequest.close(), namespace: CastNamespace.connection, to: CastMessage.receiver) { close() }
        // 대답이 늦어도 오래 붙잡지 않는다.
        queue.asyncAfter(deadline: .now() + 1) { close() }
    }

    // MARK: - 도우미

    private func send(_ payload: String, namespace: String, to destination: String, completion: (() -> Void)? = nil) {
        guard let connection else {
            completion?()
            return
        }
        let message = CastMessage(source: senderID, destination: destination, namespace: namespace, payload: payload)
        connection.send(content: message.framed(), completion: .contentProcessed { [weak self] _ in
            guard let completion else { return }
            if let self {
                self.queue.async { completion() }
            } else {
                completion()
            }
        })
    }

    private func emit(_ event: Event) {
        callbackQueue.async { self.onEvent?(event) }
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// TV 가 이 Mac 에 되돌아올 주소. IPv6 링크 로컬은 영역 이름 없이는 닿지 않아 뺀다.
    static func hostText(_ endpoint: NWEndpoint?) -> String? {
        guard case let .hostPort(host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address):
            let raw = [UInt8](address.rawValue)
            guard raw.count == 4 else { return nil }
            return raw.map(String.init).joined(separator: ".")
        case .ipv6(let address):
            let raw = [UInt8](address.rawValue)
            guard raw.count == 16 else { return nil }
            if raw[0..<10].allSatisfy({ $0 == 0 }), raw[10] == 0xFF, raw[11] == 0xFF {
                return raw[12...].map(String.init).joined(separator: ".")
            }
            if raw[0] == 0xFE, raw[1] & 0xC0 == 0x80 { return nil }
            let groups = stride(from: 0, to: 16, by: 2).map { String(UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]), radix: 16) }
            return "[" + groups.joined(separator: ":") + "]"
        case .name(let name, _):
            return name
        @unknown default:
            return nil
        }
    }
}
