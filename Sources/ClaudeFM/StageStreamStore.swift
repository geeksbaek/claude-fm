import Foundation

/// 구운 fMP4 조각을 메모리에 들고, 미끄러지는 HLS 재생 목록과 끝없는 MP4 줄기를 만든다.
/// 엔코더·HTTP 서버·앱이 서로 다른 스레드에서 쓴다.
final class StageSegmentStore: @unchecked Sendable {
    struct Segment: Equatable {
        let sequence: Int
        let duration: Double
        let data: Data
    }

    /// 재생 목록에 올리는 조각 수와, 목록에서 내려간 뒤에도 잠깐 더 내주는 몫까지 합친 수.
    let window: Int
    let retained: Int
    /// 첫 조각들이 나오기 전 재생 목록 머리에 적는 값. 조각 길이를 늘 넉넉히 덮는다.
    let resolution: String
    let frameRate: Double
    let bandwidth: Int

    private let lock = NSLock()
    private var initSegment: Data?
    private var segments: [Segment] = []
    private var nextSequence = 0
    private var longest = 0.0
    private var codecs = "avc1.640028,mp4a.40.2"
    private var poster: Data?
    private var lastAppend: TimeInterval?
    private var subscribers: [Int: (Data) -> Void] = [:]
    private var nextSubscriber = 0

    init(window: Int = 10, retained: Int = 20, resolution: String = "1280x720", frameRate: Double = 30, bandwidth: Int = 5_400_000) {
        self.window = max(3, window)
        self.retained = max(self.window, retained)
        self.resolution = resolution
        self.frameRate = frameRate
        self.bandwidth = bandwidth
    }

    // MARK: 쓰기

    func setInitialization(_ data: Data) {
        let found = Self.videoCodec(inInitialization: data)
        lock.lock()
        initSegment = data
        if let found { codecs = "\(found),mp4a.40.2" }
        lock.unlock()
    }

    func append(_ data: Data, duration: Double) {
        let length = duration.isFinite && duration > 0 ? duration : 1
        lock.lock()
        let segment = Segment(sequence: nextSequence, duration: length, data: data)
        nextSequence += 1
        segments.append(segment)
        if segments.count > retained { segments.removeFirst(segments.count - retained) }
        longest = max(longest, length)
        lastAppend = ProcessInfo.processInfo.systemUptime
        let listeners = Array(subscribers.values)
        lock.unlock()
        for listener in listeners { listener(data) }
    }

    func setPoster(_ data: Data?) {
        lock.lock()
        poster = data
        lock.unlock()
    }

    // MARK: 읽기

