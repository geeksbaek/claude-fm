import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Network

// 무대를 크롬캐스트로 보내는 핵심을 화면 없이 검사한다. 크롬캐스트가 없어도 돌도록
// 메시지는 알려진 바이트와 견주고, 영상은 실제 엔코더로 구운 뒤 되읽고, 서버와 세션은 이 Mac 안에서 주고받는다.
//   scripts/cast-check.sh [미리보기 폴더]

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("✗ \(message)  (\(file):\(line))")
    }
}

func section(_ name: String) {
    print("— \(name)")
}

func near(_ a: Double?, _ b: Double, _ tolerance: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

/// 다른 스레드의 콜백이 값을 넘겨 줄 때 쓰는 상자.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

/// `condition` 이 참이 될 때까지 기다린다.
func waitFor(_ seconds: Double, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(10_000)
    }
    return condition()
}

let previewFolder = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
if let previewFolder { try? FileManager.default.createDirectory(at: previewFolder, withIntermediateDirectories: true) }

// MARK: - CASTV2 메시지

section("CASTV2 메시지")
let connect = CastMessage(source: "sender-0", destination: "receiver-0", namespace: CastNamespace.connection,
                          payload: #"{"type":"CONNECT"}"#)
let connectBytes: [UInt8] = [0x08, 0x00, 0x12, 0x08] + Array("sender-0".utf8) + [0x1A, 0x0A] + Array("receiver-0".utf8)
    + [0x22, 0x28] + Array("urn:x-cast:com.google.cast.tp.connection".utf8) + [0x28, 0x00, 0x32, 0x12] + Array(#"{"type":"CONNECT"}"#.utf8)
check(connectBytes.count == 88, "알려진 CONNECT 바이트는 88개")
check([UInt8](connect.encoded()) == connectBytes, "CONNECT 를 protobuf 로 바이트 하나 틀림없이 짓는다")
check([UInt8](connect.framed().prefix(4)) == [0, 0, 0, 88], "4바이트 큰 끝 길이를 앞에 붙인다")
check((try? CastMessage(decoding: Data(connectBytes))) == connect, "알려진 바이트를 읽으면 같은 메시지")

let longText = String(repeating: "가", count: 100)
let long = CastMessage(source: "a", destination: "b", namespace: "n", payload: longText)
let longBytes = [UInt8](long.encoded())
check(Array(longBytes.suffix(303).prefix(3)) == [0x32, 0xAC, 0x02], "300바이트 글은 길이를 두 바이트 varint 로 쓴다")
check((try? CastMessage(decoding: long.encoded()))?.payload == longText, "한글 긴 글도 되읽는다")

var extended = connectBytes
extended += [0x78, 0x05]                    // 15번 칸 varint
extended += [0x82, 0x01, 0x03, 1, 2, 3]     // 16번 칸 길이 붙은 바이트
extended += [0x8D, 0x01, 1, 2, 3, 4]        // 17번 칸 fixed32
extended += [0x91, 0x01, 1, 2, 3, 4, 5, 6, 7, 8] // 18번 칸 fixed64
check((try? CastMessage(decoding: Data(extended))) == connect, "모르는 칸은 건너뛴다")
check((try? CastMessage(decoding: Data(connectBytes.prefix(30)))) == nil, "잘린 본문은 거절한다")
check((try? CastMessage(decoding: Data([0x08, 0x00]))) == nil, "필수 칸이 없으면 거절한다")
let auth = CastMessage(source: "s", destination: "d", namespace: "urn:x-cast:com.google.cast.tp.deviceauth", payload: "",
                       binary: Data([1, 2, 3]))
check((try? CastMessage(decoding: auth.encoded()))?.binary == Data([1, 2, 3]), "이진 내용도 읽는다")
check(CastInbound.parse(auth).event == .other("binary"), "이진 메시지는 다른 소식으로 넘긴다")

var frameReader = CastFrameReader()
var wire = connect.framed()
wire.append(long.framed())
wire.append(connect.framed())
var unpacked: [CastMessage] = []
let pieces = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]
var offset = 0
var step = 0
while offset < wire.count {
    let size = min(pieces[step % pieces.count], wire.count - offset)
    unpacked += (try? frameReader.append(wire.subdata(in: offset..<(offset + size)))) ?? []
    offset += size
    step += 1
}
check(unpacked == [connect, long, connect], "쪼개져 들어와도 세 통을 차례로 꺼낸다")
var oversized = CastFrameReader()
check((try? oversized.append(Data([0x00, 0x02, 0x00, 0x00]))) == nil, "64KB 넘는 통은 거절한다")

// MARK: - JSON

section("JSON 메시지")
func json(_ text: String) -> [String: Any] { CastJSON.object(text) ?? [:] }
check(json(CastRequest.connect())["type"] as? String == "CONNECT", "CONNECT")
check(json(CastRequest.close())["type"] as? String == "CLOSE", "CLOSE")
check(json(CastRequest.ping())["type"] as? String == "PING" && json(CastRequest.pong())["type"] as? String == "PONG", "PING PONG")
let launchJSON = json(CastRequest.launch(requestID: 3))
check(launchJSON["type"] as? String == "LAUNCH" && launchJSON["appId"] as? String == "CC1AD845"
      && (launchJSON["requestId"] as? NSNumber)?.intValue == 3, "기본 미디어 수신기를 띄운다")
let stopJSON = json(CastRequest.stop(sessionID: "S-1", requestID: 9))
check(stopJSON["type"] as? String == "STOP" && stopJSON["sessionId"] as? String == "S-1", "세션을 닫는다")
check(json(CastRequest.getStatus(requestID: 2))["type"] as? String == "GET_STATUS", "상태를 묻는다")
let hlsMedia = CastMedia(url: "http://192.168.0.5:8765/live/abc/stage.m3u8", format: .hls, title: "Claude FM 무대",
                         subtitle: "Clawd 의 콘서트", imageURL: "http://192.168.0.5:8765/live/abc/poster.jpg")
let loadText = CastRequest.load(hlsMedia, sessionID: "S-1", requestID: 4)
let loadJSON = json(loadText)
let loadMedia = loadJSON["media"] as? [String: Any] ?? [:]
let loadMetadata = loadMedia["metadata"] as? [String: Any] ?? [:]
check(loadJSON["type"] as? String == "LOAD" && loadJSON["sessionId"] as? String == "S-1"
      && (loadJSON["requestId"] as? NSNumber)?.intValue == 4 && loadJSON["autoplay"] as? Bool == true, "LOAD 의 겉")
check(loadMedia["contentId"] as? String == hlsMedia.url && loadMedia["contentUrl"] as? String == hlsMedia.url, "주소를 두 칸에 다 적는다")
check(loadMedia["contentType"] as? String == "application/vnd.apple.mpegurl" && loadMedia["streamType"] as? String == "LIVE",
      "HLS 라이브")
check(loadMedia["hlsSegmentFormat"] as? String == "fmp4" && loadMedia["hlsVideoSegmentFormat"] as? String == "fmp4", "fMP4 조각이라고 알린다")
check((loadMetadata["metadataType"] as? NSNumber)?.intValue == 0 && loadMetadata["title"] as? String == "Claude FM 무대"
      && loadMetadata["subtitle"] as? String == "Clawd 의 콘서트", "제목과 부제")
check(((loadMetadata["images"] as? [[String: Any]])?.first?["url"] as? String)?.hasSuffix("poster.jpg") == true, "무대 그림")
check(loadJSON["currentTime"] == nil && loadMedia["currentTime"] == nil, "라이브는 시작 시각을 주지 않는다")
check(loadText.contains("http://192.168.0.5:8765/live/abc/stage.m3u8"), "주소의 / 를 이스케이프하지 않는다")
let progressiveJSON = json(CastRequest.load(CastMedia(url: "http://x/stage.mp4", format: .progressive, title: "t", subtitle: "s",
                                                      imageURL: nil), sessionID: "S", requestID: 5))["media"] as? [String: Any] ?? [:]
check(progressiveJSON["contentType"] as? String == "video/mp4" && progressiveJSON["hlsSegmentFormat"] == nil
      && progressiveJSON["streamType"] as? String == "LIVE", "끝없는 MP4 는 video/mp4 라이브")

// MARK: - 받은 메시지

section("받은 메시지")
func inbound(_ namespace: String, _ payload: String, from source: String = "receiver-0") -> (event: CastInbound, requestID: Int?) {
    CastInbound.parse(CastMessage(source: source, destination: "sender-0", namespace: namespace, payload: payload))
}
let receiverStatusText = #"""
{"requestId":1,"status":{"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver","iconUrl":"","isIdleScreen":false,"launchedFromCloud":false,"namespaces":[{"name":"urn:x-cast:com.google.cast.cac"},{"name":"urn:x-cast:com.google.cast.debugoverlay"},{"name":"urn:x-cast:com.google.cast.broadcast"},{"name":"urn:x-cast:com.google.cast.media"}],"sessionId":"7E2FF513-CDF6-9A91-2B28-3E3DE7BAC174","statusText":"Default Media Receiver","transportId":"web-5","universalAppId":"CC1AD845"}],"isActiveInput":true,"isStandBy":false,"userEq":{},"volume":{"controlType":"attenuation","level":1.0,"muted":false,"stepInterval":0.05}},"type":"RECEIVER_STATUS"}
"""#
let receiverParsed = inbound(CastNamespace.receiver, receiverStatusText)
if case .receiverStatus(let status) = receiverParsed.event, let app = status.application("CC1AD845") {
    check(app.sessionID == "7E2FF513-CDF6-9A91-2B28-3E3DE7BAC174" && app.transportID == "web-5", "세션과 전송 번호")
    check(app.namespaces.contains(CastNamespace.media) && app.displayName == "Default Media Receiver", "이름 공간과 이름")
} else {
    check(false, "RECEIVER_STATUS 를 읽는다")
}
check(receiverParsed.requestID == 1, "요청 번호")
check(inbound(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","requestId":0,"status":{"volume":{"level":1}}}"#).event
      == .receiverStatus(CastReceiverStatus(applications: [])), "앱이 없는 상태")
let mediaStatusText = #"""
{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playbackRate":1,"playerState":"BUFFERING","currentTime":0,"supportedMediaCommands":12303,"volume":{"level":1,"muted":false},"currentItemId":1}],"requestId":4}
"""#
let mediaParsed = inbound(CastNamespace.media, mediaStatusText, from: "web-5")
check(mediaParsed.event == .mediaStatus([CastMediaStatus(mediaSessionID: 7, playerState: "BUFFERING", idleReason: nil)])
      && mediaParsed.requestID == 4, "MEDIA_STATUS 를 읽는다")
check(inbound(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"IDLE","idleReason":"ERROR"}],"requestId":0}"#).event
      == .mediaStatus([CastMediaStatus(mediaSessionID: 7, playerState: "IDLE", idleReason: "ERROR")]), "멈춘 까닭")
check(inbound(CastNamespace.media, #"{"type":"LOAD_FAILED","requestId":4}"#).event == .mediaError("LOAD_FAILED"), "LOAD_FAILED")
check(inbound(CastNamespace.media, #"{"type":"INVALID_REQUEST","requestId":4,"reason":"INVALID_COMMAND"}"#).event
      == .mediaError("INVALID_COMMAND"), "INVALID_REQUEST 의 까닭")
check(inbound(CastNamespace.media, #"{"type":"ERROR","detailedErrorCode":104,"requestId":0}"#).event == .mediaError("104"), "CAF 오류 번호")
check(inbound(CastNamespace.receiver, #"{"type":"LAUNCH_ERROR","reason":"NOT_FOUND","requestId":1}"#).event
      == .launchError("NOT_FOUND"), "LAUNCH_ERROR")
check(inbound(CastNamespace.receiver, #"{"type":"LAUNCH_STATUS","status":"USER_PENDING_AUTHORIZATION","requestId":1}"#).event
      == .launchStatus("USER_PENDING_AUTHORIZATION"), "TV 에서 허용을 기다리는 중")
check(inbound(CastNamespace.connection, #"{"type":"CLOSE"}"#, from: "web-5").event == .close, "CLOSE")
check(inbound(CastNamespace.heartbeat, #"{"type":"PING"}"#).event == .ping, "PING")
check(inbound(CastNamespace.heartbeat, "not json").event == .other("binary"), "읽지 못할 글")

// MARK: - 기기

section("찾은 기기")
let chromecast = CastDeviceRecord(serviceName: "Chromecast-1a2b3c", txt: ["id": "1a2b3c", "fn": "거실 TV", "md": "Chromecast", "ca": "201221"])
check(chromecast.name == "거실 TV" && chromecast.model == "Chromecast" && chromecast.id == "1a2b3c" && chromecast.showsVideo, "TV 는 이름 fn")
check(CastDeviceRecord(serviceName: "x", txt: ["md": "Chromecast Ultra", "ca": "4101"]).name == "Chromecast Ultra", "fn 이 없으면 모델 md")
check(CastDeviceRecord(serviceName: "Chromecast-9f", txt: [:]).name == "Chromecast-9f", "둘 다 없으면 서비스 이름")
check(!CastDeviceRecord(serviceName: "Google-Home", txt: ["fn": "주방", "md": "Google Home", "ca": "2052"]).showsVideo, "스피커는 뺀다")
check(!CastDeviceRecord(serviceName: "Group", txt: ["fn": "온 집", "md": "Google Cast Group", "ca": "2084"]).showsVideo, "스피커 묶음도 뺀다")
check(CastDeviceRecord(serviceName: "TV", txt: ["fn": "  "]).name == "TV", "빈 이름은 무시한다")
check(CastDiscovery.isPolicyDenied(.dns(-65_570)) && !CastDiscovery.isPolicyDenied(.posix(.ECONNREFUSED)), "로컬 네트워크 거절을 알아본다")

// MARK: - 재생 목록과 HTTP

section("HLS 재생 목록과 HTTP")
let unitStore = StageSegmentStore(window: 3, retained: 5)
check(unitStore.mediaPlaylist() == nil && unitStore.masterPlaylist() == nil, "첫머리 조각 전에는 목록이 없다")
var fakeInit = Data("\u{0}\u{0}\u{0}\u{18}ftypiso6....moov....stsd....avc1....".utf8)
fakeInit.append(Data("avcC".utf8))
fakeInit.append(contentsOf: [0x01, 0x64, 0x00, 0x1F, 0xFF])
unitStore.setInitialization(fakeInit)
check(unitStore.codecString == "avc1.64001f,mp4a.40.2", "avcC 에서 코덱을 읽는다")
for index in 0..<7 { unitStore.append(Data(repeating: UInt8(index), count: 200 + index), duration: index == 5 ? 1.0333 : 1.0) }
let unitPlaylist = unitStore.mediaPlaylist() ?? ""
let unitLines = unitPlaylist.split(separator: "\n").map(String.init)
check(unitLines.first == "#EXTM3U" && unitLines.contains("#EXT-X-VERSION:7") && unitLines.contains("#EXT-X-TARGETDURATION:2"), "목록 머리")
check(unitLines.contains("#EXT-X-MEDIA-SEQUENCE:4") && unitLines.contains("#EXT-X-MAP:URI=\"init.mp4\""), "미끄러지는 창과 첫머리")
check(unitLines.filter { $0.hasPrefix("#EXTINF:") } == ["#EXTINF:1.00000,", "#EXTINF:1.03330,", "#EXTINF:1.00000,"], "조각 길이")
check(unitLines.filter { $0.hasSuffix(".m4s") } == ["seg4.m4s", "seg5.m4s", "seg6.m4s"], "최근 세 조각만 올린다")
check(!unitLines.contains("#EXT-X-ENDLIST"), "라이브라 끝 표시가 없다")
check(unitStore.segment(1) == nil && unitStore.segment(2) != nil && unitStore.segment(6)?.count == 206, "목록에서 내려간 조각도 잠깐 더 내준다")
let master = unitStore.masterPlaylist() ?? ""
check(master.contains("CODECS=\"avc1.64001f,mp4a.40.2\"") && master.contains("RESOLUTION=1280x720") && master.hasSuffix("media.m3u8\n"),
      "마스터 목록")

let headText = "GET /live/tok/media.m3u8?_=1 HTTP/1.1\r\nHost: 192.168.0.5:8765\r\nRange: bytes=0-9\r\nOrigin: https://www.gstatic.com\r\n\r\n"
check(StageHTTPRequest.parse(Array(headText.utf8.prefix(25))) == .incomplete, "머리가 덜 오면 기다린다")
check(StageHTTPRequest.parse(Array("NONSENSE\r\n\r\n".utf8)) == .invalid, "망가진 요청")
check(StageHTTPRequest.parse(Array(repeating: 65, count: 17_000)) == .invalid, "끝없는 머리는 거절한다")
guard case .request(let unitRequest) = StageHTTPRequest.parse(Array(headText.utf8)) else { fatalError("요청을 읽지 못했다") }
check(unitRequest.method == "GET" && unitRequest.path == "/live/tok/media.m3u8" && unitRequest.headers["range"] == "bytes=0-9"
      && unitRequest.headers["origin"] == "https://www.gstatic.com", "요청 줄과 머리")
let ranged = StageHTTPRouter.respond(to: unitRequest, store: unitStore, basePath: "/live/tok/")
check(ranged.status == 206 && ranged.body == Data(unitPlaylist.utf8.prefix(10))
      && ranged.header("Content-Range") == "bytes 0-9/\(unitPlaylist.utf8.count)", "구간 요청")
check(ranged.header("Access-Control-Allow-Origin") == "*" && ranged.header("Cache-Control") == "no-cache", "CORS 와 캐시 금지")
let rangeCases: [(String, StageHTTPRouter.ByteRange)] = [
    ("bytes=0-9", .partial(0...9)), ("bytes=95-", .partial(95...99)), ("bytes=-5", .partial(95...99)),
    ("bytes=90-500", .partial(90...99)), ("bytes=-0", .unsatisfiable), ("bytes=100-", .unsatisfiable),
    ("bytes=0-1,4-5", .full), ("items=0-1", .full), ("bytes=x-", .full),
]
for (header, expected) in rangeCases {
    check(StageHTTPRouter.range(header, length: 100) == expected, "구간 \(header)")
}
var other = unitRequest
other.path = "/live/nope/media.m3u8"
check(StageHTTPRouter.respond(to: other, store: unitStore, basePath: "/live/tok/").status == 404, "열쇠가 틀리면 404")
other.path = "/live/tok/seg1.m4s"
check(StageHTTPRouter.respond(to: other, store: unitStore, basePath: "/live/tok/").status == 404, "지난 조각은 404")
other.method = "POST"
check(StageHTTPRouter.respond(to: other, store: unitStore, basePath: "/live/tok/").status == 405, "POST 는 받지 않는다")
other.method = "OPTIONS"
other.headers = ["access-control-request-headers": "range"]
let preflight = StageHTTPRouter.respond(to: other, store: unitStore, basePath: "/live/tok/")
check(preflight.status == 204 && preflight.header("Access-Control-Allow-Headers") == "range"
      && preflight.header("Access-Control-Allow-Methods")?.contains("GET") == true, "CORS 사전 요청")

// MARK: - 소리 시간줄과 고리

section("소리 시간줄")
var drifting = StageAudioTimeline(rate: 48_000, start: 100)
var host = 100.0
var largest = 0.0
var jumps = 0
for chunk in 0..<30_000 {
    let placement = drifting.place(host: host, frames: 480)
    if placement.silence > 0 || placement.skip > 1 { jumps += 1 }
    drifting.advance(placement.silence + (placement.repeatFirst ? 1 : 0) + 480 - placement.skip)
    host += 480 / (48_000 * 1.0002)   // 장치 시계가 200ppm 빠르다
    if chunk > 100 { largest = max(largest, abs(Double(drifting.head) / 48_000 - (host - 100))) }
}
check(jumps == 0 && largest < 0.004, "시계가 어긋나도 한 칸씩 고쳐 4ms 안에 붙어 간다 (\(String(format: "%.1f", largest * 1000))ms)")
var gapped = StageAudioTimeline(rate: 48_000, start: 0)
gapped.advance(48_000)
check(gapped.silenceDue(at: 1.10, latency: 0.15) == 0, "조금 늦는 것은 기다린다")
check(gapped.silenceDue(at: 1.45, latency: 0.15) == 14_400, "한참 안 오면 조용한 칸으로 채운다")
check(gapped.place(host: 1.3, frames: 480) == .init(silence: 14_400), "다시 오면 빈 곳을 메우고 이어 놓는다")
check(gapped.place(host: 0.5, frames: 480) == .init(skip: 480), "이미 지난 소리는 버린다")
check(gapped.place(host: 1.005, frames: 480) == .init(repeatFirst: true) && gapped.place(host: 0.995, frames: 480) == .init(skip: 1),
      "조금 어긋나면 한 칸씩")
check(StageAudioTimeline(rate: 48_000, start: 10).place(host: 9, frames: 480) == .init(skip: 480), "굽기 전 소리는 버린다")

let unitRing = StageAudioRing(capacity: 4_096, chunkCapacity: 64)
var interleaved = [Float](repeating: 0, count: 2_000)
for index in 0..<1_000 {
    interleaved[index * 2] = Float(index)
    interleaved[index * 2 + 1] = -Float(index)
}
interleaved.withUnsafeBufferPointer { pointer in
    unitRing.write(left: pointer.baseAddress!, right: pointer.baseAddress! + 1, stride: 2, frames: 1_000, host: 5, rate: 48_000)
}
let planarLeft = [Float](repeating: 0.5, count: 300)
let planarRight = [Float](repeating: -0.5, count: 300)
planarLeft.withUnsafeBufferPointer { left in
    planarRight.withUnsafeBufferPointer { right in
        unitRing.write(left: left.baseAddress!, right: right.baseAddress!, stride: 1, frames: 300, host: 6, rate: 44_100)
    }
}
let readBack = UnsafeMutablePointer<Float>.allocate(capacity: 8_192)
let firstPart = unitRing.read(into: readBack, maxFrames: 600)
check(firstPart == StageAudioRing.Chunk(host: 5, frames: 600, rate: 48_000) && readBack[2 * 599] == 599 && readBack[2 * 599 + 1] == -599,
      "섞인 채널을 왼쪽·오른쪽으로 꺼낸다")
let secondPart = unitRing.read(into: readBack, maxFrames: 4_096)
check(secondPart?.frames == 400 && near(secondPart?.host, 5 + 600.0 / 48_000, 1e-9) && readBack[0] == 600, "덩어리 뒷부분은 시각을 이어 준다")
let thirdPart = unitRing.read(into: readBack, maxFrames: 4_096)
check(thirdPart == StageAudioRing.Chunk(host: 6, frames: 300, rate: 44_100) && readBack[0] == 0.5 && readBack[1] == -0.5, "나뉜 채널")
check(unitRing.read(into: readBack, maxFrames: 4_096) == nil, "다 꺼내면 빈다")
let tooMuch = [Float](repeating: 0, count: 10_000)
tooMuch.withUnsafeBufferPointer { unitRing.write(left: $0.baseAddress!, right: $0.baseAddress!, stride: 1, frames: 5_000, host: 7, rate: 48_000) }
check(unitRing.dropped == 5_000 && unitRing.read(into: readBack, maxFrames: 10) == nil, "자리가 없으면 버리고 넘치지 않는다")
check(near(unitRing.lastWriteHost, 6 + 300.0 / 44_100, 1e-9), "마지막으로 받은 소리 시각")
readBack.deallocate()

// MARK: - 영상 굽기 (차례로)

section("영상 굽기")
/// 짙은 파랑 바탕에 주황 막대가 지나가고, 90~104번 프레임에는 왼쪽 위에 흰 네모가 뜬다.
func syntheticFrame(_ buffer: CVPixelBuffer, index: Int) {
    _ = CVPixelBufferLockBaseAddress(buffer, [])
    defer { _ = CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let barX = (index * 12) % width
    let flash = (90..<105).contains(index)
    for y in 0..<height {
        let row = base + y * stride
        for x in 0..<width {
            var color: (UInt8, UInt8, UInt8) = (20, 40, 90)
            if x >= barX, x < barX + 40 { color = (220, 120, 60) }
            if flash, x < 160, y < 90 { color = (255, 255, 255) }
            row[x * 4] = color.2
            row[x * 4 + 1] = color.1
            row[x * 4 + 2] = color.0
            row[x * 4 + 3] = 255
        }
    }
}

/// 440Hz 작은 소리에, 3.0초부터 0.1초 동안 1kHz 큰 소리.
func tone(at time: Double) -> Float {
    if time >= 3.0, time < 3.1 { return Float(0.8 * sin(2 * .pi * 1_000 * time)) }
    return Float(0.2 * sin(2 * .pi * 440 * time))
}

let store = StageSegmentStore()
let ring = StageAudioRing(capacity: 48_000 * 4)
var settings = StageStreamEncoder.Settings()
settings.realTime = false
let encoder = StageStreamEncoder(settings: settings, store: store, ring: ring)
var failureMessage: String?
encoder.onFailure = { failureMessage = $0 }
let startHost = 1_000.0
var started = true
do {
    try encoder.start(at: startHost)
} catch {
    started = false
    print("엔코더를 시작하지 못했다: \(error)")
}
check(started, "H.264 High 720p30 + AAC 설정으로 엔코더가 선다")
let pool = encoder.pixelBufferPool
check(pool != nil, "픽셀 버퍼 웅덩이")
var audioWritten = 0
var chunk = [Float](repeating: 0, count: 960)
func feedAudio(until seconds: Double) {
    while Double(audioWritten) / 48_000 <= seconds {
        for index in 0..<480 {
            let value = tone(at: Double(audioWritten + index) / 48_000)
            chunk[index * 2] = value
            chunk[index * 2 + 1] = value
        }
        chunk.withUnsafeBufferPointer { pointer in
            ring.write(left: pointer.baseAddress!, right: pointer.baseAddress! + 1, stride: 2, frames: 480,
                       host: startHost + Double(audioWritten) / 48_000, rate: 48_000)
        }
        audioWritten += 480
    }
}
if started, let pool {
    for index in 0..<180 {
        let time = Double(index) / 30
        feedAudio(until: time + 0.01)
        var buffer: CVPixelBuffer?
        _ = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let buffer else { break }
        syntheticFrame(buffer, index: index)
        encoder.appendVideo(buffer, at: startHost + time)
        encoder.drain()
    }
    // 앱처럼 소리는 마지막 프레임 언저리까지만 와 있고, 남은 몫은 끝낼 때 조용한 칸으로 채운다.
    let finished = DispatchSemaphore(value: 0)
    encoder.finish { finished.signal() }
    check(finished.wait(timeout: .now() + 20) == .success, "굽기를 마친다")
}
let encodeStats = encoder.stats
check(failureMessage == nil, "굽다가 멈추지 않는다 \(failureMessage ?? "")")
check(encodeStats.frames == 180 && encodeStats.dropped == 0, "프레임 180장을 다 넣는다 (\(encodeStats.frames))")
check(encodeStats.audioFrames >= 48_000 * 6 - 48, "소리도 6초를 채운다 (\(encodeStats.audioFrames))")
let segments = store.listedSegments
let durations = segments.map(\.duration)
print("  조각 \(segments.count)개: \(durations.map { String(format: "%.3f", $0) }.joined(separator: " "))  코덱 \(store.codecString)")
check(store.hasInitialization, "첫머리 조각(init)")
check(segments.count >= 4, "1초 조각이 네 개 넘게 나온다")
check(durations.dropLast().allSatisfy { $0 >= 0.5 && $0 <= 2.1 } && durations.last.map { $0 > 0 && $0 <= 2.1 } == true,
      "조각 길이는 0.5~2.1초 (마지막 조각만 짧을 수 있다)")
check(near(durations.reduce(0, +), 6.0, 0.35), "조각 길이를 더하면 6초쯤 (\(String(format: "%.3f", durations.reduce(0, +))))")
check(store.codecString.hasPrefix("avc1.64") && store.codecString.hasSuffix(",mp4a.40.2"), "H.264 High 와 AAC-LC 코덱 글")
let initData = store.initialization() ?? Data()
check(initData.count > 16 && String(decoding: initData[4..<8], as: UTF8.self) == "ftyp", "init 은 ftyp 로 시작한다")
check(initData.range(of: Data("moov".utf8)) != nil && initData.range(of: Data("mvex".utf8)) != nil, "init 에 moov·mvex")
check(segments.allSatisfy { $0.data.range(of: Data("moof".utf8)) != nil && $0.data.range(of: Data("mdat".utf8)) != nil },
      "조각마다 moof·mdat")
let playlist = store.mediaPlaylist() ?? ""
let lines = playlist.split(separator: "\n").map(String.init)
let target = lines.first { $0.hasPrefix("#EXT-X-TARGETDURATION:") }.flatMap { Int($0.dropFirst(22)) } ?? 0
check(lines.first == "#EXTM3U" && lines.contains("#EXT-X-VERSION:7") && lines.contains("#EXT-X-MEDIA-SEQUENCE:0")
      && lines.contains("#EXT-X-MAP:URI=\"init.mp4\""), "재생 목록 머리")
check(durations.allSatisfy { Int($0.rounded()) <= target }, "반올림한 조각 길이가 목표 길이 \(target) 를 넘지 않는다")
check(lines.filter { $0.hasPrefix("#EXTINF:") }.count == segments.count, "조각마다 EXTINF")

// 첫머리와 조각을 이어 붙인 파일을 AVFoundation 으로 되읽는다.
var joined = initData
for segment in segments { joined.append(segment.data) }
let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude-fm-cast-\(getpid()).mp4")
try? joined.write(to: sampleURL)
let asset = AVURLAsset(url: sampleURL)
let videoTracks = asset.tracks(withMediaType: .video)
let audioTracks = asset.tracks(withMediaType: .audio)
check(videoTracks.count == 1 && audioTracks.count == 1, "영상 하나, 소리 하나")
if let video = videoTracks.first {
    check(video.naturalSize == CGSize(width: 1_280, height: 720), "1280×720 (\(video.naturalSize))")
    let subtype = (video.formatDescriptions.first as! CMFormatDescription).mediaSubType.rawValue
    check(subtype == kCMVideoCodecType_H264, "H.264")
    print("  영상 시간 \(String(format: "%.3f", CMTimeGetSeconds(video.timeRange.start)))+\(String(format: "%.3f", CMTimeGetSeconds(video.timeRange.duration)))초, 전체 \(String(format: "%.3f", CMTimeGetSeconds(asset.duration)))초")
    check(near(CMTimeGetSeconds(video.timeRange.duration), 6.0, 0.2), "영상은 6초쯤")
}
if let audio = audioTracks.first {
    let subtype = (audio.formatDescriptions.first as! CMFormatDescription).mediaSubType.rawValue
    check(subtype == kAudioFormatMPEG4AAC, "AAC")
    let basic = CMAudioFormatDescriptionGetStreamBasicDescription(audio.formatDescriptions.first as! CMAudioFormatDescription)?.pointee
    check(basic?.mSampleRate == 48_000 && basic?.mChannelsPerFrame == 2, "48kHz 스테레오")
}
check(near(CMTimeGetSeconds(asset.duration), 6.0, 0.5), "전체 길이도 6초쯤")

/// 되읽은 BGRA 버퍼의 한 점.
func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    _ = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { _ = CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let point = base + y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
    return (Int(point[2]), Int(point[1]), Int(point[0]))
}

var flashVideoTime: Double?
var decodedFrames = 0
var firstFrameColor: (r: Int, g: Int, b: Int)?
var firstVideoTime: Double?
if let video = videoTracks.first, let reader = try? AVAssetReader(asset: asset) {
    let output = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    while let sample = output.copyNextSampleBuffer() {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        if firstVideoTime == nil {
            firstVideoTime = time
            firstFrameColor = pixel(image, 1_200, 650)
        }
        // 흰 네모만 센다. 지나가는 주황 막대(빨강만 밝다)와 헷갈리지 않게 세 색이 다 밝아야 한다.
        let mark = pixel(image, 80, 45)
        if flashVideoTime == nil, mark.r > 200, mark.g > 200, mark.b > 200 { flashVideoTime = time }
        decodedFrames += 1
    }
    check(reader.status == .completed, "영상을 끝까지 풀어 읽는다")
}
check(decodedFrames == 180, "풀어 읽은 프레임 수 \(decodedFrames)")
if let color = firstFrameColor {
    check(abs(color.r - 20) <= 12 && abs(color.g - 40) <= 12 && abs(color.b - 90) <= 12, "색이 그대로 돌아온다 \(color)")
}

var samples: [Float] = []
var firstAudioTime: Double?
if let audio = audioTracks.first, let reader = try? AVAssetReader(asset: asset) {
    let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ])
    reader.add(output)
    reader.startReading()
    while let sample = output.copyNextSampleBuffer() {
        if firstAudioTime == nil { firstAudioTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var floats = [Float](repeating: 0, count: length / 4)
        _ = floats.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        for index in stride(from: 0, to: floats.count, by: 2) { samples.append(floats[index]) }
    }
    check(reader.status == .completed, "소리를 끝까지 풀어 읽는다")
}
if let firstAudioTime, let firstVideoTime, samples.count > 48_000 * 5 {
    // 1~2초 구간: 440Hz 면 0을 880번쯤 지난다.
    let lead = Int((firstVideoTime - firstAudioTime) * 48_000)
    let window = Array(samples[(lead + 48_000)..<(lead + 96_000)])
    var crossings = 0
    for index in 1..<window.count where (window[index - 1] < 0) != (window[index] < 0) { crossings += 1 }
    let rms = sqrt(window.map { Double($0 * $0) }.reduce(0, +) / Double(window.count))
    check(abs(crossings - 880) <= 30, "440Hz 가 그대로 들린다 (0 지남 \(crossings)번)")
    check(near(rms, 0.2 / 2.squareRoot(), 0.05), "소리 세기도 그대로 (RMS \(String(format: "%.3f", rms)))")
    if let onset = samples.indices.first(where: { $0 > lead + 48_000 * 2 && abs(samples[$0]) > 0.5 }), let flashVideoTime {
        let audioTime = firstAudioTime + Double(onset) / 48_000
        let gap = audioTime - flashVideoTime
        print("  흰 네모 \(String(format: "%.3f", flashVideoTime))초, 큰 소리 \(String(format: "%.3f", audioTime))초, 차이 \(String(format: "%+.1f", gap * 1000))ms")
        check(abs(gap) < 0.05, "그림과 소리가 50ms 안에서 같이 간다")
        check(near(flashVideoTime - firstVideoTime, 3.0, 0.04), "흰 네모는 3초에")
    } else {
        check(false, "흰 네모와 큰 소리를 찾는다")
    }
} else {
    check(false, "소리를 충분히 풀어 읽는다 (\(samples.count))")
}

if let previewFolder {
    try? joined.write(to: previewFolder.appendingPathComponent("cast-sample.mp4"))
    try? playlist.write(to: previewFolder.appendingPathComponent("cast-media.m3u8"), atomically: true, encoding: .utf8)
    try? (store.masterPlaylist() ?? "").write(to: previewFolder.appendingPathComponent("cast-master.m3u8"), atomically: true, encoding: .utf8)
    if let first = segments.first { try? first.data.write(to: previewFolder.appendingPathComponent("cast-seg\(first.sequence).m4s")) }
}
try? FileManager.default.removeItem(at: sampleURL)

// MARK: - HTTP 서버

section("HTTP 서버")
let httpConfiguration = URLSessionConfiguration.ephemeral
httpConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
httpConfiguration.urlCache = nil
httpConfiguration.timeoutIntervalForRequest = 10
let http = URLSession(configuration: httpConfiguration)

struct Fetched {
    var status: Int
    var response: HTTPURLResponse
    var body: Data
    func header(_ name: String) -> String? { response.value(forHTTPHeaderField: name) }
}

func fetch(_ url: String, method: String = "GET", headers: [String: String] = [:]) -> Fetched? {
    guard let target = URL(string: url) else { return nil }
    var request = URLRequest(url: target)
    request.httpMethod = method
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    let done = DispatchSemaphore(value: 0)
    let result = Box<Fetched?>(nil)
    http.dataTask(with: request) { data, response, _ in
        if let response = response as? HTTPURLResponse {
            result.value = Fetched(status: response.statusCode, response: response, body: data ?? Data())
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 15)
    return result.value
}

let server = StageStreamServer(store: store)
var serverPort: UInt16?
let portReady = DispatchSemaphore(value: 0)
server.start(preferredPort: 8765) { port in
    serverPort = port
    portReady.signal()
}
_ = portReady.wait(timeout: .now() + 5)
check(serverPort != nil, "서버가 문을 연다 (\(serverPort.map(String.init) ?? "없음"))")
let base = "http://127.0.0.1:\(serverPort ?? 0)\(server.basePath)"
check(server.token.count == 16 && server.basePath.hasPrefix("/live/"), "경로에 무작위 열쇠")

if let fetched = fetch(base + "stage.m3u8") {
    check(fetched.status == 200 && fetched.header("Content-Type") == "application/vnd.apple.mpegurl", "마스터 목록 200")
    check(fetched.header("Access-Control-Allow-Origin") == "*" && fetched.header("Cache-Control") == "no-cache", "목록은 CORS·캐시 금지")
    check(String(decoding: fetched.body, as: UTF8.self) == store.masterPlaylist(), "마스터 목록 내용")
} else {
    check(false, "마스터 목록을 가져온다")
}
if let fetched = fetch(base + "media.m3u8") {
    check(fetched.status == 200 && String(decoding: fetched.body, as: UTF8.self) == playlist, "조각 목록")
} else {
    check(false, "조각 목록을 가져온다")
}
if let fetched = fetch(base + "init.mp4") {
    check(fetched.status == 200 && fetched.header("Content-Type") == "video/mp4" && fetched.body == initData
          && fetched.header("Content-Length") == "\(initData.count)", "init.mp4")
    check(fetched.header("Access-Control-Allow-Origin") == "*" && fetched.header("Accept-Ranges") == "bytes", "init 도 CORS·구간")
} else {
    check(false, "init.mp4 를 가져온다")
}
if let first = segments.first {
    let name = "seg\(first.sequence).m4s"
    if let fetched = fetch(base + name) {
        check(fetched.status == 200 && fetched.body == first.data && fetched.header("Content-Type") == "video/mp4", "조각 \(name)")
    } else {
        check(false, "조각을 가져온다")
    }
    if let fetched = fetch(base + name, headers: ["Range": "bytes=0-99"]) {
        check(fetched.status == 206 && fetched.body == first.data.prefix(100)
              && fetched.header("Content-Range") == "bytes 0-99/\(first.data.count)", "구간 0-99")
    } else {
        check(false, "구간을 가져온다")
    }
    if let fetched = fetch(base + name, headers: ["Range": "bytes=-10"]) {
        check(fetched.status == 206 && fetched.body == first.data.suffix(10), "끝 10바이트")
    }
    if let fetched = fetch(base + name, headers: ["Range": "bytes=999999999-"]) {
        check(fetched.status == 416 && fetched.header("Content-Range") == "bytes */\(first.data.count)", "넘친 구간은 416")
    }
    if let fetched = fetch(base + name, method: "HEAD") {
        check(fetched.status == 200 && fetched.body.isEmpty && fetched.header("Content-Length") == "\(first.data.count)", "HEAD")
    }
}
if let fetched = fetch(base + "stage.m3u8", method: "OPTIONS",
                       headers: ["Origin": "https://www.gstatic.com", "Access-Control-Request-Method": "GET",
                                 "Access-Control-Request-Headers": "range"]) {
    check(fetched.status == 204 && fetched.header("Access-Control-Allow-Origin") == "*"
          && fetched.header("Access-Control-Allow-Methods")?.contains("GET") == true, "CORS 사전 요청 204")
} else {
    check(false, "OPTIONS")
}
check(fetch("http://127.0.0.1:\(serverPort ?? 0)/live/0000000000000000/stage.m3u8")?.status == 404, "열쇠가 틀리면 404")
check(fetch(base + "seg9999.m4s")?.status == 404, "없는 조각은 404")
check(fetch(base + "stage.m3u8", method: "POST")?.status == 405, "POST 는 405")
let parallel = DispatchGroup()
let parallelLock = NSLock()
var parallelOK = 0
for _ in 0..<12 {
    parallel.enter()
    DispatchQueue.global().async {
        let fetched = fetch(base + "init.mp4")
        parallelLock.lock()
        if fetched?.status == 200, fetched?.body == initData { parallelOK += 1 }
        parallelLock.unlock()
        parallel.leave()
    }
}
_ = parallel.wait(timeout: .now() + 20)
check(parallelOK == 12, "여러 손님을 한꺼번에 받는다 (\(parallelOK)/12)")
check(server.remoteRequests.count == 0, "이 Mac 에서 온 요청은 TV 요청으로 세지 않는다")
check(StageStreamServer.isRemote(.hostPort(host: "192.168.0.9", port: 1)) && !StageStreamServer.isRemote(.hostPort(host: "127.0.0.1", port: 1))
      && !StageStreamServer.isRemote(.hostPort(host: "::1", port: 1)), "다른 기기를 알아본다")
let addresses = StageStreamServer.localIPv4Addresses()
print("  이 Mac 의 IPv4: \(addresses.joined(separator: ", "))")
check(addresses.allSatisfy { $0.split(separator: ".").count == 4 && !$0.hasPrefix("127.") }, "켜진 네트워크 주소")

// MARK: - 세션 (가짜 크롬캐스트)

section("세션")
/// TCP 로 CASTV2 를 주고받는 가짜 크롬캐스트. 기본 미디어 수신기 하나를 띄우는 척한다.
final class FakeReceiver: @unchecked Sendable {
    enum Mode {
        case normal
        case launchError
        case loadFails
    }

    let mode: Mode
    let queue = DispatchQueue(label: "fake.receiver")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var reader = CastFrameReader()
    private var log: [CastMessage] = []
    private var pongs = 0
    private var mediaSession = 7

    init(mode: Mode) {
        self.mode = mode
    }

    var messages: [CastMessage] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    var pongCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pongs
    }

    func start() -> UInt16? {
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        let port = Box<UInt16?>(nil)
        listener.stateUpdateHandler = { [weak listener] state in
            if case .ready = state {
                port.value = listener?.port?.rawValue
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connection = connection
            connection.start(queue: self.queue)
            self.receive(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        _ = ready.wait(timeout: .now() + 5)
        return port.value
    }

    func stop() {
        queue.sync {
            connection?.cancel()
            listener?.cancel()
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let messages = try? self.reader.append(data) {
                for message in messages { self.handle(message) }
            }
            if !isComplete, error == nil { self.receive(connection) }
        }
    }

    func send(from source: String, namespace: String, _ payload: String) {
        let message = CastMessage(source: source, destination: "sender-0", namespace: namespace, payload: payload)
        connection?.send(content: message.framed(), completion: .contentProcessed { _ in })
    }

    private func handle(_ message: CastMessage) {
        lock.lock()
        log.append(message)
        lock.unlock()
        let json = CastJSON.object(message.payload) ?? [:]
        let type = json["type"] as? String ?? ""
        let id = (json["requestId"] as? NSNumber)?.intValue ?? 0
        switch (message.namespace, type) {
        case (CastNamespace.heartbeat, "PING"):
            send(from: message.destination, namespace: CastNamespace.heartbeat, CastRequest.pong())
        case (CastNamespace.heartbeat, "PONG"):
            lock.lock()
            pongs += 1
            lock.unlock()
        case (CastNamespace.receiver, "LAUNCH"):
            if mode == .launchError {
                send(from: "receiver-0", namespace: CastNamespace.receiver, #"{"type":"LAUNCH_ERROR","reason":"NOT_FOUND","requestId":\#(id)}"#)
                return
            }
            // 앞서 다른 기기가 틀어 둔 미디어 소식이 먼저 온다. 세션은 이것을 우리 영상으로 착각하면 안 된다.
            send(from: "receiver-0", namespace: CastNamespace.receiver, Self.receiverStatus(id: 0, withApp: false))
            queue.asyncAfter(deadline: .now() + 0.2) {
                self.send(from: "receiver-0", namespace: CastNamespace.receiver, Self.receiverStatus(id: id, withApp: true))
            }
        case (CastNamespace.connection, "CONNECT") where message.destination == "web-5":
            send(from: "web-5", namespace: CastNamespace.media,
                 #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"PLAYING"}],"requestId":0}"#)
        case (CastNamespace.media, "LOAD"):
            if mode == .loadFails {
                send(from: "web-5", namespace: CastNamespace.media, #"{"type":"LOAD_FAILED","requestId":\#(id)}"#)
                return
            }
            send(from: "web-5", namespace: CastNamespace.media,
                 #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE","idleReason":"INTERRUPTED"}],"requestId":0}"#)
            send(from: "web-5", namespace: CastNamespace.media,
                 #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":\#(mediaSession),"playerState":"BUFFERING"}],"requestId":\#(id)}"#)
            queue.asyncAfter(deadline: .now() + 0.3) {
                self.send(from: "web-5", namespace: CastNamespace.media,
                          #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":\#(self.mediaSession),"playerState":"PLAYING"}],"requestId":0}"#)
            }
        case (CastNamespace.receiver, "STOP"):
            send(from: "receiver-0", namespace: CastNamespace.receiver, Self.receiverStatus(id: id, withApp: false))
        default:
            break
        }
    }

    /// TV 리모컨이나 Google Home 에서 앱을 닫은 것처럼.
    func closeAppOnTV() {
        queue.async {
            self.send(from: "receiver-0", namespace: CastNamespace.receiver, Self.receiverStatus(id: 0, withApp: false))
        }
    }

    /// 수신기가 먼저 PING 을 보낸다.
    func ping() {
        queue.async {
            self.send(from: "receiver-0", namespace: CastNamespace.heartbeat, CastRequest.ping())
        }
    }

    static func receiverStatus(id: Int, withApp: Bool) -> String {
        let apps = withApp
            ? #"[{"appId":"CC1AD845","displayName":"Default Media Receiver","namespaces":[{"name":"urn:x-cast:com.google.cast.media"}],"sessionId":"S-1","statusText":"Ready To Cast","transportId":"web-5"}]"#
            : "[]"
        return #"{"type":"RECEIVER_STATUS","requestId":\#(id),"status":{"applications":\#(apps),"volume":{"level":1}}}"#
    }
}

/// 세션 소식을 모아 둔다.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CastSession.Event] = []

    func add(_ event: CastSession.Event) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var all: [CastSession.Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func contains(_ event: CastSession.Event) -> Bool { all.contains(event) }
}

let sessionEvents = DispatchQueue(label: "session.events")
func endpoint(_ port: UInt16) -> NWEndpoint {
    .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
}

let fake = FakeReceiver(mode: .normal)
if let fakePort = fake.start() {
    let log = EventLog()
    let session = CastSession(endpoint: endpoint(fakePort), secure: false, callbackQueue: sessionEvents)
    session.onEvent = { log.add($0) }
    session.start()
    check(waitFor(5) { log.contains(.ready) }, "연결하고 수신기 앱을 띄운다")
    check(log.all.first == .connected(localHost: "127.0.0.1"), "TV 쪽에서 본 이 Mac 주소")
    let sent = fake.messages
    check(sent.first?.namespace == CastNamespace.connection && CastJSON.object(sent.first?.payload ?? "")?["type"] as? String == "CONNECT"
          && sent.first?.destination == "receiver-0", "먼저 CONNECT")
    check(sent.contains { $0.namespace == CastNamespace.receiver && $0.payload.contains("\"LAUNCH\"") && $0.payload.contains("CC1AD845") },
          "LAUNCH CC1AD845")
    check(sent.contains { $0.namespace == CastNamespace.connection && $0.destination == "web-5" }, "수신기 앱에도 CONNECT")
    check(!log.all.contains { if case .media = $0 { return true } else { return false } }, "LOAD 전의 다른 미디어 소식은 무시한다")
    session.load(hlsMedia)
    check(waitFor(5) { log.contains(.media("PLAYING")) }, "LOAD 뒤 BUFFERING → PLAYING")
    check(log.contains(.media("BUFFERING")) && !log.contains(.mediaIdle("INTERRUPTED")), "앞서 있던 미디어 세션의 소식은 무시한다")
    let load = fake.messages.first { $0.namespace == CastNamespace.media && $0.payload.contains("\"LOAD\"") }
    let loadBody = CastJSON.object(load?.payload ?? "") ?? [:]
    check(load?.destination == "web-5" && loadBody["sessionId"] as? String == "S-1"
          && (loadBody["media"] as? [String: Any])?["contentId"] as? String == hlsMedia.url, "LOAD 는 수신기 앱으로, 우리 세션 번호로")
    fake.ping()
    check(waitFor(3) { fake.pongCount >= 1 }, "수신기의 PING 에 PONG")
    fake.closeAppOnTV()
    check(waitFor(3) { log.contains(.ended(.closedOnReceiver)) }, "TV 에서 앱을 닫으면 세션도 끝난다")
    fake.stop()
} else {
    check(false, "가짜 수신기를 연다")
}

let stopping = FakeReceiver(mode: .normal)
if let port = stopping.start() {
    let log = EventLog()
    let session = CastSession(endpoint: endpoint(port), secure: false, callbackQueue: sessionEvents)
    session.onEvent = { log.add($0) }
    session.start()
    check(waitFor(5) { log.contains(.ready) }, "두 번째 연결")
    session.stopAndWait(timeout: 2)
    check(waitFor(2) { stopping.messages.contains { $0.payload.contains("\"STOP\"") && $0.payload.contains("S-1") } }, "그만 보내면 STOP")
    check(waitFor(2) { stopping.messages.contains { $0.namespace == CastNamespace.connection && $0.payload.contains("CLOSE") } },
          "그리고 CLOSE")
    check(waitFor(2) { log.contains(.ended(.stopped)) }, "멈춤으로 끝난다")
    stopping.stop()
}

let refusing = FakeReceiver(mode: .launchError)
if let port = refusing.start() {
    let log = EventLog()
    let session = CastSession(endpoint: endpoint(port), secure: false, callbackQueue: sessionEvents)
    session.onEvent = { log.add($0) }
    session.start()
    check(waitFor(5) { log.contains(.ended(.launchFailed("NOT_FOUND"))) }, "앱을 못 띄우면 까닭과 함께 끝난다")
    refusing.stop()
}

let failing = FakeReceiver(mode: .loadFails)
if let port = failing.start() {
    let log = EventLog()
    let session = CastSession(endpoint: endpoint(port), secure: false, callbackQueue: sessionEvents)
    session.onEvent = { log.add($0) }
    session.start()
    _ = waitFor(5) { log.contains(.ready) }
    session.load(hlsMedia)
    check(waitFor(5) { log.contains(.loadFailed("LOAD_FAILED")) }, "영상을 못 불러오면 알린다")
    check(!log.all.contains { if case .ended = $0 { return true } else { return false } }, "불러오기 실패만으로는 끝내지 않는다(다른 방식으로 다시)")
    session.stop()
    failing.stop()
}

// 아무도 듣지 않는 문을 찾는다.
var closedPort: UInt16 = 0
if let probe = try? NWListener(using: .tcp, on: .any) {
    let ready = DispatchSemaphore(value: 0)
    probe.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
    probe.start(queue: .global())
    _ = ready.wait(timeout: .now() + 3)
    closedPort = probe.port?.rawValue ?? 0
    probe.cancel()
    usleep(200_000)
}
if closedPort != 0 {
    let log = EventLog()
    let session = CastSession(endpoint: endpoint(closedPort), secure: false, callbackQueue: sessionEvents)
    session.onEvent = { log.add($0) }
    session.start()
    check(waitFor(20) { log.all.contains { if case .ended(.connectFailed) = $0 { return true } else { return false } } },
          "붙지 못하면 연결 실패로 끝난다")
}

// MARK: - 실시간 굽기와 끝없는 MP4

section("실시간 굽기와 끝없는 MP4")
let liveStore = StageSegmentStore()
let liveRing = StageAudioRing()
let live = StageStreamEncoder(store: liveStore, ring: liveRing)
var liveFailed: String?
live.onFailure = { liveFailed = $0 }
let liveStart = HostClock.now()
var liveStarted = true
do {
    try live.start(at: liveStart)
} catch {
    liveStarted = false
}
check(liveStarted, "실시간 엔코더가 선다")
let liveServer = StageStreamServer(store: liveStore)
var livePort: UInt16?
let livePortReady = DispatchSemaphore(value: 0)
liveServer.start(preferredPort: 8765) { port in
    livePort = port
    livePortReady.signal()
}
_ = livePortReady.wait(timeout: .now() + 5)
check(livePort != nil && livePort != serverPort, "8765 가 쓰이고 있으면 다른 문을 연다 (\(livePort.map(String.init) ?? "없음"))")

// 그림 두 장을 번갈아, 소리는 10ms 마다 실제 시각을 붙여 넣는다.
var liveFrames: [CVPixelBuffer] = []
for index in 0..<2 {
    var buffer: CVPixelBuffer?
    _ = CVPixelBufferCreate(kCFAllocatorDefault, 1_280, 720, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buffer)
    if let buffer {
        syntheticFrame(buffer, index: index * 40)
        liveFrames.append(buffer)
    }
}
let feeding = DispatchQueue(label: "live.feed")
let audioTimer = DispatchSource.makeTimerSource(queue: feeding)
var liveChunk = [Float](repeating: 0, count: 960)
var liveAudioFrames = 0
audioTimer.schedule(deadline: .now(), repeating: .milliseconds(10))
audioTimer.setEventHandler {
    for index in 0..<480 {
        let value = Float(0.2 * sin(2 * .pi * 440 * Double(liveAudioFrames + index) / 48_000))
        liveChunk[index * 2] = value
        liveChunk[index * 2 + 1] = value
    }
    liveChunk.withUnsafeBufferPointer { pointer in
        liveRing.write(left: pointer.baseAddress!, right: pointer.baseAddress! + 1, stride: 2, frames: 480,
                       host: HostClock.now() - 0.01, rate: 48_000)
    }
    liveAudioFrames += 480
}
audioTimer.resume()
let videoTimer = DispatchSource.makeTimerSource(flags: .strict, queue: feeding)
var liveIndex = 0
videoTimer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(2))
videoTimer.setEventHandler {
    guard !liveFrames.isEmpty else { return }
    live.appendVideo(liveFrames[liveIndex % liveFrames.count], at: HostClock.now())
    liveIndex += 1
}
videoTimer.resume()

check(waitFor(6) { liveStore.hasInitialization && liveStore.segmentCount >= 1 }, "실시간으로도 첫 조각이 나온다")

/// 끝없는 MP4 를 받아 모은다.
final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}

let collector = Collector()
let streaming = URLSession(configuration: httpConfiguration, delegate: collector, delegateQueue: nil)
let progressiveURL = URL(string: "http://127.0.0.1:\(livePort ?? 0)\(liveServer.basePath)stage.mp4")!
let streamTask = streaming.dataTask(with: progressiveURL)
streamTask.resume()
check(waitFor(5) { collector.data.count > 1_000 }, "끝없는 MP4 가 흘러온다")
let backlog = collector.data.count
let segmentsBefore = liveStore.segmentCount
_ = waitFor(4) { liveStore.segmentCount >= segmentsBefore + 2 }
check(waitFor(3) { collector.data.count > backlog }, "새 조각이 나오면 이어 보낸다 (\(backlog) → \(collector.data.count)바이트)")
let streamStatus = (streamTask.response as? HTTPURLResponse)?.statusCode
let streamType = (streamTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
streamTask.cancel()
let streamed = collector.data
check(streamStatus == 200 && streamType == "video/mp4", "끝없는 MP4 는 200 video/mp4")
check(streamed.count > 8 && String(decoding: streamed[4..<8], as: UTF8.self) == "ftyp", "ftyp 로 시작한다")
if let moov = streamed.range(of: Data("moov".utf8)) {
    check(streamed[moov.upperBound...].range(of: Data("moof".utf8)) != nil, "moov 뒤로 moof 가 이어진다")
} else {
    check(false, "moov 가 있다")
}

videoTimer.cancel()
audioTimer.cancel()
let liveSeconds = HostClock.now() - liveStart
let liveDone = DispatchSemaphore(value: 0)
live.finish { liveDone.signal() }
_ = liveDone.wait(timeout: .now() + 10)
let liveStats = live.stats
print("  실시간 \(String(format: "%.1f", liveSeconds))초: 프레임 \(liveStats.frames)장(버림 \(liveStats.dropped)), 소리 \(liveStats.audioFrames)칸, 조각 \(liveStore.segmentCount)개")
check(liveFailed == nil, "실시간 굽기가 멈추지 않는다 \(liveFailed ?? "")")
check(Double(liveStats.frames) >= liveSeconds * 30 * 0.85, "실시간 프레임을 거의 다 넣는다")
check(Double(liveStats.audioFrames) >= (liveSeconds - 0.3) * 48_000, "실시간 소리도 끊김 없이 넣는다")
check(liveServer.remoteRequests.count == 0, "이 Mac 손님은 세지 않는다")
liveServer.stop()
server.stop()

print("\(passes) 통과, \(failures) 실패")
exit(failures == 0 ? 0 : 1)
