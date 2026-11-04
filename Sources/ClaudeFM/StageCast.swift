import AppKit
import CoreVideo
import ImageIO

/// TV 로 소리도 보내는지.
enum CastSound: Equatable {
    /// 시스템 소리를 TV 로 보내고 이 Mac 에서는 끈다.
    case sending
    /// 시스템 오디오 녹음 권한이 없어 화면만 보낸다.
    case needsPermission
    /// 이 macOS 는 시스템 소리를 받을 수 없어 화면만 보낸다.
    case unsupported
}

/// TV 로 보낼 무대를 1280×720 으로 그린다. 창과 같은 감독에게서 장면을 받아, 320×180 픽셀 무대를
/// 네 배로 키우고 글자 층을 TV 안전 영역 안에 얹는다. 무대 창이 닫혀 있거나 가려져도 계속 그린다.
@MainActor
final class StageCastRenderer {
    static let size = CGSize(width: 1_280, height: 720)

    private let director: StageDirector
    private let canvas = RasterCanvas(width: 320, height: 180)
    private let hud: StageHUDView
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var timer: DispatchSourceTimer?
    private weak var encoder: StageStreamEncoder?

    init(director: StageDirector) {
        self.director = director
        hud = StageHUDView(frame: NSRect(origin: .zero, size: Self.size))
        // TV 가 가장자리를 조금 잘라 먹어도 글자가 남도록 4% 안쪽에 그린다.
        hud.safeInset = NSSize(width: 51, height: 29)
    }

