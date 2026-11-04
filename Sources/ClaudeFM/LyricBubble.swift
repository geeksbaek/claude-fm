import AppKit

/// 말풍선이 그릴 것을 고르는 설정.
struct BubbleStyle: Equatable {
    /// 부른 만큼 글자를 코랄로 채운다.
    var karaoke = true
    /// 가사 반응 스티커와 후렴 강조.
    var reactions = true
    /// 간주 끝 카운트다운을 박에 맞출 박 간격(초).
    var beatPeriod: Double?
    /// 필링 효과. 끄면 글자와 말풍선이 소리에 맞춰 움직이지 않는다.
    var feeling = true
}

/// 메뉴바 아이콘 아래에 붙는, 클릭을 받지 않는 가사 말풍선.
@MainActor
final class LyricBubble {
    private static let behavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    private static let transitionDuration: TimeInterval = 0.34
    private let panel: NSPanel
    private let view = BubbleView()
    private var currentCue: LyricCue?
    private var transitionTimer: Timer?
    private var animationTimer: Timer?
    private var transitionStart: TimeInterval = 0
    private var startFrame: NSRect = .zero
    private var targetFrame: NSRect = .zero
    private var targetAnchorMidX: CGFloat = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = Self.behavior
        panel.isReleasedWhenClosed = false
        panel.contentView = view
    }

    func show(
        _ cue: LyricCue,
        clock: PlaybackClock? = nil,
        style: BubbleStyle = BubbleStyle(),
        feeling: VocalFeeling = .calm,
        feelingEnabled: Bool = true,
        anchor: NSRect,
        screen: NSScreen
    ) {
        let effective = feelingEnabled ? BubbleView.combinedFeeling(for: cue.current, audio: feeling) : .calm
        let layout = BubbleView.layout(for: cue)
        let nextFrame = computeFrame(size: layout.size, anchor: anchor, screen: screen)
        let lineChanged = (currentCue.map { !$0.isSameLine(as: cue) } ?? false)
            && panel.isVisible
            && (!view.text.isEmpty || view.isInterlude || view.isHumming)
        currentCue = cue
        view.feeling = effective
        view.clock = clock
        view.style = style
        targetFrame = nextFrame
        targetAnchorMidX = anchor.midX

        if lineChanged {
            view.outgoingText = view.text
            view.outgoingIsInterlude = view.isInterlude
            view.outgoingIsHumming = view.isHumming
            view.outgoingNextText = view.nextText
            view.outgoingCue = view.cue
            view.cue = cue
            view.isInterlude = cue.isInterlude
            view.isHumming = cue.isHumming
            view.text = layout.current
            view.nextText = layout.next
            view.transitionProgress = 0
            view.cueShownAt = ProcessInfo.processInfo.systemUptime
            startFrame = panel.frame
            transitionStart = ProcessInfo.processInfo.systemUptime
            startTransitionTimer()
        } else {
            if view.cue == nil || !(view.cue?.isSameLine(as: cue) ?? false) {
                view.cueShownAt = ProcessInfo.processInfo.systemUptime
            }
            view.cue = cue
            view.isInterlude = cue.isInterlude
            view.isHumming = cue.isHumming
            view.text = layout.current
            view.nextText = layout.next
            if transitionTimer == nil {
                view.outgoingText = ""
                view.outgoingIsInterlude = false
                view.outgoingIsHumming = false
                view.outgoingNextText = nil
                view.outgoingCue = nil
                view.transitionProgress = 1
                applyFrame(nextFrame, anchorMidX: anchor.midX)
            }
        }

        if panel.collectionBehavior != Self.behavior {
            panel.collectionBehavior = Self.behavior
        }
        if !panel.isVisible || !panel.isOnActiveSpace {
            panel.orderFrontRegardless()
        }
        syncAnimationTimer()
    }

    private func startTransitionTimer() {
        transitionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepTransition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    /// 간주 음표, 노래방 채움, 카운트다운, 반응 스티커처럼 시간에 따라 움직이는 것이 있으면 다시 그린다.
    private func syncAnimationTimer() {
        if panel.isVisible && view.needsAnimation {
            if animationTimer == nil {
                view.noteTime = ProcessInfo.processInfo.systemUptime
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.view.noteTime = ProcessInfo.processInfo.systemUptime
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                animationTimer = timer
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func stepTransition() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - transitionStart
        let rawT = min(1.0, max(0.0, elapsed / Self.transitionDuration))
        let eased = CGFloat(1.0 - pow(1.0 - rawT, 3.0))
        view.noteTime = now
        view.transitionProgress = eased
        let interpFrame = NSRect(
            x: (startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * eased).rounded(),
            y: (startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * eased).rounded(),
            width: (startFrame.width + (targetFrame.width - startFrame.width) * eased).rounded(),
            height: (startFrame.height + (targetFrame.height - startFrame.height) * eased).rounded()
        )
        applyFrame(interpFrame, anchorMidX: targetAnchorMidX)
        if rawT >= 1.0 {
            transitionTimer?.invalidate()
            transitionTimer = nil
            view.outgoingText = ""
            view.outgoingIsInterlude = false
            view.outgoingIsHumming = false
            view.outgoingNextText = nil
            view.outgoingCue = nil
            view.transitionProgress = 1.0
            applyFrame(targetFrame, anchorMidX: targetAnchorMidX)
            syncAnimationTimer()
        }
    }

    private func computeFrame(size: NSSize, anchor: NSRect, screen: NSScreen) -> NSRect {
        let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, 24)
        let menuBottom = screen.frame.maxY - menuHeight
        let topEdge = (anchor.minY > screen.frame.minY && anchor.minY <= screen.frame.maxY)
            ? min(anchor.minY, menuBottom + 4)
            : menuBottom + 4
        var frame = NSRect(
            x: (anchor.midX - size.width / 2).rounded(),
            y: (topEdge - 4 - size.height).rounded(),
            width: size.width,
            height: size.height
        )
        let visible = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > topEdge - 2 { frame.origin.y = topEdge - 2 - frame.height }
        return frame
    }

    private func applyFrame(_ frame: NSRect, anchorMidX: CGFloat) {
        view.tailX = min(max(anchorMidX - frame.minX, 22), frame.width - 22)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        } else {
            view.needsDisplay = true
        }
    }

    func updateFeeling(_ feeling: VocalFeeling, enabled: Bool = true) {
        guard panel.isVisible else { return }
        view.style.feeling = enabled
        view.feeling = enabled ? BubbleView.combinedFeeling(for: view.text, audio: feeling) : .calm
    }

    func orderFrontIfVisible() {
        guard panel.isVisible else { return }
        panel.collectionBehavior = Self.behavior
        panel.orderFrontRegardless()
    }

    func hide() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
        currentCue = nil
        view.text = ""
        view.nextText = nil
        view.outgoingText = ""
        view.isInterlude = false
        view.outgoingIsInterlude = false
        view.isHumming = false
        view.outgoingIsHumming = false
        view.outgoingNextText = nil
        view.cue = nil
        view.outgoingCue = nil
        view.clock = nil
        view.transitionProgress = 1.0
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

/// 말풍선 그림. 미리보기 도구도 이 뷰를 그대로 그린다.
@MainActor
final class BubbleView: NSView {
    static let outerPad: CGFloat = 6
    static let tail: CGFloat = 8
    static let padX: CGFloat = 13
    static let padY: CGFloat = 7
    static let singleLineLimit: CGFloat = 230
    static let maxTextWidth: CGFloat = 320
    static let interludeWidth: CGFloat = 132
    static let hummingWidth: CGFloat = 114
    /// 제목 카드 앞 음표 자리.
    static let titleNoteWidth: CGFloat = 18
    /// 곡 기록 양옆 픽셀 그림 자리.
    static let recapGlyphWidth: CGFloat = 18

    var text = "" {
        didSet { if text != oldValue { needsDisplay = true } }
    }
    var nextText: String? {
        didSet { if nextText != oldValue { needsDisplay = true } }
    }
    var outgoingText = "" {
        didSet { if outgoingText != oldValue { needsDisplay = true } }
    }
    var isInterlude = false {
        didSet { if isInterlude != oldValue { needsDisplay = true } }
    }
    var outgoingIsInterlude = false {
        didSet { if outgoingIsInterlude != oldValue { needsDisplay = true } }
    }
    var isHumming = false {
        didSet { if isHumming != oldValue { needsDisplay = true } }
    }
    var outgoingIsHumming = false {
        didSet { if outgoingIsHumming != oldValue { needsDisplay = true } }
    }
    var outgoingNextText: String? {
        didSet { if outgoingNextText != oldValue { needsDisplay = true } }
    }
    var noteTime: TimeInterval = 0 {
        didSet { if noteTime != oldValue { needsDisplay = true } }
    }
    var transitionProgress: CGFloat = 1.0 {
        didSet { if transitionProgress != oldValue { needsDisplay = true } }
    }
    var tailX: CGFloat = 40 {
        didSet { if tailX != oldValue { needsDisplay = true } }
    }
    var feeling = VocalFeeling.calm {
        didSet { if feeling != oldValue { needsDisplay = true } }
    }
    /// 지금 줄의 시각·반응·후렴 정보.
    var cue: LyricCue? {
        didSet { if cue != oldValue { needsDisplay = true } }
    }
    /// 위로 사라지는 이전 줄의 정보. 다 부른 줄은 채운 색으로 떠난다.
    var outgoingCue: LyricCue?
    var clock: PlaybackClock? {
        didSet { if clock != oldValue { needsDisplay = true } }
    }
    var style = BubbleStyle() {
        didSet { if style != oldValue { needsDisplay = true } }
    }
    /// 지금 줄이 처음 보인 시각. 반응 스티커가 톡 튀어나오는 데 쓴다.
    var cueShownAt: TimeInterval = 0
    /// 미리보기에서 시각을 고정해 그릴 때 쓴다. 0 이면 지금 시각.
    var frozenTime: TimeInterval = 0
    /// 간주 음표가 흘러간 거리. 소리 세기에 따라 빠르기가 바뀌어도 자리가 튀지 않게 쌓아 간다.
    private var noteFlow = FlowClock()

    override var isFlipped: Bool { true }

    /// 시간에 따라 다시 그려야 하는 요소가 있는지.
    var needsAnimation: Bool {
        if isInterlude || outgoingIsInterlude || isHumming || outgoingIsHumming { return true }
        guard let cue else { return false }
        if style.karaoke, clock != nil, cue.start != nil, cue.end != nil { return true }
        if style.reactions, cue.reaction != nil || cue.isHook { return true }
        return cue.recap != nil
    }

    private var now: TimeInterval {
        frozenTime > 0 ? frozenTime : ProcessInfo.processInfo.systemUptime
    }

    /// 가사 문장부호(`!`, `...`)와 실시간 오디오 파장(`VocalFeeling`)을 합쳐 말풍선 표현 강도를 정한다.
    static func combinedFeeling(for text: String, audio: VocalFeeling) -> VocalFeeling {
        var out = audio
        let exclamations = text.filter { $0 == "!" || $0 == "！" }.count
        let hasEllipsis = text.contains("...") || text.contains("…") || text.contains("..")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isParen = (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
            || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）"))

        if exclamations >= 2 {
            out.shout = max(out.shout, 0.78)
            out.wave = max(out.wave, 0.55)
            out.whisper = 0
        } else if exclamations == 1 {
            out.shout = min(1.0, max(out.shout, 0.42) + audio.wave * 0.25)
            out.whisper = min(out.whisper, 0.1)
        } else if (hasEllipsis || isParen) && out.shout < 0.28 {
            out.whisper = max(out.whisper, hasEllipsis ? 0.68 : 0.48)
        }
        if out.phase == 0 {
            out.phase = ProcessInfo.processInfo.systemUptime
        }
        return out
    }

    /// 현재 가사와 다음 가사 미리보기의 줄바꿈·크기를 계산한다.
    static func layout(for cue: LyricCue) -> (current: String, next: String?, size: NSSize) {
        let (mainFormatted, mainTextSize): (String, NSSize)
        let lineHeight = ceil(measureFont.ascender - measureFont.descender + measureFont.leading)
        if cue.isHumming {
            mainFormatted = cue.current
            mainTextSize = NSSize(width: hummingWidth, height: lineHeight)
        } else if cue.isInterlude {
            mainFormatted = cue.current
            mainTextSize = NSSize(width: interludeWidth, height: lineHeight)
        } else if cue.isTitle {
            let title = trimSingleLine(cue.current, font: measureFont, limit: maxTextWidth - titleNoteWidth)
            mainFormatted = title
            mainTextSize = NSSize(width: max(lineWidth(title) + 8 + titleNoteWidth, 60), height: lineHeight)
        } else if cue.recap != nil {
            mainFormatted = cue.current
            mainTextSize = NSSize(width: lineWidth(cue.current) + 8 + recapGlyphWidth * 2, height: lineHeight)
        } else {
            (mainFormatted, mainTextSize) = layoutMain(for: cue.current)
        }
        let cleanNext = cue.next?.split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
        guard !cleanNext.isEmpty else {
            return (
                mainFormatted,
                nil,
                NSSize(
                    width: mainTextSize.width + padX * 2 + outerPad * 2,
                    height: tail + padY * 2 + mainTextSize.height + outerPad * 2 + 2
                )
            )
        }
        let nextFormatted = trimPreview(cleanNext)
        let nextLineHeight = ceil(previewFont.ascender - previewFont.descender + previewFont.leading)
        let nextWidth = min(maxTextWidth, ceil((nextFormatted as NSString).size(withAttributes: [.font: previewFont]).width) + 6)
        let contentWidth = max(mainTextSize.width, nextWidth)
        let contentHeight = mainTextSize.height + previewGap + nextLineHeight
        return (
            mainFormatted,
            nextFormatted,
            NSSize(
                width: contentWidth + padX * 2 + outerPad * 2,
                height: tail + padY * 2 + contentHeight + outerPad * 2 + 3
            )
        )
    }

    private static func layoutMain(for raw: String) -> (text: String, textSize: NSSize) {
        let clean = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let lineHeight = ceil(measureFont.ascender - measureFont.descender + measureFont.leading)
        let singleWidth = lineWidth(clean)
        if singleWidth <= singleLineLimit {
            let width = max(ceil(singleWidth) + 8, 28)
            return (clean, NSSize(width: width, height: lineHeight))
        }
        let (first, second) = splitBalanced(clean)
        let twoLine = first + "\n" + second
        let width = min(maxTextWidth, max(ceil(max(lineWidth(first), lineWidth(second))) + 8, 28))
        return (twoLine, NSSize(width: width, height: lineHeight * 2))
    }

    private static func trimPreview(_ raw: String) -> String {
        if ceil((raw as NSString).size(withAttributes: [.font: previewFont]).width) <= maxTextWidth {
            return raw
        }
        var words = raw.split(separator: " ").map(String.init)
        while words.count > 2 {
            words.removeLast()
            let candidate = words.joined(separator: " ") + "…"
            if ceil((candidate as NSString).size(withAttributes: [.font: previewFont]).width) <= maxTextWidth {
                return candidate
            }
        }
        return raw
    }

    /// 한 줄에 들어가도록 글자 단위로 줄이고 말줄임표를 붙인다.
    private static func trimSingleLine(_ raw: String, font: NSFont, limit: CGFloat) -> String {
        let clean = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        guard width(clean) > limit else { return clean }
        var chars = Array(clean)
        while chars.count > 1 {
            chars.removeLast()
            let candidate = String(chars).trimmingCharacters(in: .whitespaces) + "…"
            if width(candidate) <= limit { return candidate }
        }
        return clean
    }

    private static func lineWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: measureFont]).width)
    }

    private static func splitBalanced(_ text: String) -> (String, String) {
        let words = trimToTwoLines(text.split(separator: " ").map(String.init))
        guard words.count >= 2 else {
            let chars = Array(text)
            let mid = max(1, chars.count / 2)
            return (String(chars[..<mid]), String(chars[mid...]))
        }
        let trailingBreaks: Set<Character> = [",", "!", "?", ")", "）", "]", "］", "~"]
        let leadingBreaks: Set<Character> = ["(", "（", "[", "［"]
        var bestIndex = words.count / 2
        var bestCost = CGFloat.greatestFiniteMagnitude
        for index in 1..<words.count {
            let left = words[..<index].joined(separator: " ")
            let right = words[index...].joined(separator: " ")
            let w1 = lineWidth(left)
            let w2 = lineWidth(right)
            let overflow = max(0, w1 - maxTextWidth) + max(0, w2 - maxTextWidth)
            var cost = abs(w1 - w2) + overflow * 12
            let openCount = left.filter { $0 == "(" || $0 == "（" }.count
            let closeCount = left.filter { $0 == ")" || $0 == "）" }.count
            if openCount > closeCount { cost += 240 }
            if let last = left.last, trailingBreaks.contains(last) { cost -= 28 }
            if let first = right.first, leadingBreaks.contains(first) { cost -= 28 }
            if cost < bestCost {
                bestCost = cost
                bestIndex = index
            }
        }
        return (words[..<bestIndex].joined(separator: " "), words[bestIndex...].joined(separator: " "))
    }

    private static func trimToTwoLines(_ words: [String]) -> [String] {
        var kept = words
        while kept.count > 2, lineWidth(kept.joined(separator: " ")) > maxTextWidth * 2.0 {
            kept.removeLast()
        }
        return kept
    }

    /// 지금 곡 시각. 동기 가사가 아니면 nil.
    private var songElapsed: TimeInterval? {
        clock?.elapsed(at: now)
    }

    /// 노래방 채움 비율. 채우지 않으면 nil.
    private func sweep(for cue: LyricCue?) -> CGFloat? {
        guard style.karaoke, let cue, let elapsed = songElapsed, let progress = cue.progress(at: elapsed) else { return nil }
        return CGFloat(progress)
    }

    /// 미리보기 도구가 '동작 줄이기'와 상관없이 움직임을 그려 볼 때 쓴다.
    static var motionOverride: Bool?

    /// 필링 효과가 켜져 있고 '동작 줄이기'가 꺼져 있을 때만 움직인다. 색과 빛은 그대로 둔다.
    private var motionEnabled: Bool {
        style.feeling && (Self.motionOverride ?? !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// 지금 줄이 후렴이라 금빛으로 꾸미는지.
    private var hookActive: Bool {
        style.reactions && (cue?.isHook ?? false) && !isInterlude && !isHumming
    }

    override func draw(_ dirtyRect: NSRect) {
        let motion = motionEnabled
        let shout = CGFloat(feeling.shout)
        let whisper = CGFloat(feeling.whisper)
        let wave = CGFloat(feeling.wave)
        let pulse = CGFloat(feeling.beat)
        let beat = motion ? pulse : 0
        let bass = CGFloat(feeling.bass)
        let phase = feeling.phase
        let hook = hookActive

        // 외치면 말풍선이 살짝 떨리고(글자는 저마다 따로 떤다), 속삭이면 잔잔히 뜬다. 박은 말캉한 출렁임으로 받는다.
        let shakeAmp = motion && shout > 0.16 ? (shout - 0.16) * 1.1 : 0
        let jitterX = CGFloat(sin(phase * 43.0)) * shakeAmp
        let jitterY = CGFloat(cos(phase * 36.0)) * shakeAmp * 0.75
        let floatY = motion && whisper > 0.15 ? CGFloat(sin(phase * 2.6)) * whisper * 1.4 : 0
        let dx = jitterX
        let dy = jitterY + floatY

        if motion, let context = NSGraphicsContext.current?.cgContext {
            let squash = jellySquash()
            if squash != 0 {
                // 꼬리 끝을 붙잡고 눌렸다가 용수철처럼 튀어 오른다. 아이콘에서 떨어지지 않는다.
                let anchor = CGPoint(x: min(max(tailX, 0), bounds.width), y: Self.outerPad)
                context.translateBy(x: anchor.x, y: anchor.y)
                context.scaleBy(x: 1 + squash * 0.55, y: 1 - squash)
                context.translateBy(x: -anchor.x, y: -anchor.y)
            }
        }

        let path = bubblePath(dx: dx, dy: dy)
        if motion {
            drawSoundRing(path, hook: hook)
        }

        // 후렴은 따뜻한 금빛 후광이 박에 맞춰 숨 쉰다.
        if hook {
            NSGraphicsContext.saveGraphicsState()
            Self.hookGold.withAlphaComponent(0.26 + pulse * 0.22 + wave * 0.08).setStroke()
            path.lineWidth = 4.2 + pulse * 1.6
            path.lineJoinStyle = .round
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 외침이나 강한 베이스가 들어오면 말풍선 바깥에 은은한 파장 후광을 그린다.
        if shout > 0.15 || bass > 0.35 {
            NSGraphicsContext.saveGraphicsState()
            let glowColor = shout >= 0.2
                ? NSColor(srgbRed: 245 / 255, green: 84 / 255, blue: 52 / 255, alpha: min(0.52, shout * 0.45 + wave * 0.15))
                : Self.stroke.withAlphaComponent(min(0.32, bass * 0.28))
            glowColor.setStroke()
            path.lineWidth = 3.2 + shout * 2.6 + wave * 1.2
            path.lineJoinStyle = .round
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 배경 채우기 (속삭일 때는 살짝 반투명하고 아련하게, 외칠 때는 불빛이 감돌게)
        let bgAlpha: CGFloat = whisper > 0.2 ? max(0.82, 0.96 - whisper * 0.14) : 0.98
        NSColor.windowBackgroundColor.withAlphaComponent(bgAlpha).setFill()
        path.fill()
        if shout > 0.22 {
            NSColor(srgbRed: 255 / 255, green: 105 / 255, blue: 65 / 255, alpha: shout * 0.09).setFill()
            path.fill()
        }
        if hook {
            Self.hookGold.withAlphaComponent(0.07 + pulse * 0.05).setFill()
            path.fill()
        }

        // 테두리 선 (속삭일 때는 점선, 외칠 때는 굵고 강렬한 코랄 레드, 후렴은 코랄과 금빛 사이)
        NSGraphicsContext.saveGraphicsState()
        let borderColor: NSColor
        if shout > 0.2 {
            borderColor = NSColor(
                srgbRed: (217 + 35 * shout) / 255,
                green: (119 - 46 * shout) / 255,
                blue: (87 - 36 * shout) / 255,
                alpha: 1
            )
        } else if hook {
            borderColor = Self.stroke.blended(withFraction: 0.35 + pulse * 0.25, of: Self.hookGold) ?? Self.stroke
        } else if whisper > 0.2 {
            borderColor = Self.stroke.withAlphaComponent(max(0.45, 0.88 - whisper * 0.38))
        } else {
            borderColor = Self.stroke.withAlphaComponent(0.88 + wave * 0.12)
        }
        borderColor.setStroke()
        path.lineWidth = 1.45 + shout * 1.05 + wave * 0.35 - whisper * 0.35 + (hook ? 0.45 : 0)
        path.lineJoinStyle = .round
        if whisper > 0.25 && shout < 0.2 && !hook {
            let pattern: [CGFloat] = [4.0, 3.2]
            path.setLineDash(pattern, count: pattern.count, phase: CGFloat(phase * 6.0))
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 소리질러야 하는 부분에서는 말풍선 모서리에 실시간 파장 강조선(폭발선)을 그린다.
        if shout > 0.32 {
            drawShoutSparks(dx: dx, dy: dy, shout: shout, wave: wave, color: borderColor)
        }
        if hook {
            drawHookTwinkles(dx: dx, dy: dy, beat: pulse)
        }

        // 소리가 살아 있을 때 말풍선 아래 가운데에 지금 소리의 목소리 무늬를 그린다.
        if wave > 0.04 || shout > 0.2 {
            if feeling.bands.count == SpectrumMeter.bandCount {
                drawVoiceprint(dx: dx, dy: dy, bands: feeling.bands, whisper: whisper, color: borderColor)
            } else {
                drawWaveformBars(dx: dx, dy: dy, wave: wave, shout: shout, whisper: whisper, phase: phase, color: borderColor)
            }
        }

        // 가사 글자 그리기 (전환 중에는 이전 가사가 위로 사라지고, 다음 가사가 아래에서 위로 올라온다)
        NSGraphicsContext.saveGraphicsState()
        let clipRect = NSRect(
            x: Self.outerPad + 2 + dx,
            y: Self.outerPad + Self.tail + 2 + dy,
            width: max(0, bounds.width - (Self.outerPad + 2) * 2),
            height: max(0, bounds.height - Self.outerPad * 2 - Self.tail - 4)
        )
        NSBezierPath(roundedRect: clipRect, xRadius: 8, yRadius: 8).addClip()

        let activeFont = currentFont(shout: shout, whisper: whisper, wave: wave)
        let lineCount = text.contains("\n") ? 2 : 1
        let lineHeight = ceil(activeFont.ascender - activeFont.descender + activeFont.leading)
        let mainBlockHeight = lineHeight * CGFloat(lineCount)
        let nextLineHeight = ceil(Self.previewFont.ascender - Self.previewFont.descender + Self.previewFont.leading)
        let hasNext = (nextText?.isEmpty == false)
        let totalContentHeight = mainBlockHeight + (hasNext ? Self.previewGap + nextLineHeight : 0)

        let bubbleTop = Self.outerPad + Self.tail + dy
        let bubbleBottom = bounds.height - Self.outerPad + dy
        let mainY = bubbleTop + max(Self.padY - 1, (bubbleBottom - bubbleTop - totalContentHeight) / 2 - (wave > 0.04 ? 1.0 : 0))
        let nextY = mainY + mainBlockHeight + Self.previewGap
        let contentX = Self.outerPad + Self.padX + dx
        let contentWidth = bounds.width - (Self.outerPad + Self.padX) * 2

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let previewStyle = NSMutableParagraphStyle()
        previewStyle.alignment = .center
        previewStyle.lineBreakMode = .byTruncatingTail

        let baseAlpha: CGFloat = whisper > 0.2 ? max(0.66, 1.0 - whisper * 0.32) : 1.0
        let previewAlpha: CGFloat = 0.46
        let p = min(1.0, max(0.0, transitionProgress))
        let animTime = noteTime > 0 ? noteTime : (phase > 0 ? phase : now)
        let countdown = countdownState()

        if p < 1.0, (!outgoingText.isEmpty || outgoingIsInterlude || outgoingIsHumming) {
            let travelUp = max(mainBlockHeight + Self.previewGap, 18)
            let samePreview = (outgoingNextText != nil && outgoingNextText == nextText && !(nextText ?? "").isEmpty)

            // 1) 이전 현재 가사(또는 이전 간주·흥얼거림): 위로 올라가며 말풍선 상단으로 사라진다.
            let outLines = (outgoingIsInterlude || outgoingIsHumming) ? 1 : (outgoingText.contains("\n") ? 2 : 1)
            let outHeight = lineHeight * CGFloat(outLines)
            let outAlpha = max(0, (1.0 - p) * (1.0 - p)) * baseAlpha
            let outRect = NSRect(
                x: contentX,
                y: mainY - p * travelUp,
                width: contentWidth,
                height: outHeight + 4
            )
            if outgoingIsHumming {
                drawHumming(in: outRect, alpha: outAlpha, time: animTime, wave: wave, beat: beat, shout: shout, whisper: whisper)
            } else if outgoingIsInterlude {
                drawInterludeNotes(in: outRect, alpha: outAlpha, time: animTime, wave: wave, beat: beat)
            } else {
                let outAttrs: [NSAttributedString.Key: Any] = [
                    .font: activeFont,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(outAlpha),
                    .paragraphStyle: paragraph,
                ]
                (outgoingText as NSString).draw(with: outRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: outAttrs)
                // 다 부르고 떠나는 줄은 채운 색 그대로 올라간다.
                if style.karaoke, clock != nil, let outgoingCue, outgoingCue.start != nil, outgoingCue.end != nil {
                    drawSung(outgoingText, in: outRect, attributes: outAttrs, font: activeFont, progress: 1,
                             color: Self.sungColor.withAlphaComponent(outAlpha))
                }
            }

            // 2) 새 현재 가사(또는 간주 음표·흥얼거림): 아래에서 현재 가사 자리로 올라오며 선명해진다.
            if isHumming {
                let risingAlpha = (previewAlpha + (baseAlpha - previewAlpha) * p) * baseAlpha
                let risingY = (mainY + travelUp) * (1.0 - p) + mainY * p
                let risingRect = NSRect(
                    x: contentX,
                    y: risingY,
                    width: contentWidth,
                    height: mainBlockHeight + 4
                )
                drawHumming(in: risingRect, alpha: risingAlpha, time: animTime, wave: wave, beat: beat, shout: shout, whisper: whisper)
            } else if isInterlude {
                let risingAlpha = (samePreview ? p : (previewAlpha + (baseAlpha - previewAlpha) * p)) * baseAlpha
                let risingY = samePreview ? (mainY + (1.0 - p) * 10.0) : ((mainY + travelUp) * (1.0 - p) + mainY * p)
                let risingRect = NSRect(
                    x: contentX,
                    y: risingY,
                    width: contentWidth,
                    height: mainBlockHeight + 4
                )
                drawInterludeNotes(in: risingRect, alpha: risingAlpha * (1 - countdown.notesFade), time: animTime, wave: wave, beat: beat)
            } else {
                let risingSize = Self.previewFont.pointSize + (activeFont.pointSize - Self.previewFont.pointSize) * p
                let risingFont = p < 0.45
                    ? NSFont.systemFont(ofSize: risingSize, weight: .regular)
                    : NSFont.systemFont(ofSize: risingSize, weight: shout > 0.3 || cue?.isTitle == true ? .bold : .medium)
                let risingAlpha = previewAlpha + (baseAlpha - previewAlpha) * p
                let risingY = (mainY + travelUp) * (1.0 - p) + mainY * p
                let risingRect = NSRect(
                    x: contentX,
                    y: risingY,
                    width: contentWidth,
                    height: mainBlockHeight + 4
                )
                var risingAttrs: [NSAttributedString.Key: Any] = [
                    .font: risingFont,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(risingAlpha),
                    .paragraphStyle: paragraph,
                ]
                if whisper > 0.25 {
                    risingAttrs[.kern] = 0.45 * whisper * p
                }
                drawMainText(in: risingRect, attributes: risingAttrs, font: risingFont, alpha: risingAlpha, beat: beat)
            }

            // 3) 새 다음 가사 미리보기: 이미 떠 있던 다음 가사는 자리를 유지하고, 새 다음 가사는 아래에서 올라온다.
            if let nextText, !nextText.isEmpty {
                let incomingAlpha = samePreview ? previewAlpha : (max(0, (p - 0.12) / 0.88) * previewAlpha)
                let incomingY = samePreview ? nextY : (nextY + (1.0 - p) * (nextLineHeight + 7))
                let nextRect = NSRect(
                    x: contentX,
                    y: incomingY,
                    width: contentWidth,
                    height: nextLineHeight + 2
                )
                let nextAttrs: [NSAttributedString.Key: Any] = [
                    .font: Self.previewFont,
                    .foregroundColor: previewColor(alpha: incomingAlpha),
                    .paragraphStyle: previewStyle,
                ]
                (nextText as NSString).draw(with: nextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nextAttrs)
            }
        } else {
            let rect = NSRect(
                x: contentX,
                y: mainY,
                width: contentWidth,
                height: mainBlockHeight + 4
            )
            if isHumming {
                drawHumming(in: rect, alpha: baseAlpha, time: animTime, wave: wave, beat: beat, shout: shout, whisper: whisper)
            } else if isInterlude {
                drawInterludeNotes(in: rect, alpha: baseAlpha * (1 - countdown.notesFade), time: animTime, wave: wave, beat: beat)
                if countdown.dots > 0 || countdown.notesFade > 0 {
                    drawCountdownDots(countdown, in: rect, lineHeight: lineHeight, alpha: baseAlpha)
                }
            } else {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: activeFont,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(baseAlpha),
                    .paragraphStyle: paragraph,
                ]
                if whisper > 0.25 {
                    attributes[.kern] = 0.45 * whisper
                }
                if cue?.isTitle == true {
                    attributes[.font] = Self.titleFont
                }
                drawMainText(in: rect, attributes: attributes, font: (attributes[.font] as? NSFont) ?? activeFont,
                             alpha: baseAlpha, beat: beat)
            }

            if let nextText, !nextText.isEmpty {
                let nextRect = NSRect(
                    x: contentX,
                    y: nextY,
                    width: contentWidth,
                    height: nextLineHeight + 2
                )
                let nextAttrs: [NSAttributedString.Key: Any] = [
                    .font: Self.previewFont,
                    .foregroundColor: previewColor(alpha: previewAlpha),
                    .paragraphStyle: previewStyle,
                ]
                (nextText as NSString).draw(with: nextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nextAttrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // 반응 스티커는 말풍선 오른쪽 위 모서리에 붙어 박에 맞춰 통통 뛴다.
        if style.reactions, let reaction = cue?.reaction, cue?.recap == nil, !isInterlude, !isHumming {
            drawReactionSticker(reaction, dx: dx, dy: dy, beat: beat, entering: p)
        }
    }

    /// 제목 카드는 앞에 코랄 음표를, 곡 기록은 양옆에 픽셀 그림을 붙이고, 노래 줄은 부른 만큼 채운다.
    private func drawMainText(in rect: NSRect, attributes: [NSAttributedString.Key: Any], font: NSFont, alpha: CGFloat, beat: CGFloat) {
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        if cue?.isTitle == true {
            let noteFont = NSFont.systemFont(ofSize: font.pointSize + 1, weight: .bold)
            let note = "♪" as NSString
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: noteFont,
                .foregroundColor: Self.stroke.withAlphaComponent(alpha),
            ]
            let total = width + Self.titleNoteWidth
            let startX = rect.minX + max(0, (rect.width - total) / 2)
            let noteSize = note.size(withAttributes: noteAttrs)
            note.draw(at: NSPoint(x: startX + (Self.titleNoteWidth - noteSize.width) / 2 - 2,
                                  y: rect.minY + (font.ascender - noteFont.ascender) - beat * 1.2),
                      withAttributes: noteAttrs)
            let textRect = NSRect(x: startX + Self.titleNoteWidth, y: rect.minY, width: width + 2, height: rect.height)
            var left = attributes
            let leftStyle = NSMutableParagraphStyle()
            leftStyle.alignment = .left
            leftStyle.lineBreakMode = .byTruncatingTail
            left[.paragraphStyle] = leftStyle
            (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: left)
            return
        }
        if let recap = cue?.recap {
            let glyph = PixelGlyph.reaction(recap.reaction)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let startX = rect.minX + (rect.width - width) / 2
            let glyphY = rect.minY + (lineHeight - 10) / 2 - beat * 1.5
            drawGlyph(glyph, x: startX - Self.recapGlyphWidth + 2, y: glyphY, pixel: 2, alpha: alpha)
            drawGlyph(glyph, x: startX + width + Self.recapGlyphWidth - 12, y: glyphY, pixel: 2, alpha: alpha)
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            return
        }
        drawSingingText(text, in: rect, attributes: attributes, font: font, alpha: alpha)
    }

    // MARK: - 노래하는 글자

    /// 글자 하나를 그릴 자리. 띄어쓰기와 문장부호는 노래방 글자 순서(`letter`)에 들지 않는다.
    private struct GlyphSlot {
        var font: CTFont
        var glyph: CGGlyph
        var x: CGFloat
        var baseline: CGFloat
        var width: CGFloat
        var letter: Int?
        /// 이 글자 앞에 나온 글자 수. 문장부호는 앞 글자를 다 부르면 같이 채운다.
        var lettersBefore: Int
    }

    /// 줄마다 가운데 맞춘 글자 자리를 Core Text 로 구한다. 한글처럼 대체 글꼴로 그리는 글자도 제 글꼴을 쓴다.
    private func glyphSlots(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any],
                            lineHeight: CGFloat) -> (slots: [GlyphSlot], letters: Int) {
        var slots: [GlyphSlot] = []
        var letters = 0
        for (row, lineText) in text.components(separatedBy: "\n").enumerated() {
            // UTF-16 자리마다 몇 번째 글자인지와 그 앞까지의 글자 수를 적어 둔다.
            var letterAt: [Int: Int] = [:]
            var beforeAt: [Int: Int] = [:]
            var offset = 0
            for char in lineText {
                let length = char.utf16.count
                let isLetter = char.isLetter || char.isNumber
                for unit in offset..<(offset + length) {
                    beforeAt[unit] = letters
                    if isLetter { letterAt[unit] = letters }
                }
                if isLetter { letters += 1 }
                offset += length
            }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: lineText, attributes: attributes))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let originX = rect.minX + max(0, (rect.width - width) / 2)
            let baseline = rect.minY + CGFloat(row) * lineHeight + ascent
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0, let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] else { continue }
                let runFont = value as! CTFont
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                let all = CFRange(location: 0, length: 0)
                CTRunGetGlyphs(run, all, &glyphs)
                CTRunGetPositions(run, all, &positions)
                CTRunGetAdvances(run, all, &advances)
                CTRunGetStringIndices(run, all, &indices)
                for index in 0..<count {
                    slots.append(GlyphSlot(font: runFont, glyph: glyphs[index], x: originX + positions[index].x,
                                           baseline: baseline, width: advances[index].width,
                                           letter: letterAt[indices[index]], lettersBefore: beforeAt[indices[index]] ?? 0))
                }
            }
        }
        return (slots, letters)
    }

    /// 노래 줄을 글자마다 그린다. 부른 글자 수만큼 코랄로 채우고, 필링 효과가 켜져 있으면
    /// 지금 부르는 글자가 톡 솟고, 박마다 물결이 글자 사이를 지나가고, 외칠 때는 글자마다 떨고,
    /// 속삭일 때는 숨 쉬듯 떠오른다. 후렴에는 금빛 반짝임이 글자 사이를 훑고 지나간다.
    private func drawSingingText(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any],
                                 font: NSFont, alpha: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            return
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let layout = glyphSlots(text, in: rect, attributes: attributes, lineHeight: lineHeight)
        guard !layout.slots.isEmpty else { return }
        let motion = motionEnabled
        let total = Double(layout.letters)
        let sung = sweep(for: cue).map { Double($0) * total }
        let time = noteTime > 0 ? noteTime : now
        let shout = CGFloat(feeling.shout)
        let whisper = CGFloat(feeling.whisper)
        let energy = CGFloat(min(1, feeling.wave * 0.8 + feeling.bass * 0.5))
        let ripple = motion && feeling.sinceBeat < 1 ? 2.1 * energy : 0
        let tremble = motion && shout > 0.25 ? (shout - 0.25) * 1.6 : 0
        let breath = motion && whisper > 0.15 ? whisper * 1.5 : 0
        let gold = (Self.shimmerGold.usingColorSpace(.sRGB) ?? Self.hookGold).withAlphaComponent(alpha)
        let unsung = (attributes[.foregroundColor] as? NSColor ?? NSColor.labelColor.withAlphaComponent(alpha))
        let unsungColor = unsung.usingColorSpace(.sRGB) ?? unsung
        let sungColor = (Self.sungColor.usingColorSpace(.sRGB) ?? Self.sungColor).withAlphaComponent(alpha)
        // 후렴에는 금빛 반짝임이 1.6초마다 왼쪽에서 오른쪽으로 지나간다.
        let shimmerX: CGFloat? = hookActive
            ? rect.minX - 24 + CGFloat(time.truncatingRemainder(dividingBy: 1.6) / 1.6) * (rect.width + 48)
            : nil
        let xHeight = font.xHeight

        context.saveGState()
        context.textMatrix = .identity
        if motion, shout > 0.3 {
            context.setShadow(offset: .zero, blur: 2 + 3 * shout,
                              color: NSColor(srgbRed: 1, green: 0.4, blue: 0.25, alpha: 0.5 * shout * alpha).cgColor)
        }
        for (index, slot) in layout.slots.enumerated() {
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            var scale: CGFloat = 1
            var angle: CGFloat = 0
            if ripple > 0 {
                let t = feeling.sinceBeat - Double(index) * 0.018
                if t > 0, t < 0.22 { dy -= CGFloat(sin(.pi * t / 0.22)) * ripple }
            }
            if tremble > 0 {
                let seed = Double(index)
                dx += CGFloat(sin(feeling.phase * 47 + seed * 2.17)) * tremble
                dy += CGFloat(cos(feeling.phase * 39 + seed * 1.31)) * tremble * 0.8
                angle = CGFloat(sin(feeling.phase * 23 + seed * 3.1)) * 0.06 * shout
            }
            if breath > 0 {
                dy += CGFloat(sin(time * 2.4 - Double(index) * 0.55)) * breath
            }
            var amount: CGFloat = 0
            if let sung {
                if let letter = slot.letter {
                    amount = CGFloat(min(1, max(0, sung - Double(letter))))
                    if motion, sung < total {
                        let near = max(0, 1 - abs(sung - (Double(letter) + 0.5)) / 0.9)
                        scale += CGFloat(near) * 0.14
                        dy -= CGFloat(near) * 1.6
                    }
                } else if slot.lettersBefore > 0, sung >= Double(slot.lettersBefore) {
                    amount = 1
                }
            }
            var base = unsungColor
            var lit = sungColor
            if let shimmerX {
                let glow = max(0, 1 - abs(slot.x + slot.width / 2 - shimmerX) / 16)
                if glow > 0 {
                    base = base.blended(withFraction: glow * 0.7, of: gold) ?? base
                    lit = lit.blended(withFraction: glow * 0.65, of: gold) ?? lit
                }
            }
            let pivot = CGPoint(x: slot.x + slot.width / 2, y: slot.baseline - xHeight / 2)
            context.saveGState()
            context.translateBy(x: pivot.x + dx, y: pivot.y + dy)
            if angle != 0 { context.rotate(by: angle) }
            if scale != 1 { context.scaleBy(x: scale, y: scale) }
            context.translateBy(x: slot.x - pivot.x, y: slot.baseline - pivot.y)
            // 여기서부터는 글자 기준선 위가 +y 다.
            context.scaleBy(x: 1, y: -1)
            var glyph = slot.glyph
            var origin = CGPoint.zero
            if amount < 1 {
                context.setFillColor(base.cgColor)
                CTFontDrawGlyphs(slot.font, &glyph, &origin, 1, context)
            }
            if amount > 0 {
                if amount < 1 {
                    context.saveGState()
                    context.clip(to: CGRect(x: -1, y: -lineHeight * 0.6, width: slot.width * amount + 1, height: lineHeight * 1.8))
                }
                context.setFillColor(lit.cgColor)
                CTFontDrawGlyphs(slot.font, &glyph, &origin, 1, context)
                if amount < 1 { context.restoreGState() }
            }
            context.restoreGState()
        }
        context.restoreGState()
        if motion, let last = layout.slots.last {
            drawHeldNote(after: last, xHeight: xHeight, alpha: alpha)
        }
    }

    /// 마지막 음절을 길게 끄는 동안 그 뒤로 작은 떨림 물결이 이어진다.
    private func drawHeldNote(after slot: GlyphSlot, xHeight: CGFloat, alpha: CGFloat) {
        guard style.karaoke, let cue, let elapsed = songElapsed, let end = cue.end,
              let holdStart = cue.marks.last?.time, end - holdStart > 0.6 else { return }
        let held = elapsed - holdStart - 0.25
        guard held > 0, elapsed < end else { return }
        let length = min(14, CGFloat(held) * 28)
        guard length > 1.5 else { return }
        let fade = CGFloat(min(1, (end - elapsed) / 0.2))
        let startX = slot.x + slot.width + 2.5
        let midY = slot.baseline - xHeight / 2
        let amplitude = 1.1 + CGFloat(feeling.wave) * 1.2
        let time = noteTime > 0 ? noteTime : now
        let path = NSBezierPath()
        let steps = max(2, Int(length / 0.75))
        for step in 0...steps {
            let x = length * CGFloat(step) / CGFloat(steps)
            let swing = sin(Double(x) / 5 * 2 * .pi - time * 2 * .pi * 5.5)
            let y = midY + CGFloat(swing) * amplitude * min(1, x / 4)
            if step == 0 {
                path.move(to: NSPoint(x: startX + x, y: y))
            } else {
                path.line(to: NSPoint(x: startX + x, y: y))
            }
        }
        Self.sungColor.withAlphaComponent(0.8 * alpha * fade).setStroke()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// 박이 들어오면 말풍선이 눌렸다가 용수철처럼 튀어 오른다. 저음과 세기가 클수록 크게 출렁인다.
    private func jellySquash() -> CGFloat {
        let t = feeling.sinceBeat
        guard t < 0.9 else { return 0 }
        let strength = min(1, feeling.bass * 0.8 + feeling.wave * 0.45)
        guard strength > 0.08 else { return 0 }
        return CGFloat(strength * 0.05 * exp(-t / 0.16) * cos(t * 2 * .pi / 0.32))
    }

    /// 저음이 세게 들어온 박에는 말풍선 테두리에서 소리 고리가 퍼져 나간다.
    private func drawSoundRing(_ path: NSBezierPath, hook: Bool) {
        let t = feeling.sinceBeat
        guard t < 0.5, feeling.bass > 0.5, feeling.wave > 0.4 else { return }
        let spread = CGFloat(t / 0.5)
        let strength = CGFloat(min(1, (feeling.bass - 0.5) * 2 + 0.35))
        NSGraphicsContext.saveGraphicsState()
        (hook ? Self.hookGold : Self.stroke).withAlphaComponent(0.34 * (1 - spread) * (1 - spread) * strength).setStroke()
        path.lineWidth = 1.5 + spread * 8.5
        path.lineJoinStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 말풍선 아래 가운데에 지금 소리의 대역 세기를 좌우로 펼친다. 가운데가 저음, 바깥으로 갈수록 고음이다.
    private func drawVoiceprint(dx: CGFloat, dy: CGFloat, bands: [Double], whisper: CGFloat, color: NSColor) {
        let order = [7, 5, 3, 1, 0, 2, 4, 6]
        let centerX = bounds.width / 2 + dx
        let baseY = bounds.height - Self.outerPad - 3.2 + dy
        let spacing: CGFloat = 3.2
        let startX = centerX - CGFloat(order.count - 1) * spacing / 2
        let path = NSBezierPath()
        var energy: CGFloat = 0
        for (slot, band) in order.enumerated() where band < bands.count {
            let level = CGFloat(min(1, max(0, bands[band])))
            energy = max(energy, level)
            let half = min(2.7, 0.6 + level * 2.3 * (whisper > 0.3 ? 0.6 : 1))
            let x = startX + CGFloat(slot) * spacing
            path.move(to: NSPoint(x: x, y: baseY - half))
            path.line(to: NSPoint(x: x, y: baseY + half))
        }
        color.withAlphaComponent(min(0.78, 0.3 + energy * 0.5)).setStroke()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.stroke()
    }

    /// 부른 만큼만 보이도록 잘라서 같은 글을 채운 색으로 한 번 더 그린다. 두 줄이면 윗줄부터 채운다.
    private func drawSung(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any], font: NSFont,
                          progress: CGFloat, color: NSColor) {
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map { min(rect.width, ceil(($0 as NSString).size(withAttributes: attributes).width)) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var remaining = min(1, progress) * total
        let clip = NSBezierPath()
        for (index, width) in widths.enumerated() {
            guard remaining > 0 else { break }
            let take = min(width, remaining)
            remaining -= width
            let x = rect.minX + (rect.width - width) / 2
            let top = rect.minY + CGFloat(index) * lineHeight - (index == 0 ? 3 : 0)
            let bottom = rect.minY + CGFloat(index + 1) * lineHeight + (index == lines.count - 1 ? 4 : 0)
            clip.appendRect(NSRect(x: x - 2, y: top, width: take + 2, height: bottom - top))
        }
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        var sung = attributes
        sung[.foregroundColor] = color
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: sung)
        NSGraphicsContext.restoreGraphicsState()
    }

    private struct Countdown {
        var dots = 0
        /// 이번 점이 사라지는 중인 정도(0...1).
        var fading: CGFloat = 0
        /// 간주 음표가 카운트다운에 자리를 내주는 정도(0...1).
        var notesFade: CGFloat = 0
    }

    /// 노래방처럼 다음 줄이 오기 전 네 박을 점으로 센다.
    private func countdownState() -> Countdown {
        guard isInterlude, let cue, let elapsed = songElapsed, let remaining = cue.countdown(at: elapsed) else { return Countdown() }
        let unit = LyricCue.countdownBeat(style.beatPeriod)
        let window = unit * Double(LyricCue.countdownDots)
        guard remaining <= window + 0.35 else { return Countdown() }
        var state = Countdown()
        state.notesFade = CGFloat(min(1, max(0, (window + 0.35 - remaining) / 0.35)))
        guard remaining <= window else { return state }
        let ticks = remaining / unit
        state.dots = min(LyricCue.countdownDots, Int(ceil(ticks)))
        state.fading = ticks == floor(ticks) ? 0 : CGFloat(1 - (ticks - floor(ticks)))
        return state
    }

    private func drawCountdownDots(_ countdown: Countdown, in rect: NSRect, lineHeight: CGFloat, alpha: CGFloat) {
        guard countdown.dots > 0 else { return }
        let total = LyricCue.countdownDots
        let spacing: CGFloat = 15
        let radius: CGFloat = 3.4
        let centerY = rect.minY + lineHeight / 2
        let startX = rect.midX - spacing * CGFloat(total - 1) / 2
        for index in 0..<total {
            // 왼쪽 점부터 사라져서 마지막 점이 가사 쪽에 남는다.
            let visibleFrom = total - countdown.dots
            guard index >= visibleFrom else { continue }
            var scale: CGFloat = 1
            var dotAlpha = alpha
            if index == visibleFrom {
                let fade = max(0, countdown.fading - 0.55) / 0.45
                scale = 1 - fade * 0.6
                dotAlpha *= 1 - fade
            }
            let r = radius * scale
            let x = startX + CGFloat(index) * spacing
            let dot = NSRect(x: x - r, y: centerY - r, width: r * 2, height: r * 2)
            Self.stroke.withAlphaComponent(dotAlpha).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    /// 말풍선 위 모서리에 반응 그림을 붙인다. 꼬리와 겹치지 않게 꼬리 반대쪽 모서리를 고르고, 새 줄이 오면 톡 튀어나온다.
    private func drawReactionSticker(_ reaction: LyricReaction, dx: CGFloat, dy: CGFloat, beat: CGFloat, entering: CGFloat) {
        let glyph = PixelGlyph.reaction(reaction)
        let age = max(0, now - cueShownAt)
        let pop = age < 0.28 ? CGFloat(age / 0.28) : 1
        let overshoot = pop < 1 ? 1 + sin(pop * .pi) * 0.25 : 1
        let pixel = 2 * overshoot * max(0.4, pop)
        let size = pixel * 5
        let top = Self.outerPad + Self.tail + dy
        let onLeft = tailX > bounds.width * 0.62
        let x = onLeft ? Self.outerPad + dx - size * 0.18 : bounds.width - Self.outerPad + dx - size * 0.82
        let y = top - size * 0.45 - beat * 2.2
        drawGlyph(glyph, x: x, y: y, pixel: pixel, alpha: min(1, entering * 1.4))
    }

    private func drawGlyph(_ glyph: PixelGlyph, x: CGFloat, y: CGFloat, pixel: CGFloat, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        for dot in glyph.pixels {
            dot.color.nsColor(alpha: alpha).setFill()
            NSRect(x: x + CGFloat(dot.x) * pixel, y: y + CGFloat(dot.y) * pixel, width: pixel, height: pixel).fill()
        }
    }

    /// 후렴일 때 아래 두 모서리에서 작은 별이 번갈아 반짝인다.
    private func drawHookTwinkles(dx: CGFloat, dy: CGFloat, beat: CGFloat) {
        let left = Self.outerPad + dx
        let right = bounds.width - Self.outerPad + dx
        let bottom = bounds.height - Self.outerPad + dy
        let t = noteTime > 0 ? noteTime : now
        let spots: [(CGFloat, CGFloat, Double)] = [
            (left + 7, bottom - 5, 0),
            (right - 7, bottom - 5, 1.6),
            (left + 14, bottom - 2, 3.1),
        ]
        for (x, y, offset) in spots {
            let twinkle = CGFloat(0.5 + 0.5 * sin(t * 5.2 + offset)) * 0.8 + beat * 0.2
            guard twinkle > 0.15 else { continue }
            let arm = 1.5 + twinkle * 1.5
            Self.hookGold.withAlphaComponent(min(1, twinkle)).setFill()
            NSRect(x: x - 0.75, y: y - arm, width: 1.5, height: arm * 2).fill()
            NSRect(x: x - arm, y: y - 0.75, width: arm * 2, height: 1.5).fill()
        }
    }

    /// 제목 카드의 가수 줄은 조금 더 또렷하게 둔다.
    private func previewColor(alpha: CGFloat) -> NSColor {
        if cue?.isTitle == true { return NSColor.secondaryLabelColor.withAlphaComponent(min(1, alpha + 0.35)) }
        if cue?.recap != nil { return NSColor.secondaryLabelColor.withAlphaComponent(min(1, alpha + 0.25)) }
        return NSColor.labelColor.withAlphaComponent(alpha)
    }

    /// 가사를 모르는 곡일 때 글자 없이 콧노래 선율 파동과 리듬을 타는 음표만으로 흥얼거림을 표현한다.
    private func drawHumming(
        in rect: NSRect,
        alpha: CGFloat,
        time: Double,
        wave: CGFloat,
        beat: CGFloat,
        shout: CGFloat,
        whisper: CGFloat
    ) {
        guard alpha > 0.01, rect.width > 20 else { return }
        let midY = rect.minY + (rect.height - 2) * 0.5
        let startX = rect.minX + 6
        let endX = rect.maxX - 6
        let spanW = max(16, endX - startX)
        let energy = min(1.0, max(wave, shout * 0.85))
        let softScale: CGFloat = whisper > 0.25 ? max(0.55, 1.0 - whisper * 0.35) : 1.0

        // 1) 보컬 파장에 반응해 숨쉬듯 일렁이는 이중 콧노래 선율 리본
        let primaryRibbon = NSBezierPath()
        let echoRibbon = NSBezierPath()
        let steps = 28
        let amp: CGFloat = (2.2 + energy * 3.4 + beat * 1.4) * softScale
        for s in 0...steps {
            let frac = CGFloat(s) / CGFloat(steps)
            let x = startX + frac * spanW
            let env = sin(frac * .pi)
            let y1 = midY + CGFloat(sin(Double(frac) * .pi * 3.0 - time * 4.4)) * amp * env
            let y2 = midY + CGFloat(sin(Double(frac) * .pi * 2.2 - time * 3.1 + 1.3)) * (amp * 0.68) * env
            if s == 0 {
                primaryRibbon.move(to: NSPoint(x: x, y: y1))
                echoRibbon.move(to: NSPoint(x: x, y: y2))
            } else {
                primaryRibbon.line(to: NSPoint(x: x, y: y1))
                echoRibbon.line(to: NSPoint(x: x, y: y2))
            }
        }
        Self.stroke.withAlphaComponent((0.36 + energy * 0.28) * alpha).setStroke()
        primaryRibbon.lineWidth = 1.4 + energy * 0.7
        primaryRibbon.lineCapStyle = .round
        primaryRibbon.stroke()

        NSColor.labelColor.withAlphaComponent((0.18 + energy * 0.14) * alpha).setStroke()
        echoRibbon.lineWidth = 1.05
        echoRibbon.lineCapStyle = .round
        echoRibbon.stroke()

        // 2) 선율 마디 사이에서 박자에 맞춰 통통 튀는 작은 리듬 방울 점
        for d in 0..<4 {
            let frac = CGFloat(d + 1) / 5.0
            let dx = startX + frac * spanW
            let dotBounce = CGFloat(sin(time * 5.2 + Double(d) * 1.3)) * (2.0 + energy * 2.2)
            let dy = midY + dotBounce
            let dotR: CGFloat = 1.3 + CGFloat(0.5 + 0.5 * sin(time * 6.0 + Double(d))) * (0.7 + energy * 0.6)
            let dotRect = NSRect(x: dx - dotR, y: dy - dotR, width: dotR * 2, height: dotR * 2)
            Self.stroke.withAlphaComponent(0.42 * alpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // 3) 자리에서 리듬을 타며 고개를 흔들듯 춤추고 떠오르는 음표들
        let notes = ["♪", "♫", "♬"]
        for i in 0..<notes.count {
            let slotFrac = (CGFloat(i) + 0.5) / CGFloat(notes.count)
            let swayX = CGFloat(sin(time * 3.4 + Double(i) * 2.1)) * (3.2 + energy * 2.0)
            let bounceY = CGFloat(cos(time * 5.0 + Double(i) * 1.7)) * (2.4 + energy * 2.2) - beat * 1.8
            let x = startX + slotFrac * spanW + swayX
            let y = midY + bounceY
            let pulse = CGFloat(0.5 + 0.5 * sin(time * 4.6 + Double(i) * 1.5))
            let size = (12.8 + pulse * 2.2 + energy * 1.6) * softScale
            let font = NSFont.systemFont(ofSize: size, weight: shout > 0.35 ? .bold : .semibold)
            let noteColor = (i == 1)
                ? Self.stroke.withAlphaComponent(alpha * (0.88 + 0.12 * pulse))
                : NSColor.labelColor.withAlphaComponent(alpha * (0.78 + 0.18 * pulse))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: noteColor,
            ]
            let symbol = notes[i] as NSString
            let sSize = symbol.size(withAttributes: attrs)
            symbol.draw(at: NSPoint(x: x - sSize.width * 0.5, y: y - sSize.height * 0.52), withAttributes: attrs)
        }
    }

    /// 간주 중에 말풍선 안을 물결치는 선율과 함께 음표들이 부드럽게 흘러가게 그린다.
    private func drawInterludeNotes(in rect: NSRect, alpha: CGFloat, time: Double, wave: CGFloat, beat: CGFloat) {
        guard alpha > 0.01, rect.width > 20 else { return }
        let midY = rect.minY + (rect.height - 2) * 0.5
        let startX = rect.minX + 6
        let endX = rect.maxX - 6
        let spanW = max(16, endX - startX)

        // 1) 배경에 은은하게 흐르는 두 줄의 선율 물결선
        let stream1 = NSBezierPath()
        let stream2 = NSBezierPath()
        let steps = 24
        let amp: CGFloat = 2.0 + wave * 2.2
        for s in 0...steps {
            let frac = CGFloat(s) / CGFloat(steps)
            let x = startX + frac * spanW
            let env = sin(frac * .pi)
            let y1 = midY + CGFloat(sin(Double(frac) * .pi * 2.4 - time * 3.0)) * amp * env
            let y2 = midY + CGFloat(cos(Double(frac) * .pi * 2.0 - time * 2.3 + 1.1)) * (amp * 0.75) * env
            if s == 0 {
                stream1.move(to: NSPoint(x: x, y: y1))
                stream2.move(to: NSPoint(x: x, y: y2))
            } else {
                stream1.line(to: NSPoint(x: x, y: y1))
                stream2.line(to: NSPoint(x: x, y: y2))
            }
        }
        Self.stroke.withAlphaComponent(0.22 * alpha).setStroke()
        stream1.lineWidth = 1.15
        stream1.lineCapStyle = .round
        stream1.stroke()

        NSColor.secondaryLabelColor.withAlphaComponent(0.15 * alpha).setStroke()
        stream2.lineWidth = 1.0
        stream2.lineCapStyle = .round
        stream2.stroke()

        // 2) 물결을 타고 왼쪽에서 오른쪽으로 흘러가는 음표들
        let symbols = ["♪", "♫", "♬", "♩", "♫"]
        let count = symbols.count
        let flow = noteFlow.advance(to: time, speed: 0.28 + Double(wave) * 0.08)
        for i in 0..<count {
            let rawPhase = flow + Double(i) / Double(count)
            let u = rawPhase - floor(rawPhase) // 0.0 (왼쪽) -> 1.0 (오른쪽)
            let edgeFade: CGFloat
            if u < 0.18 {
                edgeFade = CGFloat(sin((u / 0.18) * (.pi / 2)))
            } else if u > 0.82 {
                edgeFade = CGFloat(sin(((1.0 - u) / 0.18) * (.pi / 2)))
            } else {
                edgeFade = 1.0
            }

            let x = startX + CGFloat(u) * spanW
            let bob = CGFloat(sin(u * .pi * 2.4 - time * 3.0 + Double(i) * 0.9)) * (2.6 + wave * 2.0) - beat * 1.4
            let y = midY + bob
            let pulse = CGFloat(0.5 + 0.5 * sin(time * 4.4 + Double(i) * 1.3))
            let fontSize: CGFloat = 12.6 + pulse * 2.0 + wave * 1.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let noteColor = (i % 2 == 0)
                ? Self.stroke.withAlphaComponent(alpha * edgeFade * (0.85 + 0.15 * pulse))
                : NSColor.labelColor.withAlphaComponent(alpha * edgeFade * (0.72 + 0.20 * pulse))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: noteColor,
            ]
            let symbol = symbols[i] as NSString
            let size = symbol.size(withAttributes: attrs)
            let drawPt = NSPoint(x: x - size.width * 0.5, y: y - size.height * 0.52)
            symbol.draw(at: drawPt, withAttributes: attrs)
        }
    }

    private func currentFont(shout: CGFloat, whisper: CGFloat, wave: CGFloat) -> NSFont {
        if shout > 0.18 {
            let size = 13.0 + min(1.6, shout * 1.45 + wave * 0.25)
            let weight: NSFont.Weight = shout > 0.52 ? .bold : .semibold
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        if whisper > 0.2 {
            let size = 13.0 - min(1.5, whisper * 1.45)
            let weight: NSFont.Weight = whisper > 0.55 ? .light : .regular
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        let size = 13.0 + wave * 0.35
        return NSFont.systemFont(ofSize: size, weight: .medium)
    }

    private func drawShoutSparks(dx: CGFloat, dy: CGFloat, shout: CGFloat, wave: CGFloat, color: NSColor) {
        let left = Self.outerPad + dx
        let right = bounds.width - Self.outerPad + dx
        let top = Self.outerPad + Self.tail + dy
        let bottom = bounds.height - Self.outerPad + dy
        let len = 2.5 + shout * 3.2 + wave * 1.5
        let sparkPath = NSBezierPath()
        let corners: [(NSPoint, CGFloat, CGFloat)] = [
            (NSPoint(x: left + 3, y: top + 3), -0.85, -0.85),
            (NSPoint(x: right - 3, y: top + 3), 0.85, -0.85),
            (NSPoint(x: left + 3, y: bottom - 3), -0.85, 0.85),
            (NSPoint(x: right - 3, y: bottom - 3), 0.85, 0.85),
        ]
        for (origin, vx, vy) in corners {
            sparkPath.move(to: origin)
            sparkPath.line(to: NSPoint(x: origin.x + vx * len, y: origin.y + vy * len))
        }
        color.withAlphaComponent(min(0.9, shout)).setStroke()
        sparkPath.lineWidth = 1.4 + shout * 0.6
        sparkPath.lineCapStyle = .round
        sparkPath.stroke()
    }

    private func drawWaveformBars(dx: CGFloat, dy: CGFloat, wave: CGFloat, shout: CGFloat, whisper: CGFloat, phase: Double, color: NSColor) {
        let centerX = bounds.width / 2 + dx
        let baseY = bounds.height - Self.outerPad - 3.2 + dy
        let barCount = 5
        let spacing: CGFloat = 3.6
        let startX = centerX - CGFloat(barCount - 1) * spacing / 2
        let wavePath = NSBezierPath()
        let energy = min(1.0, max(wave, shout * 0.85))
        for i in 0..<barCount {
            let centerWeight: CGFloat = (i == 2) ? 1.0 : ((i == 1 || i == 3) ? 0.78 : 0.52)
            let osc = CGFloat(0.65 + 0.35 * sin(phase * 18.0 + Double(i) * 1.35))
            let halfH = max(0.7, min(2.6, energy * 2.5 * centerWeight * osc * (whisper > 0.3 ? 0.55 : 1.0)))
            let x = startX + CGFloat(i) * spacing
            wavePath.move(to: NSPoint(x: x, y: baseY - halfH))
            wavePath.line(to: NSPoint(x: x, y: baseY + halfH))
        }
        color.withAlphaComponent(min(0.75, 0.3 + energy * 0.5)).setStroke()
        wavePath.lineWidth = 1.3
        wavePath.lineCapStyle = .round
        wavePath.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func bubblePath(dx: CGFloat, dy: CGFloat) -> NSBezierPath {
        let width = bounds.width
        let height = bounds.height
        let radius: CGFloat = 10
        let left = Self.outerPad + dx
        let right = width - Self.outerPad + dx
        let top = Self.outerPad + Self.tail + dy
        let bottom = height - Self.outerPad + dy
        let mid = min(max(tailX + dx, left + radius + 12), right - radius - 12)
        let half: CGFloat = 7
        let path = NSBezierPath()
        path.move(to: NSPoint(x: mid + half, y: top))
        path.line(to: NSPoint(x: right - radius, y: top))
        path.appendArc(from: NSPoint(x: right, y: top), to: NSPoint(x: right, y: top + radius), radius: radius)
        path.line(to: NSPoint(x: right, y: bottom - radius))
        path.appendArc(from: NSPoint(x: right, y: bottom), to: NSPoint(x: right - radius, y: bottom), radius: radius)
        path.line(to: NSPoint(x: left + radius, y: bottom))
        path.appendArc(from: NSPoint(x: left, y: bottom), to: NSPoint(x: left, y: bottom - radius), radius: radius)
        path.line(to: NSPoint(x: left, y: top + radius))
        path.appendArc(from: NSPoint(x: left, y: top), to: NSPoint(x: left + radius, y: top), radius: radius)
        path.line(to: NSPoint(x: mid - half, y: top))
        path.line(to: NSPoint(x: mid, y: Self.outerPad + dy * 0.35))
        path.line(to: NSPoint(x: mid + half, y: top))
        path.close()
        return path
    }

    private static let previewGap: CGFloat = 3
    private static let measureFont = NSFont.systemFont(ofSize: 14.5, weight: .bold)
    private static let previewFont = NSFont.systemFont(ofSize: 11.0, weight: .regular)
    private static let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    static let stroke = NSColor(srgbRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
    /// 부른 글자. 라이트·다크 모두에서 읽히도록 코랄을 조금 진하게.
    private static let sungColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.56, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.36, blue: 0.22, alpha: 1)
    }
    private static let hookGold = NSColor(srgbRed: 1.0, green: 0.76, blue: 0.24, alpha: 1)
    /// 후렴 글자를 훑는 반짝임. 밝은 화면에서는 탁해지지 않게 진한 호박색으로.
    private static let shimmerGold = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.80, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.58, blue: 0.02, alpha: 1)
    }
}
