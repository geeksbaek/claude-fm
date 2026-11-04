import AppKit

/// 무대가 프레임마다 앱에서 읽어 오는 것.
struct StageSnapshot {
    var pose = DancePose.idle
    /// Claude FM 을 듣는 중.
    var playing = false
    var accent = SpriteAccent.none
    var feeling = VocalFeeling.calm
    var spectrum: [Double] = []
    var beatCount = 0
    var beatPhase = 0.0
    var beatPeriod: Double?
    var bpm: Int?
    var mood = MusicMood.quiet
    var performance: LyricPerformance?
    var karaoke = true
    var reactions = true
    /// Claude FM 영상 제목.
    var radioTitle = "Claude FM"
    /// 시스템 오디오 권한이 없어 소리를 못 듣는 중.
    var needsPermission = false
}

/// 콘서트 무대 창. 픽셀 무대 위에 가사와 곡 정보를 얹는다.
@MainActor
final class StageWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var stageView: StageView?
    private var occlusionObserver: NSObjectProtocol?
    private let snapshot: () -> StageSnapshot
    /// 무대가 열리고 닫힐 때. 말풍선을 숨기고 가사를 찾게 한다.
    var onVisibilityChange: ((Bool) -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onNudgeSync: ((Double) -> Void)?

    init(snapshot: @escaping () -> StageSnapshot) {
        self.snapshot = snapshot
    }

    var isOpen: Bool { window?.isVisible == true }

    /// 무대가 화면에 보여서 폭죽을 대신 받을 수 있는지.
    var isShowingOnActiveSpace: Bool {
        guard let window, window.isVisible, window.isOnActiveSpace else { return false }
        return window.occlusionState.contains(.visible)
    }

    func toggle() {
        if isOpen {
            window?.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        // 무대가 열려 있는 동안은 Dock 과 ⌘Tab 에 나와서 전체 화면과 창 전환이 자연스럽다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(stageView)
        stageView?.start()
        onVisibilityChange?(true)
    }

    func celebrate(_ reaction: LyricReaction?) {
        stageView?.burst(reaction: reaction)
    }

    func noteSync(_ offset: Double) {
        stageView?.flashSync(offset)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude FM 무대"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 480, height: 270)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let view = StageView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), snapshot: snapshot)
        view.onTogglePlayback = { [weak self] in self?.onTogglePlayback?() }
        view.onNudgeSync = { [weak self] seconds in self?.onNudgeSync?(seconds) }
        window.contentView = view
        window.center()
        window.setFrameAutosaveName("ClaudeFMStage")
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stageView?.syncRunning() }
        }
        self.window = window
        stageView = view
        return window
    }

    func windowWillClose(_ notification: Notification) {
        stageView?.stop()
        NSApp.setActivationPolicy(.accessory)
        onVisibilityChange?(false)
    }
}

/// 픽셀 무대와 글자 층을 겹친 뷰. 열려 있고 보이는 동안 1/60초마다 다시 그린다.
@MainActor
final class StageView: NSView {
    private let snapshot: () -> StageSnapshot
    private let pixelLayer = CALayer()
    private let hud = StageHUDView()
    private var canvas = RasterCanvas(width: 320, height: 180)
    private var pixelScale = 4
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var bursts: [StageBurst] = []
    private var shownReaction: LyricReaction?
    private var reactionLevel = 0.0
    private var hookLevel = 0.0
    private var lastCueKey: String?
    private var cueStartedAt: TimeInterval = 0
    private var lastMouseMove: TimeInterval = -10
    private var syncShownAt: TimeInterval = -10
    private var syncValue = 0.0
    private var trackingArea: NSTrackingArea?
    var onTogglePlayback: (() -> Void)?
    var onNudgeSync: ((Double) -> Void)?