    /// 1/30초마다 한 장씩 그려 엔코더에 넣는다. 메뉴를 여는 동안에도 멈추지 않는다.
    func start(encoder: StageStreamEncoder, fps: Int32 = 30) {
        stop()
        self.encoder = encoder
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / Int64(max(1, fps)))), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        encoder = nil
    }

    private func tick() {
        // 엔코더가 밀려 있으면 한 장 쉰다. 그림이 늦게 쌓이는 것보다 낫다.
        guard let encoder, encoder.pendingFrames < 3, let pool = encoder.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        let host = HostClock.now()
        draw(into: buffer, at: ProcessInfo.processInfo.systemUptime)
        encoder.appendVideo(buffer, at: host)
    }

    /// `uptime` 의 장면을 `buffer`(BGRA)에 그린다.
    func draw(into buffer: CVPixelBuffer, at uptime: TimeInterval) {
        director.advance(to: uptime)
        StageScene.render(director.input(width: canvas.width, height: canvas.height), into: canvas)
        hud.update(director.hud(for: .tv))
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return }
        defer { _ = CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        paint(context, size: CGSize(width: width, height: height), at: uptime)
    }

    private func paint(_ context: CGContext, size: CGSize, at uptime: TimeInterval) {
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if let image = canvas.makeImage() {
            let scale = size.width / CGFloat(canvas.width)
            let shake = director.shake(at: uptime)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: (CGFloat(shake.dx) * scale).rounded(), y: (CGFloat(shake.dy) * scale).rounded(),
                                           width: size.width, height: CGFloat(canvas.height) * scale))
        }
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if let appearance = NSAppearance(named: .darkAqua) {
            appearance.performAsCurrentDrawingAppearance { hud.draw(hud.bounds) }
        } else {
            hud.draw(hud.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    /// 수신기 알림에 쓰는 무대 그림(640×360 JPEG).
    func posterJPEG() -> Data? {
        guard let image = canvas.makeImage(),
              let context = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 360))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// 무대를 크롬캐스트로 보낸다. 기기를 찾고, 영상을 굽고 내주고, TV 와 이야기하고, 소리를 TV 로 돌린다.
/// 잘 안 되면 이유를 짧게 알리고 모든 것을 원래대로 되돌린다.
@MainActor
final class StageCaster: NSObject, ObservableObject, NSMenuDelegate {
    enum Phase: Equatable {
        case idle
        case connecting(CastDevice)
        case casting(CastDevice)

        var device: CastDevice? {
            switch self {
            case .idle: return nil
            case .connecting(let device), .casting(let device): return device
            }
        }
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var sound = CastSound.sending
    @Published private(set) var waitingForApproval = false
    /// 최근에 안 된 이유. 메뉴 머리에 잠깐 남겨 둔다.
    @Published private(set) var problem: String?

    /// 알릴 말(한 줄과 덧붙임). 무대가 보이면 무대에, 아니면 말풍선으로 띄운다.
    var onNotice: ((String, String?) -> Void)?
    /// 상태가 바뀔 때마다. 무대 창 TV 단추와 가사 찾기를 맞춘다.
    var onChange: (() -> Void)?
    /// 소리를 TV 로 돌린다. 소리를 보낼 수 있는지 돌려준다.
    var startSound: ((StageAudioRing) -> CastSound)?
    /// 이 Mac 소리를 되돌린다.
    var stopSound: (() -> Void)?
    /// 지금 오디오 탭의 표본율.
    var sampleRate: (() -> Double?)?

    private let director: StageDirector
    private let discovery = CastDiscovery()
    private var session: CastSession?
    private var encoder: StageStreamEncoder?
    private var server: StageStreamServer?
    private var store: StageSegmentStore?
    private var renderer: StageCastRenderer?
    private var ring: StageAudioRing?
    private var activity: NSObjectProtocol?
    private var watchdog: Timer?
    private var browseTimer: Timer?
    private var generation = 0
    private var localHost: String?
    private var serverPort: UInt16?
    private var receiverReady = false
    private var format = CastMedia.Format.hls
    private var loadSentAt: TimeInterval?
    private var reloads = 0
    private var startedAt: TimeInterval = 0
    private var problemAt: TimeInterval = -1_000
    private var soundWarned = false
    private var browseUntil: TimeInterval = 0
    private var openMenus: [NSMenu] = []
    private var populatedHeader: [String] = []

    init(director: StageDirector) {
        self.director = director
        super.init()
        discovery.onChange = { [weak self] in self?.discoveryChanged() }
    }

    var isActive: Bool { phase != .idle }

    var isCasting: Bool {
        if case .casting = phase { return true }
        return false
    }

    // MARK: - 보이는 글

    /// 무대 창 TV 단추.
    var badge: StageCastBadge.Status {
        switch phase {
        case .idle: return .idle
        case .connecting(let device): return .connecting(device.name)
        case .casting(let device): return .casting(device.name)
        }
    }

    /// 메뉴바 메뉴의 항목 이름.
    var menuTitle: String {
        switch phase {
        case .idle: return "무대를 TV 로 보내기"
        case .connecting(let device): return "연결 중 · \(device.name)"
        case .casting(let device): return "TV 로 보내는 중 · \(device.name)"
        }
    }

    /// 팝오버에 적는 한 줄. 보내지 않는 동안에는 최근에 안 된 이유만.
    var statusLine: String? {
        switch phase {
        case .idle:
            return recentProblem
        case .connecting(let device):
            return waitingForApproval ? "TV 화면에서 허용을 눌러 주세요 · \(device.name)" : "연결 중 · \(device.name)"
        case .casting(let device):
            return "TV 로 보내는 중 · \(device.name) · " + (sound == .sending ? "소리는 TV 에서 나와요" : "화면만 보내요")
        }
    }

    private var soundLine: String {
        switch sound {
        case .sending: return "소리는 TV 에서 나와요"
        case .needsPermission: return "화면만 보내는 중 · 시스템 오디오 녹음 권한이 필요해요"
        case .unsupported: return "화면만 보내는 중 · macOS 14.2 부터 소리도 보내요"
        }
    }

    private var recentProblem: String? {
        guard let problem, now - problemAt < 60 else { return nil }
        return problem
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - 보내기

    func start(_ device: CastDevice) {
        if phase.device == device { return }
        if isActive { teardown() }
        generation += 1
        let current = generation
        problem = nil
        phase = .connecting(device)
        startedAt = now
        format = .hls
        reloads = 0
        loadSentAt = nil
        receiverReady = false
        localHost = nil
        serverPort = nil
        waitingForApproval = false
        soundWarned = false
        // 보내는 동안에는 앱이 낮잠 들거나 Mac 이 잠들지 않게 한다. 타이머도 제때 돈다.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "무대를 TV 로 보내는 중")

        let tapRate = sampleRate?() ?? 48_000
        let ring = StageAudioRing(capacity: Int(max(tapRate, 8_000) * 4))
        let store = StageSegmentStore()
        var settings = StageStreamEncoder.Settings()
        settings.sampleRate = abs(tapRate - 44_100) < 1 ? 44_100 : 48_000
        let encoder = StageStreamEncoder(settings: settings, store: store, ring: ring)
        encoder.onFailure = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    self.fail("무대 영상을 만들지 못했어요")
                }
            }
        }
        do {
            try encoder.start(at: HostClock.now())
        } catch {
            NSLog("[ClaudeFM] cast encoder failed: \(error)")
            activityEnd()
            phase = .idle
            report("무대 영상을 만들지 못했어요", detail: nil)
            changed()
            return
        }
        self.ring = ring
        self.store = store
        self.encoder = encoder
        let renderer = StageCastRenderer(director: director)
        renderer.start(encoder: encoder, fps: settings.frameRate)
        self.renderer = renderer

        let server = StageStreamServer(store: store)
        server.start { [weak self] port in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    guard let port else { return self.fail("TV 에 보낼 길을 열지 못했어요") }
                    self.serverPort = port
                    self.loadIfReady()
                }
            }
        }
        self.server = server

        sound = startSound?(ring) ?? .unsupported
        let session = CastSession(endpoint: device.endpoint)
        session.onEvent = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.handle(event)
            }
        }
        self.session = session
        session.start()

        let watchdog = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        self.watchdog = watchdog

        switch sound {
        case .sending:
            onNotice?("TV 에 연결하는 중 · \(device.name)", "소리는 TV 에서 나와요")
        case .needsPermission:
            onNotice?("시스템 오디오 녹음 권한이 있어야 소리도 TV 로 보낼 수 있어요", "지금은 화면만 보내요")
        case .unsupported:
            onNotice?("macOS 14.2 부터 소리도 TV 로 보낼 수 있어요", "지금은 화면만 보내요")
        }
        changed()
    }

    /// 그만 보낸다. TV 의 수신기 앱을 닫고 이 Mac 소리를 되돌린다.
    func stop() {
        guard isActive else { return }
        teardown()
        onNotice?("TV 로 보내기를 멈췄어요", nil)
    }

    /// 앱을 끝낼 때. TV 에 닫는 말을 보내고 잠깐 기다린다. 소리는 탭이 닫히며 돌아온다.
    func shutdownForQuit() {
        guard isActive else { return }
        generation += 1
        watchdog?.invalidate()
        renderer?.stop()
        session?.onEvent = nil
        session?.stopAndWait(timeout: 0.8)
        server?.stop()
        activityEnd()
    }

    private func teardown() {
        generation += 1
        watchdog?.invalidate()
        watchdog = nil
        renderer?.stop()
        renderer = nil
        session?.onEvent = nil
        session?.stop()
        session = nil
        encoder?.finish()
        encoder = nil
        server?.stop()
        server = nil
        store = nil
        if ring != nil {
            stopSound?()
            ring = nil
        }
        activityEnd()
        waitingForApproval = false
        phase = .idle
        changed()
    }

    private func activityEnd() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func fail(_ message: String, detail: String? = nil) {
        guard isActive else { return }
        teardown()
        report(message, detail: detail)
    }

    private func report(_ message: String, detail: String?) {
        problem = message
        problemAt = now
        onNotice?(message, detail)
    }

    // MARK: - TV 소식

    private func handle(_ event: CastSession.Event) {
        guard let device = phase.device else { return }
        switch event {
        case .connected(let host):
            localHost = host ?? StageStreamServer.localIPv4Addresses().first
            if localHost == nil { fail("TV 에서 이 Mac 의 주소를 찾지 못했어요") }
        case .waitingForApproval:
            guard !waitingForApproval else { return }
            waitingForApproval = true
            onNotice?("TV 화면에서 허용을 눌러 주세요", device.name)
            changed()
        case .ready:
            receiverReady = true
            if waitingForApproval {
                waitingForApproval = false
                changed()
            }
            if loadSentAt == nil {
                loadIfReady()
            } else {
                // 수신기 세션이 바뀌었으면 새 세션에 다시 불러온다.
                sendLoad()
            }
        case .media(let state):
            guard state == "PLAYING", case .connecting = phase else { return }
            phase = .casting(device)
            onNotice?("TV 로 보내는 중 · \(device.name)", sound == .sending ? soundLine : nil)
            changed()
        case .mediaIdle(let reason):
            switch reason {
            case "CANCELLED", "INTERRUPTED":
                finish("TV 에서 무대를 멈췄어요")
            case "ERROR", "FINISHED":
                if isCasting, reloads < 2 {
                    // 잠깐 끊긴 것이면 같은 영상을 다시 불러온다.
                    reloads += 1
                    sendLoad()
                } else {
                    mediaTrouble()
                }
            default:
                break
            }
        case .loadFailed:
            mediaTrouble()
        case .ended(let reason):
            switch reason {
            case .stopped:
                break
            case .closedOnReceiver:
                finish("TV 에서 무대를 닫았어요")
            case .connectFailed:
                fail("\(device.name) 에 연결하지 못했어요", detail: "같은 Wi-Fi 에 있는지 확인해 주세요")
            case .launchFailed(let why):
                fail(why == "denied" ? "TV 에서 허용하지 않았어요" : "TV 에서 무대를 열지 못했어요")
            case .lost:
                fail("TV 와 연결이 끊겼어요")
            }
        }
    }

    /// 이쪽 잘못이 아니게 끝났을 때. 이유는 메뉴 머리에 남기지 않는다.
    private func finish(_ message: String) {
        guard isActive else { return }
        teardown()
        onNotice?(message, nil)
    }

    /// 수신기 앱이 떴고, 조각이 세 개 넘게 쌓였고, 주소와 문을 알면 영상을 불러오게 한다.
    private func loadIfReady() {
        guard receiverReady, loadSentAt == nil, serverPort != nil, localHost != nil, (store?.segmentCount ?? 0) >= 3 else { return }
        sendLoad()
    }

    private func sendLoad() {
        guard let session, let server, let store, let port = serverPort, let host = localHost else { return }
        let base = "http://\(host):\(port)\(server.basePath)"
        if store.posterData() == nil { store.setPoster(renderer?.posterJPEG()) }
        let media = CastMedia(url: base + (format == .hls ? "stage.m3u8" : "stage.mp4"), format: format,
                              title: "Claude FM 무대", subtitle: "Clawd 의 콘서트",
                              imageURL: store.posterData() == nil ? nil : base + "poster.jpg")
        loadSentAt = now
        session.load(media)
    }

    /// TV 가 영상을 열지 못했다. HLS 가 안 되면 끝없는 MP4 한 줄기로 한 번 더 해 보고, 그래도 안 되면 이유를 알린다.
    private func mediaTrouble() {
        guard isActive else { return }
        if format == .hls {
            format = .progressive
            reloads = 0
            sendLoad()
            return
        }
        if fetchedSinceLoad {
            fail("TV 가 무대 영상을 재생하지 못했어요")
        } else {
            fail("TV 가 Mac 에 접속하지 못했어요", detail: "방화벽에서 Claude FM 의 들어오는 연결을 허용해 주세요")
        }
    }

    /// 마지막으로 불러오게 한 뒤에 TV 가 영상을 가져갔는지.
    private var fetchedSinceLoad: Bool {
        guard let loadSentAt, let last = server?.remoteRequests.last else { return false }
        return last >= loadSentAt
    }

    /// 1초마다 살핀다. 멈춘 곳이 있으면 오래 기다리지 않고 알린다.
    private func watch() {
        guard isActive else { return }
        let time = now
        loadIfReady()
        if time - (store?.lastSegmentUptime ?? startedAt) > 8 {
            return fail("무대 영상을 만들지 못했어요")
        }
        switch phase {
        case .connecting:
            if let sent = loadSentAt {
                if !fetchedSinceLoad, time - sent > 15 { return mediaTrouble() }
                if time - sent > 35 { return mediaTrouble() }
            } else if time - startedAt > (waitingForApproval ? 100 : 45) {
                fail(receiverReady ? "TV 가 무대 영상을 열지 못했어요" : "TV 에서 무대를 열지 못했어요")
            }
        case .casting:
            // 소리를 보내기로 했는데 탭이 멈췄으면 한 번 알린다. 이때 Mac 소리는 탭이 멈추며 돌아와 있다.
            if sound == .sending, !soundWarned, let ring, HostClock.now() - ring.lastWriteHost > 3 {
                soundWarned = true
                onNotice?("소리를 받지 못하고 있어요", "TV 에는 화면만 나가요")
            }
        case .idle:
            break
        }
    }

    // MARK: - 기기 찾기와 메뉴

    /// 메뉴를 열 때 찾기 시작한다. 마지막으로 연 뒤 90초가 지나고 보내는 중이 아니면 쉰다.
    func beginBrowsing() {
        browseUntil = now + 90
        if !discovery.isRunning { discovery.start() }
        guard browseTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.browseTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        browseTimer = timer
    }

    private func browseTick() {
        // '찾는 중' 이 오래가면 안내가 바뀐다. 글이 바뀔 때만 열린 메뉴를 다시 채워 고른 줄이 흔들리지 않게 한다.
        if headerLines() != populatedHeader { refreshOpenMenus() }
        guard now > browseUntil, openMenus.isEmpty else { return }
        discovery.stop()
        browseTimer?.invalidate()
        browseTimer = nil
    }

    private func discoveryChanged() {
        if devices != discovery.devices { devices = discovery.devices }
        changed()
    }

    /// 상태가 바뀌었다. 열린 메뉴를 다시 채우고 바깥에 알린다.
    private func changed() {
        refreshOpenMenus()
        onChange?()
    }

    private func refreshOpenMenus() {
        for menu in openMenus { populate(menu) }
    }

    /// 무대 창 TV 단추 아래에 기기 목록을 띄운다.
    func popUpMenu(below view: NSView) {
        let menu = makeMenu()
        let x = view.bounds.maxX - menu.size.width
        let y = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        _ = menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: view)
    }

    /// 마우스 자리에 기기 목록을 띄운다. 팝오버에서 쓴다.
    func popUpMenuAtMouse() {
        let menu = makeMenu()
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "무대를 TV 로 보내기")
        menu.delegate = self
        beginBrowsing()
        populate(menu)
        return menu
    }

    /// 상태 줄, 기기, 그만 보내기, 권한 안내를 차례로 채운다.
    func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let lines = headerLines()
        populatedHeader = lines
        for line in lines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        var shown = devices
        if let active = phase.device, !shown.contains(where: { $0.id == active.id }) { shown.insert(active, at: 0) }
        if !lines.isEmpty, !shown.isEmpty { menu.addItem(.separator()) }
        for device in shown {
            let item = NSMenuItem(title: device.name, action: #selector(pickDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = phase.device?.id == device.id ? .on : .off
            item.image = NSImage(systemSymbolName: "tv", accessibilityDescription: nil)
            if let model = device.model, model != device.name { item.toolTip = model }
            menu.addItem(item)
        }
        if isActive {
            menu.addItem(.separator())
            let stop = NSMenuItem(title: "그만 보내기", action: #selector(stopFromMenu), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
        if isActive, sound == .needsPermission {
            let item = NSMenuItem(title: "시스템 오디오 권한 열기…", action: #selector(openAudioSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if discovery.status == .denied {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "로컬 네트워크 설정 열기…", action: #selector(openLocalNetworkSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    private func headerLines() -> [String] {
        switch phase {
        case .casting(let device):
            return ["TV 로 보내는 중 · \(device.name)", soundLine]
        case .connecting(let device):
            return [waitingForApproval ? "TV 화면에서 허용을 눌러 주세요 · \(device.name)" : "연결 중 · \(device.name)"]
        case .idle:
            var lines: [String] = []
            if let problem = recentProblem { lines.append(problem) }
            if discovery.status == .denied {
                lines += ["로컬 네트워크 권한이 꺼져 있어요", "시스템 설정에서 Claude FM 을 켜 주세요"]
            } else if devices.isEmpty {
                let searched = discovery.startedAt.map { now - $0 } ?? 0
                if searched > 5 || discovery.status == .failed {
                    lines += ["TV 를 찾지 못했어요", "같은 Wi-Fi 에 있는지 확인해 주세요"]
                } else {
                    lines.append("TV 를 찾는 중…")
                }
            }
            return lines
        }
    }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let device = devices.first(where: { $0.id == id }) {
            start(device)
        }
    }

    @objc private func stopFromMenu() { stop() }

    @objc private func openAudioSettings() { RhythmDance.openSettings() }

    @objc private func openLocalNetworkSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
        ]
        for text in urls {
            if let url = URL(string: text), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        beginBrowsing()
        populate(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if !openMenus.contains(where: { $0 === menu }) { openMenus.append(menu) }
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.removeAll { $0 === menu }
    }
}
