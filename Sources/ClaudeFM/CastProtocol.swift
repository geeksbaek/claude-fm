import Foundation

// 크롬캐스트(CASTV2) 메시지를 짓고 읽는다. 네트워크와 화면 없이 Foundation 만 쓴다.
// 한 통은 4바이트 큰 끝 길이 뒤에 protobuf `CastMessage` 가 붙은 꼴이다.
//   1 protocol_version(varint, 0) 2 source_id 3 destination_id 4 namespace
//   5 payload_type(varint, 0 글 · 1 이진) 6 payload_utf8 7 payload_binary

/// 크롬캐스트가 쓰는 이름 공간.
enum CastNamespace {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let media = "urn:x-cast:com.google.cast.media"
}

enum CastWireError: Error, Equatable {
    case truncated
    case badWireType(Int)
    case frameTooLarge(Int)
    case missingField(Int)
    case badText(Int)
}

/// CASTV2 메시지 한 통. 보내는 쪽은 늘 글(JSON)을 싣고, 인증용 이진 내용은 받기만 한다.
struct CastMessage: Equatable {
    var source: String
    var destination: String
    var namespace: String
    var payload: String
    var binary: Data?

    /// 보내는 쪽과 받는 쪽 기본 이름.
    static let sender = "sender-0"
    static let receiver = "receiver-0"

    init(source: String, destination: String, namespace: String, payload: String, binary: Data? = nil) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
        self.binary = binary
    }

    /// 길이 머리 없는 protobuf 본문.
    func encoded() -> Data {
        var out = [UInt8]()
        out.reserveCapacity(payload.utf8.count + namespace.utf8.count + 64)
        Protobuf.appendVarint(field: 1, 0, to: &out)
        Protobuf.appendBytes(field: 2, Array(source.utf8), to: &out)
        Protobuf.appendBytes(field: 3, Array(destination.utf8), to: &out)
        Protobuf.appendBytes(field: 4, Array(namespace.utf8), to: &out)
        if let binary {
            Protobuf.appendVarint(field: 5, 1, to: &out)
            Protobuf.appendBytes(field: 7, Array(binary), to: &out)
        } else {
            Protobuf.appendVarint(field: 5, 0, to: &out)
            Protobuf.appendBytes(field: 6, Array(payload.utf8), to: &out)
        }
        return Data(out)
    }

    /// 4바이트 큰 끝 길이를 앞에 붙인 한 통.
    func framed() -> Data {
        let body = encoded()
        let length = UInt32(body.count)
        var out = Data([UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        out.append(body)
        return out
    }

    /// protobuf 본문을 읽는다. 모르는 칸은 건너뛴다.
    init(decoding data: Data) throws {
        var reader = Protobuf.Reader(Array(data))
        var source: String?
        var destination: String?
        var namespace: String?
        var payload = ""
        var binary: Data?
        var payloadType: UInt64 = 0
        while !reader.atEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                let value = try reader.varint()
                if field == 5 { payloadType = value }
            case 1:
                try reader.skip(8)
            case 2:
                let bytes = try reader.lengthDelimited()
                func text() throws -> String {
                    guard let value = String(bytes: bytes, encoding: .utf8) else { throw CastWireError.badText(field) }
                    return value
                }
                switch field {
                case 2: source = try text()
                case 3: destination = try text()
                case 4: namespace = try text()
                case 6: payload = try text()
                case 7: binary = Data(bytes)
                default: break
                }
            case 5:
                try reader.skip(4)
            default:
                throw CastWireError.badWireType(wire)
            }
        }
        guard let source else { throw CastWireError.missingField(2) }
        guard let destination else { throw CastWireError.missingField(3) }
        guard let namespace else { throw CastWireError.missingField(4) }
        self.init(source: source, destination: destination, namespace: namespace,
                  payload: payload, binary: payloadType == 1 ? (binary ?? Data()) : nil)
    }
}

