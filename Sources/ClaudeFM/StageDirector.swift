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

/// 무대 한 편을 이끈다. 창과 TV 가 같은 장면을 그리도록 폭죽·가사 반응·환호·알림을 한곳에서 들고,
/// 그리는 쪽이 부를 때마다 실제로 흐른 시간만큼만 앞으로 간다. 둘이 같이 그려도 시간이 두 번 흐르지 않는다.
/// 폭죽 자리는 판 너비·높이에 대한 비율로 들고 있다가, 그릴 판 크기에 맞춰 편다.
@MainActor
final class StageDirector {
    enum Audience {
        case window
        case tv
    }

    private let snapshot: () -> StageSnapshot
    private(set) var state = StageSnapshot()
    /// 마지막으로 앞으로 간 시각(시스템 가동 시간).
    private(set) var now: TimeInterval = 0
    private var lastAdvance: TimeInterval?
    private var bursts: [StageBurst] = []
    private(set) var shownReaction: LyricReaction?
    private var reactionLevel = 0.0
    private var hookLevel = 0.0
    private var splashLevel = 0.0
    private var cue: LyricCue?
    private var pose = DancePose.idle
    private var live = false
    private var hearing = false
    private var spectrum: [Double] = []
    private var lastCueKey: String?
    private var cueStartedAt: TimeInterval = 0
    private var toastText = ""
    private var toastShownAt: TimeInterval = -10
    private var toastSeconds = 1.8
    private var toastOnTV = true
    private var cheerUntil: TimeInterval = -10
    private var shakeStartedAt: TimeInterval = -10
    private var shakeStrength = 0.0
    private var bannerUntil: TimeInterval = -10
    private var launchIndex = 0
    private var beatCombo = 0
    private var lastLaunch: TimeInterval = -10
    /// 폭죽 조각 수를 정하는 판 너비. 무대 창이 열려 있으면 그 판, 아니면 TV 판(320).
    var referenceWidth = 320