    var segmentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return segments.count
    }

    var hasInitialization: Bool {
        lock.lock()
        defer { lock.unlock() }
        return initSegment != nil
    }

    /// 마지막 조각이 나온 시스템 시각. 영상이 멈췄는지 볼 때 쓴다.
    var lastSegmentUptime: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return lastAppend
    }

    var codecString: String {
        lock.lock()
        defer { lock.unlock() }
        return codecs
    }

    var listedSegments: [Segment] {
        lock.lock()
        defer { lock.unlock() }
        return Array(segments.suffix(window))
    }

    /// 조각 목록. 첫머리 조각이 아직 없으면 nil.
    func mediaPlaylist() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard initSegment != nil, !segments.isEmpty else { return nil }
        let listed = segments.suffix(window)
        // 반올림한 조각 길이가 목표 길이를 넘지 않게 한다. 1초 조각이라 보통 2 다.
        let target = max(2, Int(ceil(longest - 0.001)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:\(listed.first?.sequence ?? 0)",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MAP:URI=\"init.mp4\"",
        ]
        for segment in listed {
            lines.append(String(format: "#EXTINF:%.5f,", segment.duration))
            lines.append("seg\(segment.sequence).m4s")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 변형이 하나뿐인 마스터 목록. 코덱과 해상도를 미리 알려 수신기가 짐작하지 않게 한다.
    func masterPlaylist() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard initSegment != nil else { return nil }
        return [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),CODECS=\"\(codecs)\",RESOLUTION=\(resolution),FRAME-RATE=\(String(format: "%.3f", frameRate))",
            "media.m3u8",
        ].joined(separator: "\n") + "\n"
    }

    func initialization() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return initSegment
    }

    func segment(_ sequence: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return segments.first { $0.sequence == sequence }?.data
    }

    func posterData() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return poster
    }

    /// 끝없는 MP4 줄기를 받을 손님을 단다. 첫머리와 최근 조각 `lead` 개를 한 번에 돌려주고,
    /// 그 뒤로 새 조각이 나올 때마다 `handler` 를 부른다. 첫머리가 아직 없으면 nil.
    func subscribe(lead: Int = 2, _ handler: @escaping (Data) -> Void) -> (id: Int, backlog: Data)? {
        lock.lock()
        defer { lock.unlock() }
        guard let initSegment else { return nil }
        var backlog = initSegment
        for segment in segments.suffix(lead) { backlog.append(segment.data) }
        let id = nextSubscriber
        nextSubscriber += 1
        subscribers[id] = handler
        return (id, backlog)
    }

    func unsubscribe(_ id: Int) {
        lock.lock()
        subscribers[id] = nil
        lock.unlock()
    }

    /// 첫머리 조각의 `avcC` 에서 H.264 코덱 글(`avc1.64001f`)을 읽는다.
    static func videoCodec(inInitialization data: Data) -> String? {
        let bytes = [UInt8](data)
        let tag: [UInt8] = Array("avcC".utf8)
        guard bytes.count >= 8 else { return nil }
        for index in 0...(bytes.count - 8) where bytes[index] == tag[0] {
            guard bytes[index + 1] == tag[1], bytes[index + 2] == tag[2], bytes[index + 3] == tag[3],
                  bytes[index + 4] == 1 else { continue }
            return String(format: "avc1.%02x%02x%02x", bytes[index + 5], bytes[index + 6], bytes[index + 7])
        }
        return nil
    }
}

// MARK: - HTTP

/// TV 가 보낸 HTTP 요청 머리.
struct StageHTTPRequest: Equatable {
    enum Parse: Equatable {
        case incomplete
        case invalid
        case request(StageHTTPRequest)
    }

    var method: String
    /// 물음표 뒤를 뗀 경로.
    var path: String
    /// 이름은 소문자로.
    var headers: [String: String]

    static let maximumHead = 16 * 1024

    static func parse(_ bytes: [UInt8]) -> Parse {
        guard let end = headEnd(bytes) else { return bytes.count > maximumHead ? .invalid : .incomplete }
        guard let head = String(bytes: bytes[0..<end], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { $0 + ", " + value } ?? value
        }
        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .request(StageHTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers))
    }

    private static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4) where bytes[index] == 13 {
            if bytes[index + 1] == 10, bytes[index + 2] == 13, bytes[index + 3] == 10 { return index }
        }
        return nil
    }
}

struct StageHTTPResponse {
    var status: Int
    var headers: [(String, String)]
    var body: Data
    /// 몸통 뒤로 새 조각을 이어 보내는 끝없는 MP4 줄기.
    var streams = false

