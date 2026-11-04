import AppKit

/// 후렴이 터질 때 메뉴바 Clawd 아래로 쏟아지는 폭죽. 클릭을 받지 않고 잠깐 떴다가 사라진다.
@MainActor
final class CelebrationOverlay {
    private static let size = NSSize(width: 460, height: 420)
    /// 같은 곡에서 너무 자주 터지지 않게 쉬는 시간.
    private static let cooldown: TimeInterval = 24
    private let panel: NSPanel
    private let view = ConfettiView()
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var lastBurst: TimeInterval = -1_000

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
    }

    /// 아이콘 바로 아래에서 터뜨린다. 쉬는 시간 안이면 건너뛴다.
    func burst(at anchor: NSRect, screen: NSScreen, mood: MusicMood, reaction: LyricReaction?, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        // '동작 줄이기'를 켰으면 메뉴바 아래로 쏟아지는 폭죽은 쉰다.
        guard force || !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard force || now - lastBurst >= Self.cooldown else { return }
        lastBurst = now
        var frame = NSRect(
            x: (anchor.midX - Self.size.width / 2).rounded(),
            y: (anchor.minY - Self.size.height).rounded(),
            width: Self.size.width,
            height: Self.size.height
        )
        let visible = screen.frame
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        panel.setFrame(frame, display: false)
        view.burst = ConfettiBurst(
            originX: Double(anchor.midX - frame.minX),
            originY: 2,
            scale: 1,
            count: 64,
            seed: Int(now * 1000) % 100_000,
            colors: MoodPalette.of(mood == .quiet ? .groove : mood).confetti,
            glyph: reaction,
            upward: false
        )
        view.age = 0
        startedAt = now
        panel.orderFrontRegardless()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let age = ProcessInfo.processInfo.systemUptime - startedAt
        guard age < ConfettiBurst.lifetime else {
            timer?.invalidate()
            timer = nil
            view.burst = nil
            panel.orderOut(nil)
            return
        }
        view.age = age
    }
}

/// 폭죽 조각을 그린다. 종이는 뒤집히며 폭이 줄었다 늘었다 하고, 반응 그림은 픽셀로 찍는다.
@MainActor
final class ConfettiView: NSView {
    var burst: ConfettiBurst? {
        didSet { needsDisplay = true }
    }
    var age: Double = 0 {
        didSet { if age != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let burst else { return }
        for piece in burst.pieces(at: age) {
            if let glyph = piece.glyph {
                let pixel: CGFloat = 2
                for dot in PixelGlyph.reaction(glyph).pixels {
                    dot.color.nsColor(alpha: CGFloat(piece.alpha)).setFill()
                    NSRect(x: CGFloat(piece.x) + CGFloat(dot.x) * pixel - 5, y: CGFloat(piece.y) + CGFloat(dot.y) * pixel - 5,
                           width: pixel, height: pixel).fill()
                }
                continue
            }
            let side = CGFloat(piece.size) * 2
            let width = max(1, side * CGFloat(piece.face))
            piece.color.nsColor(alpha: CGFloat(piece.alpha)).setFill()
            NSRect(x: CGFloat(piece.x) - width / 2, y: CGFloat(piece.y) - side / 2, width: width, height: side).fill()
        }
    }
}
