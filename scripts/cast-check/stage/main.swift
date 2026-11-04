import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import ImageIO

// TV 로 보낼 무대를 앱과 똑같은 감독·그림판·엔코더로 몇 초 구워 본다. 창 없이 돈다.
// 감독이 창과 TV 에 같은 장면을 주는지, TV 그림이 뒤집히거나 색 순서가 바뀌지 않았는지 픽셀 무대와 견주고,
// 구운 영상을 되읽어 본다. 폴더를 넘기면 TV 가 받을 그림과 영상을 남긴다.
//   scripts/cast-check.sh [미리보기 폴더]  (핵심 검사 뒤에 이어서 돈다)

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

func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

let previewFolder = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
if let previewFolder { try? FileManager.default.createDirectory(at: previewFolder, withIntermediateDirectories: true) }

let songStart = ProcessInfo.processInfo.systemUptime

/// 후렴 한 줄을 부르며 빠르게 춤추는 무대.
func singing(at now: TimeInterval) -> StageSnapshot {
    var snapshot = StageSnapshot()
    let beat = max(0, now - songStart) * 2
    snapshot.pose = DancePose(active: true, hop: max(0, 1 - beat.truncatingRemainder(dividingBy: 1) * 2.5), stepRight: Int(beat) % 2 == 0,
                              mood: .drive, style: .bounce, danceTime: 12)
    snapshot.feeling.wave = 0.7
    snapshot.feeling.bass = 0.6
    snapshot.spectrum = [0.9, 0.8, 0.65, 0.7, 0.55, 0.45, 0.35, 0.2]
    snapshot.beatCount = Int(beat)
    snapshot.beatPhase = beat.truncatingRemainder(dividingBy: 1)
    snapshot.beatPeriod = 0.5
    snapshot.bpm = 120
    snapshot.mood = .drive
    var cue = LyricCue(current: "너를 처음 만난 그 날처럼", next: "별빛이 내린 밤")
    cue.start = 10
    cue.end = 20
    cue.reaction = .love
    cue.isHook = true
    snapshot.performance = LyricPerformance(cue: cue, clock: PlaybackClock(elapsed: 10, uptime: songStart, rate: 1),
                                            title: "First Love", artist: "Clawd & Friends",
                                            position: PlaybackClock(elapsed: 70, uptime: songStart, rate: 1), duration: 200)
    snapshot.accent = SpriteAccent(reaction: .love, hook: true)
    return snapshot
}

/// 소리가 없고 권한도 없는 조용한 무대.
func quiet() -> StageSnapshot {
    var snapshot = StageSnapshot()
    snapshot.needsPermission = true
    return snapshot
}

