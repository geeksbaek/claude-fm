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
}

func line(_ text: String, next: String?, start: Double, end: Double, reaction: LyricReaction? = nil, hook: Bool = false) -> LyricCue {
    var cue = LyricCue(current: text, next: next)
    cue.start = start
    cue.end = end
    cue.reaction = reaction
    cue.isHook = hook
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

let bubbleCases: [BubbleCase] = [
    BubbleCase(name: "karaoke", cue: line("너를 처음 만난 그 날처럼", next: "별빛이 내린 밤", start: 10, end: 13, reaction: .love),
               elapsed: 11.3),
    BubbleCase(name: "karaoke-two-lines", cue: line("아이 니드 유 투나잇 앤 에브리 나잇 비코즈 유어 마이 온리 원 앤 온리",
                                                    next: "돈트 고", start: 10, end: 16), elapsed: 14.2),
    BubbleCase(name: "hook", cue: line("반짝반짝 빛나는 별처럼", next: "우리 함께라면", start: 30, end: 33, reaction: .star, hook: true),
               elapsed: 31.0, feeling: beatFeeling),
    BubbleCase(name: "countdown", cue: countdownCue, elapsed: 18.4, style: BubbleStyle(karaoke: true, reactions: true, beatPeriod: 0.5)),
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
        view.noteTime = freeze
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