/// 손으로 쓴 작은 protobuf 도우미. CastMessage 에 필요한 varint 와 길이 붙은 칸만 다룬다.
enum Protobuf {
    static func appendVarint(_ value: UInt64, to out: inout [UInt8]) {
        var rest = value
        while rest >= 0x80 {
            out.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        out.append(UInt8(rest))
    }

    static func appendVarint(field: Int, _ value: UInt64, to out: inout [UInt8]) {
        appendVarint(UInt64(field << 3), to: &out)
        appendVarint(value, to: &out)
    }

    static func appendBytes(field: Int, _ bytes: [UInt8], to out: inout [UInt8]) {
        appendVarint(UInt64(field << 3 | 2), to: &out)
        appendVarint(UInt64(bytes.count), to: &out)
        out.append(contentsOf: bytes)
    }

    struct Reader {
        private let bytes: [UInt8]
        private var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        var atEnd: Bool { index >= bytes.count }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < bytes.count, shift < 64 else { throw CastWireError.truncated }
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        mutating func lengthDelimited() throws -> [UInt8] {
            let length = try varint()
            guard length <= UInt64(bytes.count - index) else { throw CastWireError.truncated }
            let end = index + Int(length)
            defer { index = end }
            return Array(bytes[index..<end])
        }

        mutating func skip(_ count: Int) throws {
            guard bytes.count - index >= count else { throw CastWireError.truncated }
            index += count
        }
    }
}

/// TLS 로 들어온 바이트를 모아 다 온 통만 꺼낸다. 크롬캐스트는 한 통을 64KB 아래로 보낸다.
struct CastFrameReader {
    static let maximumFrame = 64 * 1024
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) throws -> [CastMessage] {
        buffer.append(contentsOf: data)
        var messages: [CastMessage] = []
        while buffer.count >= 4 {
            let length = Int(buffer[0]) << 24 | Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
            guard length <= Self.maximumFrame else { throw CastWireError.frameTooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            let body = Data(buffer[4..<(4 + length)])
            buffer.removeFirst(4 + length)
            messages.append(try CastMessage(decoding: body))
        }
        return messages
    }
}

// MARK: - JSON

enum CastJSON {
    static func text(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

/// TV 에 불러오게 할 무대 영상.
struct CastMedia: Equatable {
    enum Format: Equatable {
        /// fMP4 조각으로 된 HLS 라이브.
        case hls
        /// 끝없이 이어 보내는 fMP4 한 줄기.
        case progressive
    }

    var url: String
    var format: Format
    var title: String
    var subtitle: String
    var imageURL: String?

    var contentType: String {
        switch format {
        case .hls: return "application/vnd.apple.mpegurl"
        case .progressive: return "video/mp4"
        }
    }

    var json: [String: Any] {
        var metadata: [String: Any] = ["metadataType": 0, "title": title, "subtitle": subtitle]
        if let imageURL { metadata["images"] = [["url": imageURL]] }
        var media: [String: Any] = [
            "contentId": url,
            "contentUrl": url,
            "contentType": contentType,
            "streamType": "LIVE",
            "metadata": metadata,
        ]
        if format == .hls {
            media["hlsSegmentFormat"] = "fmp4"
            media["hlsVideoSegmentFormat"] = "fmp4"
        }
        return media
    }
}

/// 보내는 메시지의 글.
enum CastRequest {
    /// 크롬캐스트 기본 미디어 수신기.
    static let mediaReceiverAppID = "CC1AD845"

    static func connect() -> String {
        CastJSON.text(["type": "CONNECT", "origin": [String: Any](), "userAgent": "Claude FM"])
    }

    static func close() -> String { CastJSON.text(["type": "CLOSE"]) }
    static func ping() -> String { CastJSON.text(["type": "PING"]) }
    static func pong() -> String { CastJSON.text(["type": "PONG"]) }

    static func getStatus(requestID: Int) -> String {
        CastJSON.text(["type": "GET_STATUS", "requestId": requestID])
    }

    static func launch(appID: String = mediaReceiverAppID, requestID: Int) -> String {
        CastJSON.text(["type": "LAUNCH", "appId": appID, "requestId": requestID])
    }

    static func stop(sessionID: String, requestID: Int) -> String {
        CastJSON.text(["type": "STOP", "sessionId": sessionID, "requestId": requestID])
    }

    static func load(_ media: CastMedia, sessionID: String, requestID: Int) -> String {
        CastJSON.text(["type": "LOAD", "requestId": requestID, "sessionId": sessionID, "autoplay": true, "media": media.json])
    }

    static func mediaStatus(requestID: Int) -> String {
        CastJSON.text(["type": "GET_STATUS", "requestId": requestID])
    }
}

// MARK: - 받은 메시지

/// 수신기에서 돌고 있는 앱 하나.
struct CastApplication: Equatable {
    var appID: String
    var sessionID: String
    var transportID: String
    var displayName: String
    var namespaces: [String]
}

struct CastReceiverStatus: Equatable {
    var applications: [CastApplication]

    func application(_ appID: String) -> CastApplication? {
        applications.first { $0.appID == appID }
    }
}

struct CastMediaStatus: Equatable {
    var mediaSessionID: Int?
    /// IDLE · BUFFERING · PLAYING · PAUSED
    var playerState: String
    /// IDLE 일 때만. FINISHED · CANCELLED · INTERRUPTED · ERROR
    var idleReason: String?
}

enum CastInbound: Equatable {
    case ping
    case pong
    case close
    case receiverStatus(CastReceiverStatus)
    /// 앱을 띄우는 중간 상태. 처음 보내는 기기면 TV 에서 허용을 기다리기도 한다.
    case launchStatus(String)
    case launchError(String)
    case mediaStatus([CastMediaStatus])
    /// 미디어를 불러오지 못했거나 요청이 거절됐다.
    case mediaError(String)
    case receiverError(String)
    case other(String)

    /// 메시지를 읽고 요청 번호를 같이 돌려준다. 수신기가 먼저 보낸 소식은 번호가 0 이거나 없다.
    static func parse(_ message: CastMessage) -> (event: CastInbound, requestID: Int?) {
        guard message.binary == nil, let json = CastJSON.object(message.payload) else { return (.other("binary"), nil) }
        let type = json["type"] as? String ?? ""
        let requestID = (json["requestId"] as? NSNumber)?.intValue
        let reason = (json["reason"] as? String) ?? (json["detailedErrorCode"] as? NSNumber)?.stringValue ?? type
        switch message.namespace {
        case CastNamespace.heartbeat:
            if type == "PING" { return (.ping, requestID) }
            if type == "PONG" { return (.pong, requestID) }
        case CastNamespace.connection:
            if type == "CLOSE" { return (.close, requestID) }
        case CastNamespace.receiver:
            switch type {
            case "RECEIVER_STATUS":
                let status = json["status"] as? [String: Any] ?? [:]
                let apps = (status["applications"] as? [[String: Any]] ?? []).map(parseApplication)
                return (.receiverStatus(CastReceiverStatus(applications: apps)), requestID)
            case "LAUNCH_STATUS":
                return (.launchStatus(json["status"] as? String ?? json["launchRequestStatus"] as? String ?? ""), requestID)
            case "LAUNCH_ERROR":
                return (.launchError(reason), requestID)
            case "INVALID_REQUEST":
                return (.receiverError(reason), requestID)
            default:
                break
            }
        case CastNamespace.media:
            switch type {
            case "MEDIA_STATUS":
                let list = (json["status"] as? [[String: Any]] ?? []).map { item in
                    CastMediaStatus(mediaSessionID: (item["mediaSessionId"] as? NSNumber)?.intValue,
                                    playerState: item["playerState"] as? String ?? "IDLE",
                                    idleReason: item["idleReason"] as? String)
                }
                return (.mediaStatus(list), requestID)
            case "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE", "ERROR":
                return (.mediaError(reason), requestID)
            default:
                break
            }
        default:
            break
        }
        return (.other(type), requestID)
    }

    private static func parseApplication(_ item: [String: Any]) -> CastApplication {
        let namespaces = (item["namespaces"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        return CastApplication(appID: item["appId"] as? String ?? "",
                               sessionID: item["sessionId"] as? String ?? "",
                               transportID: item["transportId"] as? String ?? "",
                               displayName: item["displayName"] as? String ?? "",
                               namespaces: namespaces)
    }
}

// MARK: - 찾은 기기

/// Bonjour TXT 기록에서 읽은 크롬캐스트 정보. `fn` 이 이름, `md` 가 모델, `ca` 가 할 수 있는 일이다.
struct CastDeviceRecord: Equatable {
    var id: String
    var name: String
    var model: String?
    var capabilities: Int?

    init(serviceName: String, txt: [String: String]) {
        let clean = { (value: String?) -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        model = clean(txt["md"])
        name = clean(txt["fn"]) ?? model ?? clean(serviceName) ?? "TV"
        id = clean(txt["id"]) ?? serviceName
        capabilities = clean(txt["ca"]).flatMap { Int($0) }
    }

    /// 화면이 있는 기기인지. `ca` 의 첫 비트가 영상 출력이다. 스피커와 스피커 묶음은 빼고, 모르면 보여 준다.
    var showsVideo: Bool {
        guard let capabilities else { return true }
        return capabilities & 1 != 0
    }
}
