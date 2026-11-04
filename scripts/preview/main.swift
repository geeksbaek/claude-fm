import AppKit

// 화면 요소를 상태별로 PNG 로 그린다. 눈으로 확인하고 README 그림을 만들 때 쓴다.
//   scripts/preview.sh <out-dir>

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: preview <out-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let light = NSAppearance(named: .aqua)!
let dark = NSAppearance(named: .darkAqua)!

func write(_ rep: NSBitmapImageRep, _ name: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("✗ \(name): png 실패")
        return
    }
    do {
        try data.write(to: outDir.appendingPathComponent(name))
        print("✓ \(name) \(rep.pixelsWide)×\(rep.pixelsHigh)")
    } catch {
        print("✗ \(name): \(error)")
    }
}

/// 뷰를 2배로 그린다. 배경색을 주면 그 위에 얹는다(말풍선은 메뉴바 아래 데스크톱 위에 뜬다).
@MainActor
func snapshot(_ view: NSView, appearance: NSAppearance, background: NSColor, scale: CGFloat = 2) -> NSBitmapImageRep {
    let size = view.frame.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    background.setFill()
    NSRect(origin: .zero, size: size).fill()
    if view.isFlipped {
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    }
    view.appearance = appearance
    appearance.performAsCurrentDrawingAppearance {
        view.draw(view.bounds)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 여러 장을 세로로 이어 붙인다.
func stack(_ reps: [NSBitmapImageRep], gap: Int = 24, background: NSColor) -> NSBitmapImageRep {
    let width = reps.map(\.pixelsWide).max() ?? 1
    let height = reps.map(\.pixelsHigh).reduce(0, +) + gap * (reps.count + 1)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width + gap * 2, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
    var y = height - gap
    for item in reps {
        y -= item.pixelsHigh
        item.draw(in: NSRect(x: gap, y: y, width: item.pixelsWide, height: item.pixelsHigh))
        y -= gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 말풍선

struct BubbleCase {
    var name: String
    var cue: LyricCue
    var elapsed: Double?
    var feeling = VocalFeeling.calm
    var style = BubbleStyle()
    /// 음표·반짝임처럼 시계로 움직이는 것을 이만큼 앞당겨 그린다.
    var noteOffset = 0.0
}

func line(_ text: String, next: String?, start: Double, end: Double, reaction: LyricReaction? = nil, hook: Bool = false) -> LyricCue {
    var cue = LyricCue(current: text, next: next)
    cue.start = start
    cue.end = end
    cue.reaction = reaction
    cue.isHook = hook
    cue.marks = LyricInsight.phrasedMarks(text, start: start, end: end, rate: 4.5)
    return cue
}

var countdownCue = LyricCue.interlude(next: "다시 한 번 너에게로")
countdownCue.nextStart = 20
let recapCue = LyricCue.recap(LyricRecap(reaction: .love, word: "love", count: 12))
var beatFeeling = VocalFeeling.calm
beatFeeling.beat = 0.7
beatFeeling.wave = 0.5
var shoutFeeling = VocalFeeling.calm
shoutFeeling.shout = 0.75
shoutFeeling.wave = 0.8
shoutFeeling.bass = 0.7
shoutFeeling.sinceBeat = 0.12
shoutFeeling.bands = [0.95, 0.9, 0.7, 0.75, 0.8, 0.7, 0.55, 0.4]
var rippleFeeling = VocalFeeling.calm
rippleFeeling.wave = 0.65
rippleFeeling.bass = 0.45
rippleFeeling.beat = 0.5
rippleFeeling.sinceBeat = 0.16
rippleFeeling.bands = [0.85, 0.7, 0.55, 0.5, 0.45, 0.35, 0.25, 0.15]
var whisperFeeling = VocalFeeling.calm
whisperFeeling.whisper = 0.7
whisperFeeling.wave = 0.18
whisperFeeling.bands = [0.3, 0.25, 0.3, 0.35, 0.25, 0.15, 0.1, 0.05]
var heldFeeling = VocalFeeling.calm
heldFeeling.wave = 0.55
heldFeeling.bands = [0.5, 0.45, 0.5, 0.6, 0.55, 0.4, 0.3, 0.2]

let bubbleCases: [BubbleCase] = [
    BubbleCase(name: "karaoke", cue: line("너를 처음 만난 그 날처럼", next: "별빛이 내린 밤", start: 10, end: 13, reaction: .love),
               elapsed: 11.3),
    BubbleCase(name: "karaoke-two-lines", cue: line("아이 니드 유 투나잇 앤 에브리 나잇 비코즈 유어 마이 온리 원 앤 온리",
                                                    next: "돈트 고", start: 10, end: 16), elapsed: 14.2),
    BubbleCase(name: "hook", cue: line("반짝반짝 빛나는 별처럼", next: "우리 함께라면", start: 30, end: 33, reaction: .star, hook: true),
               elapsed: 31.0, feeling: beatFeeling, noteOffset: 0.8),
    BubbleCase(name: "ripple", cue: line("오늘 밤 우리 함께 춤을 춰요", next: "끝나지 않게", start: 50, end: 53),
               elapsed: 51.1, feeling: rippleFeeling),
    BubbleCase(name: "whisper", cue: line("조용히... 너를 불러", next: nil, start: 60, end: 63), elapsed: 61.0,
               feeling: whisperFeeling),
    BubbleCase(name: "held-note", cue: line("사랑해", next: "오래오래", start: 70, end: 73.2, reaction: .love), elapsed: 72.6,
               feeling: heldFeeling),
    BubbleCase(name: "countdown", cue: countdownCue, elapsed: 18.8, style: BubbleStyle(karaoke: true, reactions: true, beatPeriod: 0.5)),
    BubbleCase(name: "title", cue: .title("Supernova", artist: "aespa"), elapsed: nil),
    BubbleCase(name: "recap", cue: recapCue, elapsed: nil),
    BubbleCase(name: "shout", cue: line("소리 질러!!", next: nil, start: 40, end: 41.5, reaction: .fire), elapsed: 41.0,
               feeling: shoutFeeling),
    BubbleCase(name: "humming", cue: .humming(), elapsed: nil),
]

let freeze = 1_000.0
MainActor.assumeIsolated {
    var lightReps: [NSBitmapImageRep] = []
    var darkReps: [NSBitmapImageRep] = []
    for item in bubbleCases {
        let view = BubbleView()
        let layout = BubbleView.layout(for: item.cue)
        view.frame = NSRect(origin: .zero, size: layout.size)
        view.frozenTime = freeze
        view.noteTime = freeze + item.noteOffset
        view.cueShownAt = freeze - 2
        var feeling = item.feeling
        feeling.phase = freeze
        view.feeling = BubbleView.combinedFeeling(for: item.cue.current, audio: feeling)
        view.style = item.style
        view.cue = item.cue
        view.isInterlude = item.cue.isInterlude
        view.isHumming = item.cue.isHumming
        view.text = layout.current
        view.nextText = layout.next
        view.tailX = layout.size.width / 2
        if let elapsed = item.elapsed {
            view.clock = PlaybackClock(elapsed: elapsed, uptime: freeze, rate: 1)
        }
        let desk = NSColor(srgbRed: 0.84, green: 0.86, blue: 0.90, alpha: 1)
        let night = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        let l = snapshot(view, appearance: light, background: desk)
        let d = snapshot(view, appearance: dark, background: night)
        write(l, "bubble-\(item.name)-light.png")
        write(d, "bubble-\(item.name)-dark.png")
        lightReps.append(l)
        darkReps.append(d)
    }
    write(stack(lightReps, background: NSColor(srgbRed: 0.84, green: 0.86, blue: 0.90, alpha: 1)), "bubbles-light.png")
    write(stack(darkReps, background: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)), "bubbles-dark.png")
}

// MARK: - 메뉴바 Clawd

func spriteSheet(appearance: NSAppearance, background: NSColor, ink: NSColor) -> NSBitmapImageRep {
    let scale: CGFloat = 8, gap: CGFloat = 16
    let cell = NSSize(width: ClawdSprite.canvas.width * scale, height: ClawdSprite.canvas.height * scale)
    let dance = DancePose(active: true, hop: 1, stepRight: false, mood: .groove, style: .bounce, danceTime: 1)
    var handsUp = dance
    handsUp.style = .handsUp
    var rows: [(DancePose, SpriteAccent)] = []
    for reaction in LyricReaction.allCases {
        rows.append((dance, SpriteAccent(reaction: reaction, hook: false)))
    }
    rows.append((handsUp, SpriteAccent(reaction: .love, hook: true)))
    rows.append((DancePose.idle, SpriteAccent(reaction: .star, hook: true)))
    let columns = 4
    let size = NSSize(width: CGFloat(columns) * (cell.width + gap) + gap, height: CGFloat(rows.count) * (cell.height + gap) + gap)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .none
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    background.setFill()
    NSRect(origin: .zero, size: size).fill()
    appearance.performAsCurrentDrawingAppearance {
        for (r, row) in rows.enumerated() {
            for c in 0..<columns {
                var pose = row.0
                pose.hop = c % 2 == 0 ? 1 : 0.3
                pose.stepRight = c >= 2
                let origin = CGPoint(x: gap + CGFloat(c) * (cell.width + gap), y: gap + CGFloat(r) * (cell.height + gap))
                ClawdSprite.draw(frame: c * 2 + 1, playing: false, dance: pose, scale: scale, origin: origin, noteColor: ink,
                                 accent: row.1)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

write(spriteSheet(appearance: light, background: NSColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1),
                  ink: NSColor(srgbRed: 0.16, green: 0.15, blue: 0.13, alpha: 1)), "sprite-reactions.png")

// MARK: - 무대

/// 픽셀 무대를 이웃 픽셀로 키워 깔고, 그 위에 글자 층을 그린다.
@MainActor
func renderStage(_ input: StageInput, hud: StageHUDView.State, size: NSSize = NSSize(width: 960, height: 540)) -> NSBitmapImageRep {
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    let pixelScale = max(1, Int((size.height / 180).rounded()))
    let width = Int((size.width / CGFloat(pixelScale)).rounded(.up))
    let height = Int((size.height / CGFloat(pixelScale)).rounded(.up))
    let canvas = RasterCanvas(width: width, height: height)
    StageScene.render(input, into: canvas)
    if let image = canvas.makeImage() {
        cg.interpolationQuality = .none
        let drawn = CGSize(width: CGFloat(width * pixelScale), height: CGFloat(height * pixelScale))
        cg.draw(image, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
    }
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    let view = StageHUDView(frame: NSRect(origin: .zero, size: size))
    view.update(hud)
    dark.performAsCurrentDrawingAppearance {
        view.draw(view.bounds)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

struct StageCase {
    var name: String
    var configure: (inout StageInput, inout StageHUDView.State) -> Void
}

func stageLine(_ text: String, original: String = "", next: String?, start: Double, end: Double,
               reaction: LyricReaction? = nil, hook: Bool = false) -> LyricCue {
    var cue = line(text, next: next, start: start, end: end, reaction: reaction, hook: hook)
    cue.original = original
    return cue
}

let stageCases: [StageCase] = [
    StageCase(name: "karaoke") { input, hud in
        hud.cue = stageLine("사쿠라 히라히라 마이오리테 오치테", original: "桜ひらひら舞い降りて落ちて",
                            next: "유레루 오모이노 타케", start: 10, end: 14, reaction: .flower)
        hud.elapsed = 12.1
        hud.title = "桜流し"
        hud.subtitle = "宇多田ヒカル"
        hud.bpm = 92
        hud.moodLabel = "리듬"
        input.reaction = .flower
        input.reactionLevel = 1
        input.accent = SpriteAccent(reaction: .flower, hook: false)
    },
    StageCase(name: "hook") { input, hud in
        hud.cue = stageLine("너를 사랑해 영원히", next: "하늘 위로 날아가", start: 30, end: 33, reaction: .love, hook: true)
        hud.elapsed = 31.6
        hud.title = "First Love"
        hud.subtitle = "Clawd & Friends"
        hud.bpm = 128
        hud.moodLabel = "빠름"
        input.pose = DancePose(active: true, hop: 1, stepRight: true, mood: .drive, style: .handsUp, danceTime: 30)
        input.hookLevel = 1
        input.reaction = .love
        input.reactionLevel = 1
        input.accent = SpriteAccent(reaction: .love, hook: true)
        var burst = ConfettiBurst(originX: 26, originY: 176, scale: 0.9, count: 54, seed: 9,
                                  colors: MoodPalette.of(.drive).confetti, glyph: .love, upward: true)
        input.bursts = [StageBurst(burst: burst, age: 0.85)]
        burst.originX = 294
        burst.seed = 40
        input.bursts.append(StageBurst(burst: burst, age: 0.8))
    },
    StageCase(name: "title") { input, hud in
        hud.cue = .title("Supernova", artist: "aespa")
        hud.cueAge = 1
        hud.title = "Supernova"
        hud.subtitle = "aespa"
        input.pose.mood = .bright
    },
    StageCase(name: "countdown") { input, hud in
        var cue = LyricCue.interlude(next: "다시 한 번 너에게로")
        cue.nextStart = 50
        hud.cue = cue
        hud.elapsed = 48.8
        hud.beatPeriod = 0.5
        hud.title = "Interlude"
        hud.subtitle = "Clawd"
        hud.bpm = 120
        input.pose.mood = .bass
        input.reaction = .moon
        input.reactionLevel = 1
    },
    StageCase(name: "recap") { input, hud in
        hud.cue = .recap(LyricRecap(reaction: .love, word: "love", count: 12))
        hud.cueAge = 1
        hud.title = "Love Song"
        hud.subtitle = "Clawd"
        input.pose = DancePose(active: true, hop: 0.4, stepRight: false, mood: .calm, style: .waveTilt, danceTime: 40)
    },
    StageCase(name: "live") { input, hud in
        hud.title = "Claude FM — lofi beats to code to"
        hud.subtitle = "Claude FM"
        hud.live = true
        hud.bpm = 84
        hud.moodLabel = "잔잔"
        input.playing = true
        input.pose = DancePose(active: true, hop: 0.5, stepRight: false, mood: .calm, style: .bounce, danceTime: 6)
        input.hour = 2
    },
    StageCase(name: "idle") { input, hud in
        input.live = false
        input.pose = .idle
        input.spectrum = Array(repeating: 0, count: SpectrumMeter.bandCount)
        hud.idle = true
    },
]

MainActor.assumeIsolated {
    for item in stageCases {
        var input = StageInput()
        input.time = 12.3
        input.spriteFrame = 5
        input.live = true
        input.spectrum = [0.9, 0.8, 0.65, 0.7, 0.55, 0.45, 0.35, 0.2]
        input.pose = DancePose(active: true, hop: 0.9, stepRight: false, mood: .groove, style: .bounce, danceTime: 2)
        input.feeling.wave = 0.6
        input.feeling.bass = 0.5
        input.beatCount = 6
        input.beatPhase = 0.2
        var hud = StageHUDView.State()
        hud.idle = false
        hud.karaoke = true
        item.configure(&input, &hud)
        // 무대 창처럼 제목·곡 기록이 뜨는 동안은 전광판을 어둡게 누른다.
        if let cue = hud.cue, cue.isTitle || cue.recap != nil { input.splash = 1 }
        hud.palette = MoodPalette.of(input.pose.mood == .quiet ? .groove : input.pose.mood)
        hud.hop = input.pose.active ? input.pose.hop : 0
        write(renderStage(input, hud: hud), "stage-\(item.name).png")
    }
}

// MARK: - README 대표 그림

/// 메뉴바 한 줄에 Clawd 가 있고, 그 아래로 말풍선이 뜬 모습.
@MainActor
func menuBarScene(appearance: NSAppearance, cue: LyricCue, elapsed: Double?, accent: SpriteAccent,
                  pose: DancePose, feeling: VocalFeeling) -> NSBitmapImageRep {
    let scale: CGFloat = 2
    let size = NSSize(width: 520, height: 150)
    let barHeight: CGFloat = 26
    let iconX: CGFloat = 330
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    appearance.performAsCurrentDrawingAppearance {
        // 바탕 화면과 메뉴바
        let desk = isDark ? NSColor(srgbRed: 0.13, green: 0.15, blue: 0.22, alpha: 1) : NSColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1)
        desk.setFill()
        NSRect(origin: .zero, size: size).fill()
        (isDark ? NSColor(white: 0.12, alpha: 0.92) : NSColor(white: 0.97, alpha: 0.9)).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: barHeight).fill()
        let ink = isDark ? NSColor.white : NSColor.black
        // 다른 메뉴바 아이콘 자리는 둥근 칸으로만, 오른쪽 끝에는 시계를 둔다.
        let clock = "오후 10:30" as NSString
        let clockAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                         .foregroundColor: ink.withAlphaComponent(0.85)]
        let clockWidth = clock.size(withAttributes: clockAttrs).width
        clock.draw(at: NSPoint(x: size.width - 14 - clockWidth, y: 5), withAttributes: clockAttrs)
        var slot = size.width - 14 - clockWidth - 30
        for _ in 0..<3 {
            ink.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: slot, y: 8, width: 14, height: 10), xRadius: 3, yRadius: 3).fill()
            slot -= 28
        }
        ClawdSprite.draw(frame: 3, playing: false, dance: pose, scale: 1, origin: CGPoint(x: iconX - 12, y: 6),
                         noteColor: ink, accent: accent)
        // 말풍선
        let view = BubbleView()
        let layout = BubbleView.layout(for: cue)
        view.frame = NSRect(origin: .zero, size: layout.size)
        view.frozenTime = freeze
        view.noteTime = freeze
        view.cueShownAt = freeze - 2
        var mixed = feeling
        mixed.phase = freeze
        view.feeling = BubbleView.combinedFeeling(for: cue.current, audio: mixed)
        view.cue = cue
        view.isInterlude = cue.isInterlude
        view.isHumming = cue.isHumming
        view.text = layout.current
        view.nextText = layout.next
        view.tailX = layout.size.width / 2
        if let elapsed { view.clock = PlaybackClock(elapsed: elapsed, uptime: freeze, rate: 1) }
        view.appearance = appearance
        cg.saveGState()
        cg.translateBy(x: (iconX - layout.size.width / 2).rounded(), y: barHeight - 2)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        view.draw(view.bounds)
        cg.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 반응 그림 여덟 가지를 한 줄로.
func reactionStrip() -> NSBitmapImageRep {
    let scale: CGFloat = 6, gap: CGFloat = 10
    let cell = NSSize(width: ClawdSprite.canvas.width * scale, height: ClawdSprite.canvas.height * scale)
    let reactions = LyricReaction.allCases
    let size = NSSize(width: CGFloat(reactions.count) * (cell.width + gap) + gap, height: cell.height + gap * 2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .none
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    for (index, reaction) in reactions.enumerated() {
        let pose = DancePose(active: true, hop: index % 2 == 0 ? 1 : 0.3, stepRight: index % 2 == 1, mood: .groove,
                             style: .bounce, danceTime: 1)
        let origin = CGPoint(x: gap + CGFloat(index) * (cell.width + gap), y: gap)
        ClawdSprite.draw(frame: 2 + index, playing: false, dance: pose, scale: scale, origin: origin,
                         noteColor: NSColor(srgbRed: 0.16, green: 0.15, blue: 0.13, alpha: 1),
                         accent: SpriteAccent(reaction: reaction, hook: false), decorations: false)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

MainActor.assumeIsolated {
    let cue = line("너를 처음 만난 그 날처럼", next: "별빛이 내린 밤", start: 10, end: 13, reaction: .love)
    let pose = DancePose(active: true, hop: 1, stepRight: false, mood: .groove, style: .bounce, danceTime: 2)
    var feeling = VocalFeeling.calm
    feeling.wave = 0.4
    feeling.beat = 0.5
    let accent = SpriteAccent(reaction: .love, hook: false)
    write(menuBarScene(appearance: light, cue: cue, elapsed: 11.3, accent: accent, pose: pose, feeling: feeling), "hero-light.png")
    write(menuBarScene(appearance: dark, cue: cue, elapsed: 11.3, accent: accent, pose: pose, feeling: feeling), "hero-dark.png")
}
write(reactionStrip(), "reactions.png")
