import AppKit

/// 콘서트 무대 창. 픽셀 무대 위에 가사와 곡 정보를 얹는다. 장면은 TV 와 같이 쓰는 감독이 들고 있다.
@MainActor
final class StageWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var stageView: StageView?
    private var occlusionObserver: NSObjectProtocol?
    let director: StageDirector
    private var castStatus = StageCastBadge.Status.idle
    /// 무대가 열리고 닫힐 때. 말풍선을 숨기고 가사를 찾게 한다.
    var onVisibilityChange: ((Bool) -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onNudgeSync: ((Double) -> Void)?
    /// TV 단추를 누르거나 t 를 눌렀을 때. 단추 아래에 기기 목록을 띄운다.
    var onCastMenu: ((NSView) -> Void)?

    init(director: StageDirector) {
        self.director = director
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

    func noteSync(_ offset: Double) {
        director.flashSync(offset)
    }

    func showToast(_ text: String, onTV: Bool = true, seconds: TimeInterval = 1.8) {
        director.toast(text, onTV: onTV, seconds: seconds)
    }

    /// TV 단추에 지금 보내는 상태를 적는다.
    func updateCast(_ status: StageCastBadge.Status) {
        castStatus = status
        stageView?.castStatus = status
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
        let view = StageView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), director: director)
        view.onTogglePlayback = { [weak self] in self?.onTogglePlayback?() }
        view.onNudgeSync = { [weak self] seconds in self?.onNudgeSync?(seconds) }
        view.onCastMenu = { [weak self] anchor in self?.onCastMenu?(anchor) }
        view.castStatus = castStatus
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

/// 픽셀 무대와 글자 층을 겹친 뷰. 열려 있고 보이는 동안 1/60초마다 감독에게 장면을 받아 다시 그린다.
@MainActor
final class StageView: NSView {
    private let director: StageDirector
    private let pixelLayer = CALayer()
    private let hud = StageHUDView()
    private let castBadge = StageCastBadge()
    private var canvas = RasterCanvas(width: 320, height: 180)
    private var pixelScale = 4
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var lastMouseMove: TimeInterval = -10
    private var trackingArea: NSTrackingArea?
    var onTogglePlayback: (() -> Void)?
    var onNudgeSync: ((Double) -> Void)?
    var onCastMenu: ((NSView) -> Void)?

    var castStatus = StageCastBadge.Status.idle {
        didSet {
            guard castStatus != oldValue else { return }
            castBadge.status = castStatus
            // 상태가 바뀌면 단추를 잠깐 또렷이 보여 준다.
            lastMouseMove = ProcessInfo.processInfo.systemUptime
            layoutBadge()
        }
    }

    init(frame: NSRect, director: StageDirector) {
        self.director = director
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        pixelLayer.magnificationFilter = .nearest
        pixelLayer.minificationFilter = .nearest
        pixelLayer.contentsGravity = .resize
        pixelLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        // 글자 층(하위 뷰)이 늘 픽셀 무대 위에 오도록 픽셀 층을 뒤로 민다.
        pixelLayer.zPosition = -1
        layer?.addSublayer(pixelLayer)
        hud.frame = bounds
        hud.autoresizingMask = [.width, .height]
        addSubview(hud)
        castBadge.isHidden = true
        castBadge.alphaValue = 0
        castBadge.onPress = { [weak self] in self?.openCastMenu() }
        addSubview(castBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    func start() {
        layoutCanvas()
        layoutBadge()
        // 창이 막 열린 참이라 가림 상태가 아직 갱신되지 않았을 수 있다. 일단 돌리고, 가려지면 그때 쉰다.
        startTimer()
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        director.referenceWidth = 320
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

    override func layout() {
        super.layout()
        layoutCanvas()
        layoutBadge()
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

    /// TV 단추는 오른쪽 위 빠르기·분위기 칩 아래에 둔다. 제목 막대 아래라 눌러도 창이 끌리지 않는다.
    private func layoutBadge() {
        let unit = max(0.6, min(1.6, bounds.height / 540))
        castBadge.unit = unit
        let size = castBadge.preferredSize
        castBadge.frame = NSRect(x: (bounds.width - 22 * unit - size.width).rounded(),
                                 y: (bounds.height - 65 * unit - size.height).rounded(),
                                 width: size.width, height: size.height)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        // 저전력 모드에서는 초당 30번만 그린다.
        if ProcessInfo.processInfo.isLowPowerModeEnabled, now - lastTick < 1.0 / 40 { return }
        lastTick = now
        director.referenceWidth = canvas.width
        director.advance(to: now)
        StageScene.render(director.input(width: canvas.width, height: canvas.height), into: canvas)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pixelLayer.contents = canvas.makeImage()
        pixelLayer.setAffineTransform(shakeTransform(now))
        CATransaction.commit()

        var hudState = director.hud(for: .window)
        let sinceMouse = now - lastMouseMove
        hudState.hint = sinceMouse < 2.5 ? 1 : max(0, 1 - (sinceMouse - 2.5) / 0.6)
        hud.update(hudState)
        updateBadge(hint: hudState.hint)
    }

    /// 보내는 동안에는 단추가 늘 보이고, 아니면 안내 글처럼 마우스를 움직일 때만 나온다.
    private func updateBadge(hint: Double) {
        let alpha = CGFloat(castStatus.isActive ? max(0.8, hint) : hint)
        let hidden = alpha < 0.02
        if castBadge.isHidden != hidden { castBadge.isHidden = hidden }
        if abs(castBadge.alphaValue - alpha) > 0.005 { castBadge.alphaValue = alpha }
    }

    private func openCastMenu() {
        lastMouseMove = ProcessInfo.processInfo.systemUptime
        layoutBadge()
        updateBadge(hint: 1)
        onCastMenu?(castBadge)
    }

    /// 폭죽이 터질 때 0.4초 동안 픽셀 한두 칸만큼 흔든다.
    private func shakeTransform(_ now: TimeInterval) -> CGAffineTransform {
        let shake = director.shake(at: now)
        guard shake.dx != 0 || shake.dy != 0 else { return .identity }
        let scale = Double(pixelScale)
        return CGAffineTransform(translationX: CGFloat((shake.dx * scale).rounded()), y: CGFloat((shake.dy * scale).rounded()))
    }

    /// 지금 무대를 화면 그대로(픽셀 무대와 글자) 이미지로 만든다.
    private func snapshotImage() -> NSImage? {
        guard let pixels = canvas.makeImage() else { return nil }
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        cg.setFillColor(NSColor.black.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.interpolationQuality = .none
        cg.draw(pixels, in: pixelLayer.frame)
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let appearance = NSAppearance(named: .darkAqua) ?? effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            hud.draw(hud.bounds)
        }
        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func copySnapshot() {
        guard let image = snapshotImage() else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([image])
        director.toast("무대 사진을 복사했어요", onTV: false)
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

    /// 무대를 누르면 그 자리에서 폭죽이 솟고 관객이 환호한다. 두 번 누르면 전체 화면.
    override func mouseDown(with event: NSEvent) {
        lastMouseMove = ProcessInfo.processInfo.systemUptime
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let frame = pixelLayer.frame
        guard frame.contains(point) else { return }
        // TV 판과 크기가 달라도 같은 자리에 터지도록 판에 대한 비율로 넘긴다.
        let x = Double((point.x - frame.minX) / CGFloat(pixelScale)) / Double(canvas.width)
        let y = Double((frame.maxY - point.y) / CGFloat(pixelScale)) / Double(canvas.height)
        director.confetti(atX: x, y: y)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            copySnapshot()
            return true
        }
        return super.performKeyEquivalent(with: event)
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
            if !event.isARepeat { director.launch() }
        case 35: // p
            onTogglePlayback?()
        case 17: // t
            if !event.isARepeat { openCastMenu() }
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

/// 무대 창 오른쪽 위의 TV 단추. 누르면 같은 Wi-Fi 의 크롬캐스트 목록이 뜬다.
@MainActor
final class StageCastBadge: NSView {
    enum Status: Equatable {
        case idle
        case connecting(String)
        case casting(String)

        var isActive: Bool { self != .idle }

        var title: String {
            switch self {
            case .idle: return "TV"
            case .connecting(let name): return "연결 중 · \(name)"
            case .casting(let name): return "TV 로 보내는 중 · \(name)"
            }
        }
    }

    var status = Status.idle {
        didSet {
            guard status != oldValue else { return }
            toolTip = status.isActive ? status.title : "무대를 TV 로 보내기 (T)"
            needsDisplay = true
        }
    }

    var unit: CGFloat = 1 {
        didSet {
            guard unit != oldValue else { return }
            symbol = nil
            needsDisplay = true
        }
    }

    var onPress: (() -> Void)?
    private var pressed = false
    private var symbol: NSImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "무대를 TV 로 보내기 (T)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var font: NSFont { NSFont.systemFont(ofSize: 12 * unit, weight: .bold) }
    private var iconHeight: CGFloat { 11 * unit }

    var preferredSize: NSSize {
        let text = (status.title as NSString).size(withAttributes: [.font: font])
        let icon = iconWidth
        return NSSize(width: ceil(text.width + icon + 6 * unit + 12 * unit * 1.4),
                      height: ceil(text.height + 12 * unit * 0.7))
    }

    private var iconWidth: CGFloat {
        guard let symbol = tintedSymbol(), symbol.size.height > 0 else { return 0 }
        return iconHeight * symbol.size.width / symbol.size.height
    }

    /// 흰색으로 칠한 TV 기호. 크기가 바뀔 때만 다시 만든다.
    private func tintedSymbol() -> NSImage? {
        if let symbol { return symbol }
        guard let base = NSImage(systemSymbolName: "tv", accessibilityDescription: nil),
              let sized = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12 * unit, weight: .bold)) else { return nil }
        let size = sized.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            sized.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        symbol = tinted
        return tinted
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let fill: NSColor
        switch status {
        case .idle:
            fill = NSColor.black.withAlphaComponent(pressed ? 0.62 : 0.45)
        case .connecting:
            fill = NSColor.black.withAlphaComponent(pressed ? 0.72 : 0.56)
        case .casting:
            fill = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: pressed ? 1 : 0.92)
        }
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        var x = rect.minX + 12 * unit * 0.7
        if let symbol = tintedSymbol() {
            let width = iconWidth
            symbol.draw(in: NSRect(x: x, y: rect.midY - iconHeight / 2, width: width, height: iconHeight),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += width + 6 * unit
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (status.title as NSString).size(withAttributes: attrs)
        (status.title as NSString).draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        display()
        // 목록은 누르는 즉시 뜨고, 닫힐 때까지 여기서 기다린다.
        onPress?()
        pressed = false
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { status.isActive ? status.title : "무대를 TV 로 보내기" }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}

/// 무대 위 글자 층. 가사는 노래방처럼 채우고, 곡 정보·빠르기·안내를 얹는다.
/// TV 에서는 가장자리가 조금 잘려도 글자가 남도록 `safeInset` 만큼 안쪽에 그린다.
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
        /// 잠깐 떴다 사라지는 알림(가사 싱크, 사진 복사).
        var toast = ""
        var toastLevel = 0.0
        var palette = MoodPalette.of(.groove)
        var hop = 0.0
        var needsPermission = false
        /// 곡 진행(0...1)과 시각 글자.
        var songProgress: Double?
        var songTime = ""

        /// 프레임마다 바뀌는 값을 뺀 나머지가 같으면 위쪽 글자는 다시 그리지 않는다.
        func sameHeader(as other: State) -> Bool {
            title == other.title && subtitle == other.subtitle && live == other.live && bpm == other.bpm
                && moodLabel == other.moodLabel && toast == other.toast && toastLevel == other.toastLevel
                && needsPermission == other.needsPermission
                && (cue?.isTitle == true) == (other.cue?.isTitle == true)
        }
    }

    private(set) var state = State()
    /// 글자를 이만큼 안쪽에 그린다. 아래 그늘은 뷰 전체에 깐다.
    var safeInset = NSSize.zero {
        didSet { needsDisplay = true }
    }

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

    /// 글자를 놓는 판. 안쪽 여백을 뺀 크기이고, 그릴 때는 여백만큼 옮겨 둔다.
    private var box: NSRect {
        NSRect(x: 0, y: 0, width: max(1, bounds.width - safeInset.width * 2), height: max(1, bounds.height - safeInset.height * 2))
    }

    private var unit: CGFloat { max(0.6, min(1.6, box.height / 540)) }

    override func draw(_ dirtyRect: NSRect) {
        drawBottomShade(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        if safeInset != .zero {
            let shift = NSAffineTransform()
            shift.translateX(by: safeInset.width, yBy: safeInset.height)
            shift.concat()
        }
        drawHeader()
        drawCenter()
        drawLyrics()
        drawProgress()
        drawHint()
        drawToast()
        NSGraphicsContext.restoreGraphicsState()
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
        if !state.title.isEmpty, state.cue?.isTitle != true {
            var x = margin
            if state.live {
                let badge = drawPill("LIVE", at: NSPoint(x: x, y: y), font: NSFont.systemFont(ofSize: 10.5 * unit, weight: .heavy),
                                     fill: NSColor(srgbRed: 0.93, green: 0.22, blue: 0.24, alpha: 0.95), text: .white)
                x += badge.width + 8 * unit
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white, .shadow: shadow]
            let limit = box.width * 0.55
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
        var right = box.width - margin
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
        let centerY = box.height * 0.3
        if let cue = state.cue, cue.isTitle {
            let appear = min(1, state.cueAge / 0.5)
            let rise = (1 - appear) * 14 * unit
            let titleFont = NSFont.systemFont(ofSize: 40 * unit, weight: .heavy)
            let artistFont = NSFont.systemFont(ofSize: 18 * unit, weight: .semibold)
            drawCentered("♪ NOW PLAYING", y: centerY - 46 * unit + rise,
                         font: NSFont.systemFont(ofSize: 12 * unit, weight: .heavy),
                         color: state.palette.accent.nsColor(alpha: 0.9 * appear), kern: 3 * unit)
            let maxWidth = box.width * 0.86
            drawCentered(fit(cue.current, font: titleFont, width: maxWidth), y: centerY - 22 * unit + rise, font: titleFont,
                         color: NSColor.white.withAlphaComponent(appear))
            if let artist = cue.next {
                drawCentered(fit(artist, font: artistFont, width: maxWidth), y: centerY + 30 * unit + rise, font: artistFont,
                             color: NSColor.white.withAlphaComponent(0.72 * appear))
            }
            return
        }
        if let cue = state.cue, let recap = cue.recap {
            let appear = min(1, state.cueAge / 0.5)
            let font = NSFont.systemFont(ofSize: 46 * unit, weight: .heavy)
            let glyph = PixelGlyph.large(recap.reaction)
            let textWidth = (recap.headline as NSString).size(withAttributes: [.font: font]).width
            let pixel = (4.5 * unit).rounded()
            let glyphW = CGFloat(glyph.width) * pixel, glyphH = CGFloat(glyph.height) * pixel
            let glyphY = centerY - glyphH / 2 - state.hop * 6 * unit
            drawGlyph(glyph, x: (box.width - textWidth) / 2 - glyphW - 20 * unit, y: glyphY, pixel: pixel, alpha: appear)
            drawGlyph(glyph, x: (box.width + textWidth) / 2 + 20 * unit, y: glyphY, pixel: pixel, alpha: appear)
            drawCentered(recap.headline, y: centerY - font.pointSize * 0.62, font: font, color: NSColor.white.withAlphaComponent(appear))
            drawCentered(recap.caption, y: centerY + font.pointSize * 0.62, font: NSFont.systemFont(ofSize: 16 * unit, weight: .semibold),
                         color: NSColor.white.withAlphaComponent(0.7 * appear))
            return
        }
        if state.idle {
            drawCentered("음악을 틀면 무대가 시작돼요", y: box.height * 0.83, font: NSFont.systemFont(ofSize: 20 * unit, weight: .bold),
                         color: NSColor.white.withAlphaComponent(0.85))
            drawCentered("Claude FM 을 재생하거나 다른 앱에서 노래를 틀어 보세요", y: box.height * 0.83 + 30 * unit,
                         font: NSFont.systemFont(ofSize: 13 * unit, weight: .medium), color: NSColor.white.withAlphaComponent(0.55))
        }
    }

    // MARK: - 가사

    private func drawLyrics() {
        guard let cue = state.cue, !cue.isTitle, cue.recap == nil else { return }
        let bottom = box.height - 34 * unit
        let lyricFont = NSFont.systemFont(ofSize: 40 * unit, weight: .heavy)
        let nextFont = NSFont.systemFont(ofSize: 21 * unit, weight: .semibold)
        let originalFont = NSFont.systemFont(ofSize: 14 * unit, weight: .medium)
        let maxWidth = box.width * 0.86

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
        // 채움은 글자 수로 센다. 줄마다 맡은 글자 몫을 그 줄의 폭으로 바꿔, 말풍선·팝오버와 같은 자리를 채운다.
        let letters = lines.map { line in line.reduce(0) { $0 + ($1.isLetter || $1.isNumber ? 1 : 0) } }
        let totalLetters = letters.reduce(0, +)
        var lettersBefore = 0
        let shadow = textShadow(blur: 10 * unit)
        for (index, line) in lines.enumerated() {
            let width = widths[index]
            let x = (box.width - width) / 2
            let y = top + CGFloat(index) * lineHeight
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: baseColor, .shadow: shadow]
            (line as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            var take = 0.0
            if let progress, totalLetters > 0, letters[index] > 0 {
                let target = progress * Double(totalLetters) - Double(lettersBefore)
                let lineProgress = min(1, max(0, target / Double(letters[index])))
                take = KaraokeText.sungWidth(line, progress: lineProgress) { prefix in
                    Double((prefix as NSString).size(withAttributes: [.font: font]).width)
                }
            }
            lettersBefore += letters[index]
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
            let x = box.width / 2 + (CGFloat(index) - CGFloat(total - 1) / 2) * spacing
            let rect = NSRect(x: x - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            state.palette.accent.nsColor(alpha: 0.95).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    /// 맨 아래 가는 막대로 곡이 얼마나 흘렀는지 보여 준다.
    private func drawProgress() {
        guard let progress = state.songProgress else { return }
        let height = max(2, 3 * unit)
        let track = NSRect(x: 0, y: box.height - height, width: box.width, height: height)
        NSColor.white.withAlphaComponent(0.12).setFill()
        track.fill()
        state.palette.primary.nsColor(alpha: 0.9).setFill()
        NSRect(x: 0, y: track.minY, width: box.width * CGFloat(progress), height: height).fill()
        guard state.hint > 0.01, !state.songTime.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11 * unit, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6 * state.hint),
        ]
        (state.songTime as NSString).draw(at: NSPoint(x: 18 * unit, y: box.height - height - 22 * unit), withAttributes: attrs)
    }

    // MARK: - 안내

    private func drawHint() {
        guard state.hint > 0.01 else { return }
        let font = NSFont.systemFont(ofSize: 11 * unit, weight: .medium)
        let text = "클릭·스페이스 폭죽  ·  더블클릭 전체 화면  ·  ← → 가사 싱크  ·  P 재생  ·  T TV 로 보내기  ·  ⌘C 무대 사진  ·  esc 닫기"
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.6 * state.hint)]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: box.width - size.width - 18 * unit, y: box.height - size.height - 10 * unit),
                                withAttributes: attrs)
    }

    private func drawToast() {
        if state.needsPermission, state.toastLevel <= 0.01 {
            let text = "시스템 오디오 녹음을 허용하면 무대가 음악에 맞춰 춤춰요"
            let font = NSFont.systemFont(ofSize: 12 * unit, weight: .semibold)
            let size = pillSize(text, font: font)
            drawPill(text, at: NSPoint(x: (box.width - size.width) / 2, y: 24 * unit), font: font,
                     fill: NSColor.black.withAlphaComponent(0.5), text: NSColor.white.withAlphaComponent(0.85))
            return
        }
        guard state.toastLevel > 0.01, !state.toast.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 13 * unit, weight: .bold)
        let size = pillSize(state.toast, font: font)
        drawPill(state.toast, at: NSPoint(x: (box.width - size.width) / 2, y: 24 * unit), font: font,
                 fill: NSColor.black.withAlphaComponent(0.55 * state.toastLevel),
                 text: NSColor.white.withAlphaComponent(state.toastLevel))
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
        (text as NSString).draw(at: NSPoint(x: (box.width - size.width) / 2, y: y), withAttributes: attrs)
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
