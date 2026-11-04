import AppKit

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
    private var interludeTimer: Timer?
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

    func show(_ cue: LyricCue, feeling: VocalFeeling = .calm, feelingEnabled: Bool = true, anchor: NSRect, screen: NSScreen) {
        let effective = feelingEnabled ? BubbleView.combinedFeeling(for: cue.current, audio: feeling) : .calm
        let layout = BubbleView.layout(for: cue)
        let nextFrame = computeFrame(size: layout.size, anchor: anchor, screen: screen)
        let lineChanged = currentCue != nil
            && (currentCue?.current != cue.current
                || currentCue?.isInterlude != cue.isInterlude
                || currentCue?.isHumming != cue.isHumming)
            && panel.isVisible
            && (!view.text.isEmpty || view.isInterlude || view.isHumming)
        currentCue = cue
        view.feeling = effective
        targetFrame = nextFrame
        targetAnchorMidX = anchor.midX

        if lineChanged {
            view.outgoingText = view.text
            view.outgoingIsInterlude = view.isInterlude
            view.outgoingIsHumming = view.isHumming
            view.outgoingNextText = view.nextText
            view.isInterlude = cue.isInterlude
            view.isHumming = cue.isHumming
            view.text = layout.current
            view.nextText = layout.next
            view.transitionProgress = 0
            startFrame = panel.frame
            transitionStart = ProcessInfo.processInfo.systemUptime
            startTransitionTimer()
        } else {
            view.isInterlude = cue.isInterlude
            view.isHumming = cue.isHumming
            view.text = layout.current
            view.nextText = layout.next
            if transitionTimer == nil {
                view.outgoingText = ""
                view.outgoingIsInterlude = false
                view.outgoingIsHumming = false
                view.outgoingNextText = nil
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
        syncInterludeTimer()
    }

    private func startTransitionTimer() {
        transitionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepTransition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func syncInterludeTimer() {
        if panel.isVisible && (view.isInterlude || view.outgoingIsInterlude || view.isHumming || view.outgoingIsHumming) {
            if interludeTimer == nil {
                view.noteTime = ProcessInfo.processInfo.systemUptime
                let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.view.noteTime = ProcessInfo.processInfo.systemUptime
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                interludeTimer = timer
            }
        } else {
            interludeTimer?.invalidate()
            interludeTimer = nil
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
            view.transitionProgress = 1.0
            applyFrame(targetFrame, anchorMidX: targetAnchorMidX)
            syncInterludeTimer()
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
        interludeTimer?.invalidate()
        interludeTimer = nil
        currentCue = nil
        view.text = ""
        view.nextText = nil
        view.outgoingText = ""
        view.isInterlude = false
        view.outgoingIsInterlude = false
        view.isHumming = false
        view.outgoingIsHumming = false
        view.outgoingNextText = nil
        view.transitionProgress = 1.0
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

@MainActor
private final class BubbleView: NSView {
    static let outerPad: CGFloat = 6
    static let tail: CGFloat = 8
    static let padX: CGFloat = 13
    static let padY: CGFloat = 7
    static let singleLineLimit: CGFloat = 230
    static let maxTextWidth: CGFloat = 320
    static let interludeWidth: CGFloat = 132
    static let hummingWidth: CGFloat = 114

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

    override var isFlipped: Bool { true }

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
        if cue.isHumming {
            let lineHeight = ceil(measureFont.ascender - measureFont.descender + measureFont.leading)
            mainFormatted = cue.current
            mainTextSize = NSSize(width: hummingWidth, height: lineHeight)
        } else if cue.isInterlude {
            let lineHeight = ceil(measureFont.ascender - measureFont.descender + measureFont.leading)
            mainFormatted = cue.current
            mainTextSize = NSSize(width: interludeWidth, height: lineHeight)
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

    override func draw(_ dirtyRect: NSRect) {
        let shout = CGFloat(feeling.shout)
        let whisper = CGFloat(feeling.whisper)
        let wave = CGFloat(feeling.wave)
        let beat = CGFloat(feeling.beat)
        let bass = CGFloat(feeling.bass)
        let phase = feeling.phase

        // 외침(소리질러야 하는 부분)은 고주파 떨림, 속삭임은 잔잔한 부유감, 박자는 통통 튀는 반동을 준다.
        let shakeAmp = shout > 0.16 ? (shout - 0.16) * 2.4 : 0
        let jitterX = CGFloat(sin(phase * 43.0)) * shakeAmp
        let jitterY = CGFloat(cos(phase * 36.0)) * shakeAmp * 0.75
        let floatY = whisper > 0.15 ? CGFloat(sin(phase * 2.6)) * whisper * 1.4 : 0
        let bounceY = beat * 1.8
        let dx = jitterX
        let dy = jitterY + floatY + bounceY

        let path = bubblePath(dx: dx, dy: dy)

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

        // 테두리 선 (속삭일 때는 점선, 외칠 때는 굵고 강렬한 코랄 레드)
        NSGraphicsContext.saveGraphicsState()
        let borderColor: NSColor
        if shout > 0.2 {
            borderColor = NSColor(
                srgbRed: (217 + 35 * shout) / 255,
                green: (119 - 46 * shout) / 255,
                blue: (87 - 36 * shout) / 255,
                alpha: 1
            )
        } else if whisper > 0.2 {
            borderColor = Self.stroke.withAlphaComponent(max(0.45, 0.88 - whisper * 0.38))
        } else {
            borderColor = Self.stroke.withAlphaComponent(0.88 + wave * 0.12)
        }
        borderColor.setStroke()
        path.lineWidth = 1.45 + shout * 1.05 + wave * 0.35 - whisper * 0.35
        path.lineJoinStyle = .round
        if whisper > 0.25 && shout < 0.2 {
            let pattern: [CGFloat] = [4.0, 3.2]
            path.setLineDash(pattern, count: pattern.count, phase: CGFloat(phase * 6.0))
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 소리질러야 하는 부분에서는 말풍선 모서리에 실시간 파장 강조선(폭발선)을 그린다.
        if shout > 0.32 {
            drawShoutSparks(dx: dx, dy: dy, shout: shout, wave: wave, color: borderColor)
        }

        // 오디오 파장이 살아 있을 때 말풍선 하단 중앙에 실시간 미니 파장 바를 그린다.
        if wave > 0.04 || shout > 0.2 {
            drawWaveformBars(dx: dx, dy: dy, wave: wave, shout: shout, whisper: whisper, phase: phase, color: borderColor)
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

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let previewStyle = NSMutableParagraphStyle()
        previewStyle.alignment = .center
        previewStyle.lineBreakMode = .byTruncatingTail

        let baseAlpha: CGFloat = whisper > 0.2 ? max(0.66, 1.0 - whisper * 0.32) : 1.0
        let previewAlpha: CGFloat = 0.46
        let p = min(1.0, max(0.0, transitionProgress))
        let animTime = noteTime > 0 ? noteTime : (phase > 0 ? phase : ProcessInfo.processInfo.systemUptime)

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
                    .paragraphStyle: style,
                ]
                (outgoingText as NSString).draw(with: outRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: outAttrs)
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
                drawInterludeNotes(in: risingRect, alpha: risingAlpha, time: animTime, wave: wave, beat: beat)
            } else {
                let risingSize = Self.previewFont.pointSize + (activeFont.pointSize - Self.previewFont.pointSize) * p
                let risingFont = p < 0.45
                    ? NSFont.systemFont(ofSize: risingSize, weight: .regular)
                    : NSFont.systemFont(ofSize: risingSize, weight: shout > 0.3 ? .bold : .medium)
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
                    .paragraphStyle: style,
                ]
                if whisper > 0.25 {
                    risingAttrs[.kern] = 0.45 * whisper * p
                }
                (text as NSString).draw(with: risingRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: risingAttrs)
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
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(incomingAlpha),
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
                drawInterludeNotes(in: rect, alpha: baseAlpha, time: animTime, wave: wave, beat: beat)
            } else {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: activeFont,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(baseAlpha),
                    .paragraphStyle: style,
                ]
                if whisper > 0.25 {
                    attributes[.kern] = 0.45 * whisper
                }
                (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
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
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(previewAlpha),
                    .paragraphStyle: previewStyle,
                ]
                (nextText as NSString).draw(with: nextRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nextAttrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
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
        let speed = 0.28 + Double(wave) * 0.08
        for i in 0..<count {
            let rawPhase = time * speed + Double(i) / Double(count)
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
    private static let stroke = NSColor(srgbRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
}