    func header(_ name: String) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }

    /// 상태 줄과 머리.
    func head() -> Data {
        var text = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (name, value) in headers { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        return Data(text.utf8)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}

/// 요청 하나에 맞는 응답을 짓는다. 소리까지 실린 무대라서 아무나 못 보게 경로에 무작위 열쇠를 둔다.
enum StageHTTPRouter {
    enum ByteRange: Equatable {
        case full
        case partial(ClosedRange<Int>)
        case unsatisfiable
    }

    static let playlistType = "application/vnd.apple.mpegurl"
    static let videoType = "video/mp4"

    static func respond(to request: StageHTTPRequest, store: StageSegmentStore, basePath: String) -> StageHTTPResponse {
        if request.method == "OPTIONS" {
            var headers = common()
            headers.append(("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS"))
            headers.append(("Access-Control-Allow-Headers", request.headers["access-control-request-headers"] ?? "*"))
            headers.append(("Access-Control-Max-Age", "600"))
            headers.append(("Content-Length", "0"))
            return StageHTTPResponse(status: 204, headers: headers, body: Data())
        }
        guard request.method == "GET" || request.method == "HEAD" else {
            return plain(405, extra: [("Allow", "GET, HEAD, OPTIONS")])
        }
        guard request.path.hasPrefix(basePath) else { return plain(404) }
        let name = String(request.path.dropFirst(basePath.count))
        switch name {
        case "stage.m3u8":
            guard let text = store.masterPlaylist() else { return plain(503, extra: [("Retry-After", "1")]) }
            return file(Data(text.utf8), type: playlistType, cache: "no-cache", request: request)
        case "media.m3u8":
            guard let text = store.mediaPlaylist() else { return plain(503, extra: [("Retry-After", "1")]) }
            return file(Data(text.utf8), type: playlistType, cache: "no-cache", request: request)
        case "init.mp4":
            guard let data = store.initialization() else { return plain(503, extra: [("Retry-After", "1")]) }
            return file(data, type: videoType, cache: "max-age=3600", request: request)
        case "poster.jpg":
            guard let data = store.posterData() else { return plain(404) }
            return file(data, type: "image/jpeg", cache: "no-cache", request: request)
        case "stage.mp4":
            // 길이를 모르는 줄기라 연결을 닫을 때 끝난다. 이어 붙이는 일은 서버가 맡는다.
            guard store.hasInitialization else { return plain(503, extra: [("Retry-After", "1")]) }
            var headers = common()
            headers.append(("Content-Type", videoType))
            headers.append(("Cache-Control", "no-cache, no-store"))
            return StageHTTPResponse(status: 200, headers: headers, body: Data(), streams: true)
        default:
            guard name.hasPrefix("seg"), name.hasSuffix(".m4s"),
                  let sequence = Int(name.dropFirst(3).dropLast(4)), let data = store.segment(sequence) else { return plain(404) }
            return file(data, type: videoType, cache: "max-age=3600", request: request)
        }
    }

    /// `bytes=0-99`, `bytes=100-`, `bytes=-50` 하나만 받는다. 여러 구간이나 읽지 못할 글은 무시하고 다 보낸다.
    static func range(_ header: String?, length: Int) -> ByteRange {
        guard let header = header?.trimmingCharacters(in: .whitespaces), header.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = header.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }
        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            // 끝에서부터 몇 바이트.
            guard let count = Int(last) else { return .full }
            guard count > 0, length > 0 else { return .unsatisfiable }
            return .partial(max(0, length - count)...(length - 1))
        }
        guard let start = Int(first), start >= 0 else { return .full }
        guard start < length else { return .unsatisfiable }
        if last.isEmpty { return .partial(start...(length - 1)) }
        guard let end = Int(last), end >= start else { return .full }
        return .partial(start...min(end, length - 1))
    }

    static func common() -> [(String, String)] {
        [
            ("Access-Control-Allow-Origin", "*"),
            ("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges"),
            ("Connection", "close"),
        ]
    }

    private static func file(_ data: Data, type: String, cache: String, request: StageHTTPRequest) -> StageHTTPResponse {
        var headers = common()
        headers.append(("Content-Type", type))
        headers.append(("Cache-Control", cache))
        headers.append(("Accept-Ranges", "bytes"))
        switch range(request.headers["range"], length: data.count) {
        case .full:
            headers.append(("Content-Length", "\(data.count)"))
            return StageHTTPResponse(status: 200, headers: headers, body: data)
        case .partial(let span):
            headers.append(("Content-Range", "bytes \(span.lowerBound)-\(span.upperBound)/\(data.count)"))
            headers.append(("Content-Length", "\(span.count)"))
            let start = data.startIndex + span.lowerBound
            return StageHTTPResponse(status: 206, headers: headers, body: data.subdata(in: start..<(start + span.count)))
        case .unsatisfiable:
            headers.append(("Content-Range", "bytes */\(data.count)"))
            headers.append(("Content-Length", "0"))
            return StageHTTPResponse(status: 416, headers: headers, body: Data())
        }
    }

    static func plain(_ status: Int, extra: [(String, String)] = []) -> StageHTTPResponse {
        let body = Data("\(status) \(StageHTTPResponse.reason(status))\n".utf8)
        var headers = common()
        headers.append(("Content-Type", "text/plain; charset=utf-8"))
        headers.append(("Cache-Control", "no-cache"))
        headers.append(contentsOf: extra)
        headers.append(("Content-Length", "\(body.count)"))
        return StageHTTPResponse(status: status, headers: headers, body: body)
    }
}