    init(snapshot: @escaping () -> StageSnapshot) {
        self.snapshot = snapshot
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: - 시간

    /// `time` 까지 앞으로 간다. 같은 시각에 또 부르면 아무것도 하지 않는다.
    func advance(to time: TimeInterval) {
        let gap = lastAdvance.map { max(0, time - $0) } ?? 0
        if lastAdvance != nil, gap == 0 { return }
        lastAdvance = time
        now = time
        let dt = min(0.1, gap)
        state = snapshot()
        cue = state.performance?.cue
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

        // 폭죽은 쉬던 동안 흐른 시간까지 다 먹는다. 무대를 다시 열었을 때 지난 폭죽이 되살아나지 않는다.
        bursts = bursts.compactMap { item in
            var item = item
            item.age += gap
            return item.age < ConfettiBurst.lifetime ? item : nil
        }

        live = state.playing || state.pose.showsMotion || state.performance != nil
        pose = state.pose
        if hookLevel > 0.5, pose.active { pose.style = .handsUp }
        // 소리를 못 듣는 동안(권한이 없거나 아주 작을 때)에는 흥얼거리고, 전광판은 잔잔한 물결로 움직인다.
        hearing = state.pose.showsMotion || (state.spectrum.max() ?? 0) > 0.05
        spectrum = state.spectrum
        if live, !hearing {
            spectrum = (0..<SpectrumMeter.bandCount).map { band -> Double in
                let offset = Double(band)
                let slow: Double = sin(time * 2.1 + offset * 0.8)
                let fast: Double = sin(time * 5.3 + offset * 2.1)
                return 0.32 + 0.22 * slow + 0.08 * fast
            }
        }
        let splashing = cue.map { $0.isTitle || $0.recap != nil } ?? false
        splashLevel = splashing ? min(1, splashLevel + dt / 0.35) : max(0, splashLevel - dt / 0.5)

        let key = cue.map { "\($0.current)|\($0.start ?? -1)|\($0.isTitle)|\($0.recap != nil)" }
        if key != lastCueKey {
            lastCueKey = key
            cueStartedAt = time
        }
    }

    // MARK: - 장면

    /// `width`×`height` 판에 그릴 장면.
    func input(width: Int, height: Int) -> StageInput {
        let w = Double(width), h = Double(height)
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
        input.bursts = bursts.map { item in
            var item = item
            item.burst.originX *= w
            item.burst.originY *= h
            return item
        }
        input.hour = Calendar.current.component(.hour, from: Date())
        input.live = live
        input.cheer = cheerUntil > now ? min(1, (cheerUntil - now) / 0.6) : 0
        input.splash = splashLevel
        let splashing = cue.map { $0.isTitle || $0.recap != nil } ?? false
        input.banner = bannerUntil > now && !splashing ? "ENCORE!" : nil
        input.reduceMotion = reduceMotion
        return input
    }

    /// 글자 층. 창에서는 안내(hint)를 따로 얹는다. TV 에는 권한 안내와 창 전용 알림을 띄우지 않는다.
    func hud(for audience: Audience) -> StageHUDView.State {
        var hud = StageHUDView.State()
        hud.palette = MoodPalette.of(pose.mood == .quiet ? .groove : pose.mood)
        hud.cue = cue
        hud.cueAge = now - cueStartedAt
        hud.elapsed = state.performance?.clock?.elapsed(at: now)
        hud.karaoke = state.karaoke
        hud.beatPeriod = state.beatPeriod
        hud.bpm = live ? state.bpm : nil
        hud.moodLabel = live ? state.mood.label : nil
        hud.hop = pose.active ? pose.hop : 0
        if let performance = state.performance {
            hud.title = performance.title
            hud.subtitle = performance.artist
            hud.live = false
        } else if state.playing {
            hud.title = state.radioTitle
            hud.subtitle = "Claude FM"
            hud.live = true
        } else if state.pose.showsMotion {
            hud.title = "지금 나는 소리에 맞춰"
            hud.subtitle = state.mood.caption ?? ""
        }
        hud.idle = !live
        hud.needsPermission = audience == .window && state.needsPermission && !hearing
        if let performance = state.performance, let progress = performance.progress(at: now),
           let position = performance.position, let duration = performance.duration {
            hud.songProgress = progress
            hud.songTime = "\(Self.clockText(min(position.elapsed(at: now), duration))) / \(Self.clockText(duration))"
        }
        let sinceToast = now - toastShownAt
        let showsToast = audience == .window || toastOnTV
        hud.toastLevel = showsToast && sinceToast < toastSeconds ? min(1, (toastSeconds - sinceToast) / 0.3) : 0
        hud.toast = hud.toastLevel > 0 ? toastText : ""
        return hud
    }

    /// 폭죽이 터질 때 0.4초 동안 판 한두 칸만큼 흔든다. 판 칸 단위로 돌려준다.
    func shake(at time: TimeInterval) -> (dx: Double, dy: Double) {
        let age = time - shakeStartedAt
        guard age < 0.4, shakeStrength > 0 else { return (0, 0) }
        let fade = 1 - age / 0.4
        let amount = 1.5 * shakeStrength * fade
        return (sin(age * 90) * amount, cos(age * 71) * amount * 0.6)
    }

    /// 3:07 처럼 분과 초.
    static func clockText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 무대에서 일어나는 일

    private func append(_ burst: ConfettiBurst, age: Double = 0) {
        bursts.append(StageBurst(burst: burst, age: age))
        // 마구 눌러도 무대가 폭죽으로 덮이지 않게 가장 오래된 것부터 거둔다.
        if bursts.count > 24 { bursts.removeFirst(bursts.count - 24) }
    }

    /// 무대 양옆에서 위로 쏘고, 가운데 위에서 쏟아지는 폭죽.
    func burst(reaction: LyricReaction?) {
        let mood = snapshot().mood
        let colors = MoodPalette.of(mood == .quiet ? .groove : mood).confetti
        let seed = Int(ProcessInfo.processInfo.systemUptime * 1000) % 100_000
        // '동작 줄이기'를 켰으면 폭죽을 줄이고 흔들지 않는다.
        let reduceMotion = self.reduceMotion
        let count = max(30, referenceWidth / 6) / (reduceMotion ? 3 : 1)
        append(ConfettiBurst(originX: 0.08, originY: 0.98, scale: 0.9, count: count, seed: seed,
                             colors: colors, glyph: reaction, upward: true))
        append(ConfettiBurst(originX: 0.92, originY: 0.98, scale: 0.9, count: count, seed: seed + 77,
                             colors: colors, glyph: reaction, upward: true))
        append(ConfettiBurst(originX: 0.5, originY: -4.0 / 180, scale: 0.6, count: count, seed: seed + 151,
                             colors: colors, glyph: reaction, upward: false), age: -0.25)
        if !reduceMotion { shake(1) }
        cheer(for: 2.4)
    }

    /// 스페이스로 무대 앞에서 폭죽을 쏜다. 왼쪽 오른쪽을 번갈아 안쪽으로 옮겨 가며 쏘고,
    /// 박에 맞춰 누르면 금빛으로 더 크게 터지고 관객이 더 크게 환호한다.
    func launch() {
        let now = ProcessInfo.processInfo.systemUptime
        let state = snapshot()
        let slots = [0.14, 0.86, 0.3, 0.7, 0.44, 0.56]
        let slot = slots[launchIndex % slots.count]
        launchIndex += 1
        // 박을 잡고 있을 때만 박자를 본다. 박 앞뒤로 한 박의 14% 안이면 맞춘 것으로 친다.
        var onBeat = false
        if state.bpm != nil, let period = state.beatPeriod, period > 0 {
            onBeat = state.beatPhase < 0.14 || state.beatPhase > 0.86
        }
        beatCombo = onBeat ? (now - lastLaunch < 2.5 ? beatCombo + 1 : 1) : 0
        lastLaunch = now
        let palette = MoodPalette.of(state.mood == .quiet ? .groove : state.mood).confetti
        let colors = onBeat ? [RGBColor(0xFFD54A), RGBColor(0xFFF1B8), .white] + palette : palette
        let reduceMotion = self.reduceMotion
        let count = (onBeat ? 36 : 22) / (reduceMotion ? 2 : 1)
        let seed = Int(now * 1000) % 100_000
        append(ConfettiBurst(originX: slot, originY: 0.97, scale: onBeat ? 0.85 : 0.6, count: count, seed: seed, colors: colors,
                             glyph: shownReaction ?? (onBeat ? .star : nil), upward: true))
        cheer(for: onBeat ? 1.6 : 0.9)
        if onBeat, beatCombo >= 4, !reduceMotion { shake(0.45) }
        if [4, 8, 16, 32, 64].contains(beatCombo) { toast("박자 딱! ×\(beatCombo)") }
    }

    /// 무대를 누른 자리(판 너비·높이에 대한 비율)에서 폭죽이 솟는다.
    func confetti(atX x: Double, y: Double) {
        let mood = snapshot().mood
        let seed = Int(ProcessInfo.processInfo.systemUptime * 1000) % 100_000
        append(ConfettiBurst(originX: x, originY: y, scale: 0.55, count: 26, seed: seed,
                             colors: MoodPalette.of(mood == .quiet ? .groove : mood).confetti,
                             glyph: shownReaction, upward: true))
        cheer(for: 1.4)
    }

    /// 가사 싱크를 옮긴 것은 무대 창에서 누른 사람만 보면 된다.
    func flashSync(_ offset: Double) {
        let text = abs(offset) < 0.05 ? "가사 싱크 맞춤" : String(format: "가사 %@ %.1f초", offset > 0 ? "늦게" : "빠르게", abs(offset))
        toast(text, onTV: false)
    }

    /// 잠깐 떴다 사라지는 알림. `onTV` 가 false 면 무대 창에만 띄운다.
    func toast(_ text: String, onTV: Bool = true, seconds: TimeInterval = 1.8) {
        toastText = text
        toastShownAt = ProcessInfo.processInfo.systemUptime
        toastOnTV = onTV
        toastSeconds = max(0.6, seconds)
    }

    /// 곡이 끝까지 흐르면 관객이 환호하고, 다음 곡이 없으면 전광판에 ENCORE 를 띄운다.
    func encore(banner: Bool) {
        cheer(for: 3.2)
        if banner { bannerUntil = ProcessInfo.processInfo.systemUptime + 3.6 }
    }

    /// 무대가 쿵 하고 짧게 흔들린다.
    private func shake(_ strength: Double) {
        shakeStartedAt = ProcessInfo.processInfo.systemUptime
        shakeStrength = strength
    }

    private func cheer(for seconds: TimeInterval) {
        cheerUntil = max(cheerUntil, ProcessInfo.processInfo.systemUptime + seconds)
    }
}