/// BGRA 버퍼의 한 점.
func pixel(_ buffer: CVPixelBuffer, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    _ = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { _ = CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let point = base + y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
    return (Int(point[2]), Int(point[1]), Int(point[0]))
}

/// 버퍼를 줄 간격 없이 베껴 둔다(B, G, R, A 순서).
func copyBytes(_ buffer: CVPixelBuffer) -> [UInt8] {
    _ = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { _ = CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var out = [UInt8](repeating: 0, count: width * height * 4)
    out.withUnsafeMutableBufferPointer { target in
        for y in 0..<height {
            (target.baseAddress! + y * width * 4).update(from: base + y * rowBytes, count: width * 4)
        }
    }
    return out
}

/// BGRA 바이트를 PNG 로 쓴다.
func writePNG(_ bytes: [UInt8], width: Int, height: Int, to url: URL) {
    var copy = bytes
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    copy.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
    }
}

// MARK: - 감독

print("— 감독")
MainActor.assumeIsolated {
    // 창(60Hz)만 그릴 때와 창·TV(30Hz)가 같이 그릴 때, 같은 시각에 두 번 부를 때 시간이 같게 흘러야 한다.
    let t0 = songStart + 0.001
    var windowSteps: [Double] = (0...30).map { t0 + Double($0) / 60 }
    var sharedSteps = windowSteps + (0...15).map { t0 + Double($0) / 30 + 0.004 } + [t0 + 0.25, t0 + 0.25]
    sharedSteps = sharedSteps.filter { $0 <= t0 + 0.5 }.sorted()
    windowSteps.sort()
    let fixed = singing(at: songStart + 5)
    let windowOnly = StageDirector { fixed }
    let shared = StageDirector { fixed }
    for time in windowSteps { windowOnly.advance(to: time) }
    for time in sharedSteps { shared.advance(to: time) }
    let a = windowOnly.input(width: 320, height: 180)
    let b = shared.input(width: 320, height: 180)
    print("  반응 세기: 창만 \(String(format: "%.4f", a.reactionLevel)), 창과 TV \(String(format: "%.4f", b.reactionLevel))")
    check(near(a.reactionLevel, b.reactionLevel, 1e-9) && near(a.reactionLevel, 0.5 / 0.6, 1e-6), "창과 TV 가 같이 그려도 시간이 두 번 흐르지 않는다")
    check(a.reaction == .love && b.reaction == .love && a.hookLevel == b.hookLevel && a.splash == b.splash, "가사 반응과 후렴도 같다")

    let bursts = StageDirector { fixed }
    bursts.advance(to: songStart + 1)
    bursts.confetti(atX: 0.25, y: 0.5)
    let narrow = bursts.input(width: 320, height: 180).bursts.last?.burst
    let wide = bursts.input(width: 400, height: 200).bursts.last?.burst
    check(narrow?.originX == 80 && narrow?.originY == 90 && wide?.originX == 100 && wide?.originY == 100,
          "누른 자리는 판 크기가 달라도 같은 비율의 자리")
    bursts.burst(reaction: .star)
    check(bursts.input(width: 320, height: 180).bursts.count == 4, "후렴 폭죽은 양옆과 위에서 셋 더")
    bursts.advance(to: songStart + 4)
    check(bursts.input(width: 320, height: 180).bursts.isEmpty, "쉬다 돌아오면 지난 폭죽은 사라져 있다")

    let toasts = StageDirector { fixed }
    toasts.toast("창에만", onTV: false)
    toasts.advance(to: ProcessInfo.processInfo.systemUptime + 0.01)
    check(toasts.hud(for: .window).toast == "창에만" && toasts.hud(for: .tv).toast.isEmpty, "창 알림은 TV 에 안 나간다")
    toasts.toast("모두에게")
    toasts.advance(to: ProcessInfo.processInfo.systemUptime + 0.02)
    check(toasts.hud(for: .window).toast == "모두에게" && toasts.hud(for: .tv).toast == "모두에게", "무대 알림은 TV 에도 나간다")
    check(toasts.hud(for: .tv).hint == 0 && toasts.hud(for: .tv).title == "First Love", "TV 에는 조작 안내가 없고 곡 제목은 있다")

    let silent = StageDirector { quiet() }
    silent.advance(to: songStart + 1)
    check(silent.hud(for: .window).needsPermission && !silent.hud(for: .tv).needsPermission, "권한 안내는 창에만")
    check(!silent.input(width: 320, height: 180).live && silent.hud(for: .tv).idle, "소리가 없으면 쉬는 무대")

    // TV 안전 영역: 글자 층을 4% 안쪽에 그리면 맨 가장자리에는 글자가 닿지 않는다.
    let hud = StageHUDView(frame: NSRect(x: 0, y: 0, width: 1_280, height: 720))
    hud.safeInset = NSSize(width: 51, height: 29)
    var state = StageHUDView.State()
    state.title = String(repeating: "아주 긴 곡 제목 ", count: 8)
    state.subtitle = "Clawd & Friends"
    state.bpm = 128
    state.moodLabel = "빠름"
    state.idle = false
    state.toast = "TV 로 보내는 중 · 거실 TV"
    state.toastLevel = 1
    hud.update(state)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1_280, pixelsHigh: 720, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = context.cgContext
    cg.translateBy(x: 0, y: 720)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    hud.draw(hud.bounds)
    NSGraphicsContext.restoreGraphicsState()
    var outside = 0
    var inside = 0
    if let data = rep.bitmapData {
        // 비트맵은 맨 윗줄부터 쌓인다. 위에서 뒤집어 그렸으니 y 가 작을수록 화면 위쪽이다.
        for y in 0..<440 {
            for x in 0..<1_280 where data[y * rep.bytesPerRow + x * 4 + 3] > 12 {
                if x < 40 || x >= 1_240 || y < 22 { outside += 1 } else { inside += 1 }
            }
        }
    }
    check(inside > 1_000 && outside == 0, "제목·칩·알림은 TV 안전 영역 안에 (안 \(inside), 밖 \(outside))")
}

// MARK: - TV 그림판과 엔코더

print("— TV 무대 굽기")
let store = StageSegmentStore()
let ring = StageAudioRing()
var settings = StageStreamEncoder.Settings()
settings.realTime = false
let encoder = StageStreamEncoder(settings: settings, store: store, ring: ring)
var encoderFailure: String?
encoder.onFailure = { encoderFailure = $0 }
let startHost = HostClock.now()
var started = true
do {
    try encoder.start(at: startHost)
} catch {
    started = false
    print("엔코더를 시작하지 못했다: \(error)")
}
check(started && encoder.pixelBufferPool != nil, "엔코더와 픽셀 버퍼 웅덩이")

let frameCount = 120
let keptIndex = 75
let frameWidth = 1_280, frameHeight = 720
var keptFrame: [UInt8] = []
var orientationMatches = 0
var orientationSamples = 0

MainActor.assumeIsolated {
    guard started, let pool = encoder.pixelBufferPool else { return }
    let director = StageDirector { singing(at: ProcessInfo.processInfo.systemUptime) }
    let renderer = StageCastRenderer(director: director)
    let reference = RasterCanvas(width: 320, height: 180)
    let begin = ProcessInfo.processInfo.systemUptime
    director.advance(to: begin)
    director.burst(reaction: .love)
    for index in 0..<frameCount {
        // 앱처럼 1/30초마다 한 장. 그림 시각은 30fps 눈금에 딱 맞춰 붙인다.
        let due = begin + Double(index) / 30
        let wait = due - ProcessInfo.processInfo.systemUptime
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
        if index == 40 { director.launch() }
        var buffer: CVPixelBuffer?
        _ = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let buffer else { break }
        renderer.draw(into: buffer, at: ProcessInfo.processInfo.systemUptime)
        if index == keptIndex {
            keptFrame = copyBytes(buffer)
            // 같은 순간의 픽셀 무대를 따로 그려 견준다. 글자 층과 Clawd 가 없는 하늘·전광판 둘레만 본다.
            StageScene.render(director.input(width: 320, height: 180), into: reference)
            let points = [(120, 150), (200, 200), (300, 160), (380, 260), (460, 330), (250, 400),
                          (820, 150), (900, 210), (1_000, 260), (1_080, 320), (1_160, 380), (980, 420)]
            for (x, y) in points {
                let shown = pixel(buffer, x, y)
                let offset = ((y / 4) * reference.width + x / 4) * 4
                let r = Int(reference.bytes[offset]), g = Int(reference.bytes[offset + 1]), b = Int(reference.bytes[offset + 2])
                orientationSamples += 1
                if abs(shown.r - r) <= 3, abs(shown.g - g) <= 3, abs(shown.b - b) <= 3 { orientationMatches += 1 }
            }
        }
        encoder.appendVideo(buffer, at: startHost + Double(index) / 30)
        encoder.drain()
    }
    renderer.stop()
}

let finished = DispatchSemaphore(value: 0)
encoder.finish { finished.signal() }
check(finished.wait(timeout: .now() + 20) == .success, "굽기를 마친다")
let stats = encoder.stats
print("  프레임 \(stats.frames)장, 조각 \(store.listedSegments.count)개, 코덱 \(store.codecString)")
check(encoderFailure == nil, "굽다가 멈추지 않는다 \(encoderFailure ?? "")")
check(stats.frames == frameCount, "프레임을 다 넣는다")
check(orientationMatches >= orientationSamples - 1 && orientationSamples > 0,
      "TV 그림이 픽셀 무대와 같은 방향·같은 색 (\(orientationMatches)/\(orientationSamples))")

check(keptFrame.count == frameWidth * frameHeight * 4, "그린 프레임을 베꼈다")
if keptFrame.count == frameWidth * frameHeight * 4 {
    // 글자 층이 얹혔는지: 아래쪽 가사 띠에 밝은 글자 픽셀이 있다.
    var bright = 0
    for y in 520..<640 {
        for x in stride(from: 200, to: 1_080, by: 2) {
            let offset = (y * frameWidth + x) * 4
            if keptFrame[offset] > 225, keptFrame[offset + 1] > 225, keptFrame[offset + 2] > 225 { bright += 1 }
        }
    }
    check(bright > 200, "가사 글자가 TV 화면 아래에 그려진다 (\(bright))")
    if let previewFolder {
        writePNG(keptFrame, width: frameWidth, height: frameHeight, to: previewFolder.appendingPathComponent("cast-frame.png"))
    }
}

// 구운 조각을 이어 붙여 되읽고, 같은 프레임이 얼마나 그대로 돌아오는지 본다.
var joined = store.initialization() ?? Data()
for segment in store.listedSegments { joined.append(segment.data) }
let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude-fm-cast-stage-\(getpid()).mp4")
try? joined.write(to: sampleURL)
let asset = AVURLAsset(url: sampleURL)
if let video = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) {
    let output = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    var decoded = 0
    var difference: Double?
    while let sample = output.copyNextSampleBuffer() {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
        if decoded == keptIndex, keptFrame.count == frameWidth * frameHeight * 4 {
            let back = copyBytes(image)
            var total = 0
            var count = 0
            for offset in stride(from: 0, to: back.count, by: 4 * 7) {
                for channel in 0..<3 { total += abs(Int(back[offset + channel]) - Int(keptFrame[offset + channel])) }
                count += 3
            }
            difference = Double(total) / Double(max(1, count))
            if let previewFolder {
                writePNG(back, width: frameWidth, height: frameHeight, to: previewFolder.appendingPathComponent("cast-tv.png"))
            }
        }
        decoded += 1
    }
    print("  되읽은 프레임 \(decoded)장, 그린 그림과의 평균 차 \(difference.map { String(format: "%.2f", $0) } ?? "없음")")
    check(decoded == frameCount, "TV 무대 영상을 끝까지 풀어 읽는다")
    check((difference ?? 99) < 8, "H.264 로 구워도 무대가 또렷하다 (평균 차 8 아래)")
} else {
    check(false, "TV 무대 영상을 연다")
}
if let previewFolder {
    try? joined.write(to: previewFolder.appendingPathComponent("cast-stage.mp4"))
    try? (store.mediaPlaylist() ?? "").write(to: previewFolder.appendingPathComponent("cast-stage.m3u8"), atomically: true, encoding: .utf8)
}
try? FileManager.default.removeItem(at: sampleURL)

print("\(passes) 통과, \(failures) 실패")
exit(failures == 0 ? 0 : 1)