    init(frame: NSRect, snapshot: @escaping () -> StageSnapshot) {
        self.snapshot = snapshot
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        pixelLayer.magnificationFilter = .nearest
        pixelLayer.minificationFilter = .nearest
        pixelLayer.contentsGravity = .resize
        pixelLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(pixelLayer)
        hud.frame = bounds
        hud.autoresizingMask = [.width, .height]
        addSubview(hud)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    func start() {
        layoutCanvas()
        // 창이 막 열린 참이라 가림 상태가 아직 갱신되지 않았을 수 있다. 일단 돌리고, 가려지면 그때 쉰다.
        startTimer()
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 창이 가려지면 쉬고, 다시 보이면 이어 그린다.
    func syncRunning() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        if visible {
            startTimer()
        } else {
            stop()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 무대 양옆에서 위로 쏘고, 가운데 위에서 쏟아지는 폭죽.
    func burst(reaction: LyricReaction?) {
        let w = Double(canvas.width), h = Double(canvas.height)
        let colors = MoodPalette.of(snapshot().mood == .quiet ? .groove : snapshot().mood).confetti
        let seed = Int(ProcessInfo.processInfo.systemUptime * 1000) % 100_000
        let count = max(30, canvas.width / 6)
        bursts.append(StageBurst(burst: ConfettiBurst(originX: w * 0.08, originY: h * 0.98, scale: 0.9, count: count, seed: seed,
                                                      colors: colors, glyph: reaction, upward: true), age: 0))
        bursts.append(StageBurst(burst: ConfettiBurst(originX: w * 0.92, originY: h * 0.98, scale: 0.9, count: count, seed: seed + 77,
                                                      colors: colors, glyph: reaction, upward: true), age: 0))
        bursts.append(StageBurst(burst: ConfettiBurst(originX: w * 0.5, originY: -4, scale: 0.6, count: count, seed: seed + 151,
                                                      colors: colors, glyph: reaction, upward: false), age: -0.25))
    }

    func flashSync(_ offset: Double) {
        syncValue = offset
        syncShownAt = ProcessInfo.processInfo.systemUptime
    }

    override func layout() {
        super.layout()
        layoutCanvas()
    }

    /// 높이 180 칸 안팎이 되도록 정수 배율을 고른다. 칸이 고르게 커져야 픽셀이 흔들리지 않는다.
    private func layoutCanvas() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(1, Int((size.height / 180).rounded()))
        let width = Int((size.width / CGFloat(scale)).rounded(.up))
        let height = Int((size.height / CGFloat(scale)).rounded(.up))
        if width != canvas.width || height != canvas.height || scale != pixelScale {
            canvas = RasterCanvas(width: width, height: height)
            pixelScale = scale
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let drawn = CGSize(width: CGFloat(width * scale), height: CGFloat(height * scale))
        pixelLayer.frame = CGRect(x: ((size.width - drawn.width) / 2).rounded(), y: ((size.height - drawn.height) / 2).rounded(),
                                  width: drawn.width, height: drawn.height)
        CATransaction.commit()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        let state = snapshot()
        let cue = state.performance?.cue
        let sungLine = cue.map { !$0.isInterlude && !$0.isHumming && !$0.isTitle && $0.recap == nil } ?? false

        // 가사 반응과 후렴은 서서히 켜고 끈다. 꺼질 때도 마지막 반응이 흐려지며 사라진다.
        let wantReaction = state.reactions && sungLine ? cue?.reaction : nil
        if let wantReaction {
            if wantReaction != shownReaction {
                shownReaction = wantReaction
                reactionLevel = min(reactionLevel, 0.2)
            }
            reactionLevel = min(1, reactionLevel + dt / 0.6)
        } else {
            reactionLevel = max(0, reactionLevel - dt / 1.2)
            if reactionLevel == 0 { shownReaction = nil }
        }
        let wantHook = state.reactions && sungLine && (cue?.isHook ?? false)
        hookLevel = wantHook ? min(1, hookLevel + dt / 0.4) : max(0, hookLevel - dt / 1.5)

        bursts = bursts.compactMap { item in
            var item = item
            item.age += dt
            return item.age < ConfettiBurst.lifetime ? item : nil
        }

        let live = state.playing || state.pose.showsMotion || state.performance != nil
        var pose = state.pose
        if hookLevel > 0.5, pose.active { pose.style = .handsUp }
        // 소리를 못 듣는 동안(권한이 없거나 아주 작을 때)에는 흥얼거리고, 전광판은 잔잔한 물결로 움직인다.
        let hearing = state.pose.showsMotion || (state.spectrum.max() ?? 0) > 0.05
        var spectrum = state.spectrum
        if live, !hearing {
            spectrum = (0..<SpectrumMeter.bandCount).map { band -> Double in
                let offset = Double(band)
                let slow: Double = sin(now * 2.1 + offset * 0.8)
                let fast: Double = sin(now * 5.3 + offset * 2.1)
                return 0.32 + 0.22 * slow + 0.08 * fast
            }
        }
        var input = StageInput()
        input.time = now
        input.spriteFrame = Animation.frame(at: Date())
        input.pose = pose
        input.playing = state.playing || (live && !hearing)
        input.accent = state.accent
        input.feeling = state.feeling
        input.spectrum = spectrum
        input.beatCount = state.beatCount
        input.beatPhase = state.beatPhase
        input.reaction = shownReaction
        input.reactionLevel = reactionLevel
        input.hookLevel = hookLevel
        input.bursts = bursts
        input.hour = Calendar.current.component(.hour, from: Date())
        input.live = live
        StageScene.render(input, into: canvas)
        pixelLayer.contents = canvas.makeImage()

        let key = cue.map { "\($0.current)|\($0.start ?? -1)|\($0.isTitle)|\($0.recap != nil)" }
        if key != lastCueKey {
            lastCueKey = key
            cueStartedAt = now
        }
        var hudState = StageHUDView.State()
        hudState.palette = MoodPalette.of(pose.mood == .quiet ? .groove : pose.mood)
        hudState.cue = cue
        hudState.cueAge = now - cueStartedAt
        hudState.elapsed = state.performance?.clock?.elapsed(at: now)
        hudState.karaoke = state.karaoke
        hudState.beatPeriod = state.beatPeriod
        hudState.bpm = live ? state.bpm : nil
        hudState.moodLabel = live ? state.mood.label : nil
        hudState.hop = pose.active ? pose.hop : 0
        if let performance = state.performance {
            hudState.title = performance.title
            hudState.subtitle = performance.artist
            hudState.live = false
        } else if state.playing {
            hudState.title = state.radioTitle
            hudState.subtitle = "Claude FM"
            hudState.live = true
        } else if state.pose.showsMotion {
            hudState.title = "지금 나는 소리에 맞춰"
            hudState.subtitle = state.mood.caption ?? ""
        }
        hudState.idle = !live
        hudState.needsPermission = state.needsPermission && !hearing
        let sinceMouse = now - lastMouseMove
        hudState.hint = sinceMouse < 2.5 ? 1 : max(0, 1 - (sinceMouse - 2.5) / 0.6)
        let sinceSync = now - syncShownAt
        hudState.syncBadge = sinceSync < 1.6 ? min(1, (1.6 - sinceSync) / 0.3) : 0
        hudState.syncOffset = syncValue
        hud.update(hudState)
    }

    // MARK: - 입력

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouseMove = ProcessInfo.processInfo.systemUptime
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseMove = ProcessInfo.processInfo.systemUptime
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        lastMouseMove = ProcessInfo.processInfo.systemUptime
        switch event.keyCode {
        case 53: // esc
            if window?.styleMask.contains(.fullScreen) == true {
                window?.toggleFullScreen(nil)
            } else {
                window?.performClose(nil)
            }
        case 3, 36: // f, return
            window?.toggleFullScreen(nil)
        case 49: // space
            onTogglePlayback?()
        case 123: // ←
            onNudgeSync?(-0.1)
        case 124: // →
            onNudgeSync?(0.1)
        case 29: // 0
            onNudgeSync?(0)
        default:
            super.keyDown(with: event)
        }
    }
}

/// 무대 위 글자 층. 가사는 노래방처럼 채우고, 곡 정보·빠르기·안내를 얹는다.
@MainActor
final class StageHUDView: NSView {
    struct State: Equatable {
        var title = ""
        var subtitle = ""
        var live = false
        var bpm: Int?
        var moodLabel: String?
        var cue: LyricCue?
        var cueAge = 0.0
        var elapsed: TimeInterval?
        var karaoke = true
        var beatPeriod: Double?
        var idle = true
        var hint = 0.0
        var syncBadge = 0.0
        var syncOffset = 0.0
        var palette = MoodPalette.of(.groove)
        var hop = 0.0
        var needsPermission = false

        /// 프레임마다 바뀌는 값을 뺀 나머지가 같으면 위쪽 글자는 다시 그리지 않는다.
        func sameHeader(as other: State) -> Bool {
            title == other.title && subtitle == other.subtitle && live == other.live && bpm == other.bpm
                && moodLabel == other.moodLabel && syncBadge == other.syncBadge && syncOffset == other.syncOffset
                && needsPermission == other.needsPermission
        }
    }

    private(set) var state = State()

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ next: State) {
        guard next != state else { return }
        let headerChanged = !next.sameHeader(as: state)
        state = next
        if headerChanged {
            needsDisplay = true
        } else {
            // 가사 띠와 가운데 띠만 매 프레임 다시 그린다.
            setNeedsDisplay(NSRect(x: 0, y: bounds.height * 0.2, width: bounds.width, height: bounds.height * 0.8))
        }
    }

    private var unit: CGFloat { max(0.6, min(1.6, bounds.height / 540)) }

    override func draw(_ dirtyRect: NSRect) {
        drawBottomShade(dirtyRect)
        drawHeader()
        drawCenter()
        drawLyrics()
        drawHint()
        drawSyncBadge()
    }

    // MARK: - 바탕

    private func drawBottomShade(_ dirtyRect: NSRect) {
        let top = bounds.height * 0.64
        let band = NSRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
        guard band.intersects(dirtyRect),
              let gradient = NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.62)]) else { return }
        gradient.draw(from: NSPoint(x: 0, y: top), to: NSPoint(x: 0, y: bounds.height), options: [])
    }

    // MARK: - 곡 정보

    private func drawHeader() {
        let margin = 22 * unit
        let titleFont = NSFont.systemFont(ofSize: 17 * unit, weight: .bold)
        let subFont = NSFont.systemFont(ofSize: 12.5 * unit, weight: .medium)
        let shadow = textShadow(blur: 6 * unit)
        var y = margin + 14 * unit
        if !state.title.isEmpty {
            var x = margin
            if state.live {
                let badge = drawPill("LIVE", at: NSPoint(x: x, y: y), font: NSFont.systemFont(ofSize: 10.5 * unit, weight: .heavy),
                                     fill: NSColor(srgbRed: 0.93, green: 0.22, blue: 0.24, alpha: 0.95), text: .white)
                x += badge.width + 8 * unit
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white, .shadow: shadow]
            let limit = bounds.width * 0.55
            (state.title as NSString).draw(with: NSRect(x: x, y: y - 2 * unit, width: limit, height: titleFont.pointSize * 1.4),
                                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            y += titleFont.pointSize * 1.3
            if !state.subtitle.isEmpty {
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: subFont, .foregroundColor: NSColor.white.withAlphaComponent(0.66), .shadow: shadow,
                ]
                (state.subtitle as NSString).draw(with: NSRect(x: margin, y: y, width: limit, height: subFont.pointSize * 1.4),
                                                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: subAttrs)
            }
        }
        // 오른쪽 위: 빠르기와 분위기
        var right = bounds.width - margin
        let chipFont = NSFont.monospacedDigitSystemFont(ofSize: 12 * unit, weight: .bold)
        let chipFill = NSColor.black.withAlphaComponent(0.42)
        if let mood = state.moodLabel {
            let size = pillSize(mood, font: chipFont)
            right -= size.width
            drawPill(mood, at: NSPoint(x: right, y: margin + 14 * unit), font: chipFont, fill: chipFill,
                     text: state.palette.primary.nsColor())
            right -= 8 * unit
        }
        if let bpm = state.bpm {
            let label = "♩ \(bpm)"
            let size = pillSize(label, font: chipFont)
            right -= size.width
            drawPill(label, at: NSPoint(x: right, y: margin + 14 * unit), font: chipFont, fill: chipFill, text: .white)
        }
    }

    @discardableResult
    private func drawPill(_ text: String, at origin: NSPoint, font: NSFont, fill: NSColor, text color: NSColor) -> NSSize {
        let size = pillSize(text, font: font)
        let rect = NSRect(origin: origin, size: size)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attrs)
        return size
    }

    private func pillSize(_ text: String, font: NSFont) -> NSSize {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(textSize.width + font.pointSize * 1.3), height: ceil(textSize.height + font.pointSize * 0.55))
    }

    // MARK: - 가운데: 제목 카드, 곡 기록, 쉬는 무대 안내

    private func drawCenter() {
        let centerY = bounds.height * 0.3
        if let cue = state.cue, cue.isTitle {
            let appear = min(1, state.cueAge / 0.5)
            let rise = (1 - appear) * 14 * unit
            let titleFont = NSFont.systemFont(ofSize: 40 * unit, weight: .heavy)
            let artistFont = NSFont.systemFont(ofSize: 18 * unit, weight: .semibold)
            drawCentered("♪ NOW PLAYING", y: centerY - 46 * unit + rise,
                         font: NSFont.systemFont(ofSize: 12 * unit, weight: .heavy),
                         color: state.palette.accent.nsColor(alpha: 0.9 * appear), kern: 3 * unit)
            drawCentered(cue.current, y: centerY - 22 * unit + rise, font: titleFont, color: NSColor.white.withAlphaComponent(appear))
            if let artist = cue.next {
                drawCentered(artist, y: centerY + 30 * unit + rise, font: artistFont,
                             color: NSColor.white.withAlphaComponent(0.72 * appear))
            }
            return
        }
        if let cue = state.cue, let recap = cue.recap {
            let appear = min(1, state.cueAge / 0.5)
            let font = NSFont.systemFont(ofSize: 46 * unit, weight: .heavy)
            let glyph = PixelGlyph.reaction(recap.reaction)
            let textWidth = (recap.headline as NSString).size(withAttributes: [.font: font]).width
            let pixel = (7 * unit).rounded()
            let glyphX = (bounds.width - textWidth) / 2 - pixel * 5 - 18 * unit
            drawGlyph(glyph, x: glyphX, y: centerY - pixel * 2.5 - state.hop * 6 * unit, pixel: pixel, alpha: appear)
            drawGlyph(glyph, x: (bounds.width + textWidth) / 2 + 18 * unit, y: centerY - pixel * 2.5 - state.hop * 6 * unit,
                      pixel: pixel, alpha: appear)
            drawCentered(recap.headline, y: centerY - font.pointSize * 0.62, font: font, color: NSColor.white.withAlphaComponent(appear))
            drawCentered(recap.caption, y: centerY + font.pointSize * 0.62, font: NSFont.systemFont(ofSize: 16 * unit, weight: .semibold),
                         color: NSColor.white.withAlphaComponent(0.7 * appear))
            return
        }
        if state.idle {
            drawCentered("음악을 틀면 무대가 시작돼요", y: bounds.height * 0.83, font: NSFont.systemFont(ofSize: 20 * unit, weight: .bold),
                         color: NSColor.white.withAlphaComponent(0.85))
            drawCentered("Claude FM 을 재생하거나 다른 앱에서 노래를 틀어 보세요", y: bounds.height * 0.83 + 30 * unit,
                         font: NSFont.systemFont(ofSize: 13 * unit, weight: .medium), color: NSColor.white.withAlphaComponent(0.55))
        }
    }

    // MARK: - 가사

    private func drawLyrics() {
        guard let cue = state.cue, !cue.isTitle, cue.recap == nil else { return }
        let bottom = bounds.height - 34 * unit
        let lyricFont = NSFont.systemFont(ofSize: 40 * unit, weight: .heavy)
        let nextFont = NSFont.systemFont(ofSize: 21 * unit, weight: .semibold)
        let originalFont = NSFont.systemFont(ofSize: 14 * unit, weight: .medium)
        let maxWidth = bounds.width * 0.86

        if cue.isHumming {
            // 가사를 모르는 곡은 제목을 작게 띄운다.
            if !state.title.isEmpty {
                drawCentered("♪  \(state.title)", y: bottom - nextFont.pointSize * 1.6, font: nextFont,
                             color: NSColor.white.withAlphaComponent(0.75))
            }
            return
        }

        let nextHeight = cue.next == nil ? 0 : nextFont.pointSize * 1.35
        if cue.isInterlude {
            if let next = cue.next {
                drawCentered(fit(next, font: nextFont, width: maxWidth), y: bottom - nextHeight, font: nextFont,
                             color: NSColor.white.withAlphaComponent(0.6))
                drawCountdown(cue, centerY: bottom - nextHeight - 24 * unit)
            }
            return
        }

        let (lines, font) = wrap(cue.current, font: lyricFont, width: maxWidth)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let blockHeight = lineHeight * CGFloat(lines.count)
        let top = bottom - nextHeight - 8 * unit - blockHeight
        let progress: Double? = state.karaoke ? state.elapsed.flatMap { cue.progress(at: $0) } : nil
        let hook = cue.isHook
        let baseColor = NSColor.white.withAlphaComponent(0.94)
        let sungColor = hook ? NSColor(srgbRed: 1.0, green: 0.80, blue: 0.32, alpha: 1)
                             : NSColor(srgbRed: 1.0, green: 0.56, blue: 0.40, alpha: 1)
        let widths = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }
        let total = widths.reduce(0, +)
        var remaining = (progress ?? 0) * Double(total)
        let shadow = textShadow(blur: 10 * unit)
        for (index, line) in lines.enumerated() {
            let width = widths[index]
            let x = (bounds.width - width) / 2
            let y = top + CGFloat(index) * lineHeight
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: baseColor, .shadow: shadow]
            (line as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            let take = min(Double(width), max(0, remaining))
            remaining -= Double(width)
            if progress != nil, take > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: x - 2, y: y - 4 * unit, width: CGFloat(take) + 2, height: lineHeight + 8 * unit)).addClip()
                let glow = NSShadow()
                glow.shadowColor = sungColor.withAlphaComponent(0.65)
                glow.shadowBlurRadius = 14 * unit
                glow.shadowOffset = .zero
                let sung: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: sungColor, .shadow: glow]
                (line as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: sung)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // 원문이 발음과 다르면 그 위에 작게 단다.
        let original = cue.original.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !original.isEmpty, LyricInsight.hookKey(original) != LyricInsight.hookKey(cue.current) {
            drawCentered(fit(original, font: originalFont, width: maxWidth), y: top - originalFont.pointSize * 1.5, font: originalFont,
                         color: NSColor.white.withAlphaComponent(0.55))
        }
        if let next = cue.next {
            drawCentered(fit(next, font: nextFont, width: maxWidth), y: bottom - nextHeight, font: nextFont,
                         color: NSColor.white.withAlphaComponent(0.5))
        }
        if let elapsed = state.elapsed, let remainingTime = cue.countdown(at: elapsed),
           remainingTime <= LyricCue.countdownBeat(state.beatPeriod) * Double(LyricCue.countdownDots) {
            drawCountdown(cue, centerY: top - (original.isEmpty ? 16 : 34) * unit)
        }
    }

    /// 노래방 카운트다운: 다음 줄까지 남은 박을 큰 점으로 센다.
    private func drawCountdown(_ cue: LyricCue, centerY: CGFloat) {
        guard let elapsed = state.elapsed, let remaining = cue.countdown(at: elapsed) else { return }
        let beat = LyricCue.countdownBeat(state.beatPeriod)
        let total = LyricCue.countdownDots
        guard remaining <= beat * Double(total) else { return }
        let dots = min(total, Int(ceil(remaining / beat)))
        let radius = 7 * unit
        let spacing = 30 * unit
        for index in 0..<total where index >= total - dots {
            let x = bounds.width / 2 + (CGFloat(index) - CGFloat(total - 1) / 2) * spacing
            let rect = NSRect(x: x - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            state.palette.accent.nsColor(alpha: 0.95).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    // MARK: - 안내

    private func drawHint() {
        guard state.hint > 0.01 else { return }
        let font = NSFont.systemFont(ofSize: 11 * unit, weight: .medium)
        let text = "더블클릭 전체 화면  ·  ← → 가사 싱크  ·  스페이스 Claude FM  ·  esc 닫기"
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.6 * state.hint)]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: bounds.width - size.width - 18 * unit, y: bounds.height - size.height - 10 * unit),
                                withAttributes: attrs)
    }

    private func drawSyncBadge() {
        if state.needsPermission, state.syncBadge <= 0.01 {
            let text = "시스템 오디오 녹음을 허용하면 무대가 음악에 맞춰 춤춰요"
            let font = NSFont.systemFont(ofSize: 12 * unit, weight: .semibold)
            let size = pillSize(text, font: font)
            drawPill(text, at: NSPoint(x: (bounds.width - size.width) / 2, y: 24 * unit), font: font,
                     fill: NSColor.black.withAlphaComponent(0.5), text: NSColor.white.withAlphaComponent(0.85))
            return
        }
        guard state.syncBadge > 0.01 else { return }
        let value = state.syncOffset
        let text = value == 0 ? "가사 싱크 맞춤" : String(format: "가사 %@ %.1f초", value > 0 ? "늦게" : "빠르게", abs(value))
        let font = NSFont.systemFont(ofSize: 13 * unit, weight: .bold)
        let size = pillSize(text, font: font)
        drawPill(text, at: NSPoint(x: (bounds.width - size.width) / 2, y: 24 * unit), font: font,
                 fill: NSColor.black.withAlphaComponent(0.55 * state.syncBadge),
                 text: NSColor.white.withAlphaComponent(state.syncBadge))
    }

    // MARK: - 도우미

    private func textShadow(blur: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    private func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: textShadow(blur: 8 * unit)]
        if kern != 0 { attrs[.kern] = kern }
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
    }

    private func drawGlyph(_ glyph: PixelGlyph, x: CGFloat, y: CGFloat, pixel: CGFloat, alpha: CGFloat) {
        for dot in glyph.pixels {
            dot.color.nsColor(alpha: alpha).setFill()
            NSRect(x: x + CGFloat(dot.x) * pixel, y: y + CGFloat(dot.y) * pixel, width: pixel, height: pixel).fill()
        }
    }

    /// 한 줄에 안 들어가면 글자를 조금 줄이고, 그래도 넘치면 두 줄로 나눈다.
    private func wrap(_ text: String, font: NSFont, width: CGFloat) -> ([String], NSFont) {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        func measure(_ value: String, _ f: NSFont) -> CGFloat { (value as NSString).size(withAttributes: [.font: f]).width }
        if measure(clean, font) <= width { return ([clean], font) }
        let smaller = NSFont.systemFont(ofSize: font.pointSize * 0.82, weight: .heavy)
        if measure(clean, smaller) <= width { return ([clean], smaller) }
        let words = clean.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return ([fit(clean, font: smaller, width: width)], smaller) }
        var best = 1
        var bestCost = CGFloat.greatestFiniteMagnitude
        for split in 1..<words.count {
            let left = words[..<split].joined(separator: " "), right = words[split...].joined(separator: " ")
            let cost = abs(measure(left, smaller) - measure(right, smaller))
            if cost < bestCost {
                bestCost = cost
                best = split
            }
        }
        let first = fit(words[..<best].joined(separator: " "), font: smaller, width: width)
        let second = fit(words[best...].joined(separator: " "), font: smaller, width: width)
        return ([first, second], smaller)
    }

    /// 너비에 맞게 끝을 말줄임표로 줄인다.
    private func fit(_ text: String, font: NSFont, width: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attrs).width <= width { return text }
        var chars = Array(text)
        while chars.count > 1 {
            chars.removeLast()
            let candidate = String(chars) + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= width { return candidate }
        }
        return text
    }
}

extension RasterCanvas {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// 픽셀 판을 그대로 CGImage 로. 화면에서는 이웃 픽셀 그대로 키운다.
    func makeImage() -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
