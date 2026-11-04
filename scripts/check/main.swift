import Foundation

// 화면 없이 확인할 수 있는 로직을 검사한다. XCTest 없이 명령줄 도구만으로 돈다.
//   scripts/check.sh

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

func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.02) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

// MARK: - 가사 반응

let reactionCases: [(String, LyricReaction?)] = [
    ("사랑해 너를", .love),
    ("I love you so", .love),
    ("이별이 아파", nil),
    ("특별한 밤이야", nil),
    ("별빛이 내린다", .star),
    ("You're my superstar", .star),
    ("Let's start again", nil),
    ("불러줘 내 이름", nil),
    ("불꽃처럼 타올라", .fire),
    ("눈꽃이 피면", .snow),
    ("Over the rainbow", nil),
    ("It's raining again", .tears),
    ("クラブで踊ろう", nil),
    ("花火が上がる", .fire),
    ("岁月如歌", nil),
    ("눈부신 햇살 아래", .sun),
    ("꽃잎이 날려", .flower),
    ("달빛 아래 춤을", .moon),
    ("눈물이 흘러", .tears),
    ("夜空に輝く星", .moon),
    ("오늘도 그냥 걸어", nil),
    ("작별을 말할 때", nil),
    ("결별이 오기 전에", nil),
    ("Fireworks in the sky", .fire),
    ("今天很开心", nil),
    ("小心一点", nil),
    ("我的心在跳", .love),
]
for (text, expected) in reactionCases {
    check(LyricReactionFinder.find(in: text) == expected, "반응 \(text) → \(String(describing: LyricReactionFinder.find(in: text))), 기대 \(String(describing: expected))")
}

let recapLines = ["사랑해 사랑해", "너를 사랑해", "별빛 아래", "그냥 걸어", "사랑이야"]
let recap = LyricInsight.recap(recapLines)
check(recap?.reaction == .love && recap?.count == 4 && recap?.word == "사랑", "곡 기록 \(String(describing: recap))")
check(LyricInsight.recap(["사랑해", "그냥"]) == nil, "두 번 이하는 기록하지 않는다")

// MARK: - 낱말 시각

let worded = LyricInsight.wordMarks("<00:12.00>Hello <00:12.50>world<00:13.00>", offset: 0)
check(worded.text == "Hello world", "낱말 시각을 뗀 글 \(worded.text)")
check(worded.marks.count == 3, "낱말 시각 수 \(worded.marks.count)")
check(near(worded.marks.first?.fraction, 0) && near(worded.marks.last?.fraction, 1) && near(worded.marks[1].fraction, 0.5),
      "낱말 비율 \(worded.marks)")
check(near(worded.marks[1].time, 12.5), "낱말 시각 \(worded.marks[1].time)")
check(LyricInsight.wordMarks("그냥 가사", offset: 0).marks.isEmpty, "시각 없는 줄")

// MARK: - 동기 가사와 노래방 채움

let lrc = """
[00:05.00]첫 번째 줄을 불러요
[00:09.00]두 번째 줄 사랑해
[00:13.00]
[00:15.00]너를 사랑해 영원히
[00:19.00]하늘 위로 날아가
[00:23.00]너를 사랑해 영원히
[00:27.00]하늘 위로 날아가
[00:31.00]마지막 줄이에요
[00:45.00]너를 사랑해 영원히
[00:49.00]하늘 위로 날아가
"""
let song = LyricSong.make(synced: lrc, plain: nil, duration: 60, instrumental: false)
check(song.synced, "동기 가사 표시")
check(song.lines.filter { !$0.text.isEmpty }.count == 9, "줄 수 \(song.lines.count)")
let vocal = song.lines.filter { !$0.text.isEmpty }
check(vocal.allSatisfy { $0.end != nil && $0.end! > $0.time }, "모든 줄에 끝 시각")
if let second = vocal.first(where: { $0.time == 9 }) {
    check(second.end! <= 13.0, "빈 줄 앞에서 끝난다 \(second.end!)")
    check(second.reaction == .love, "줄 반응 \(String(describing: second.reaction))")
}
let hookLines = vocal.filter(\.isHook).map(\.time)
check(hookLines == [15, 19, 23, 27, 45, 49], "후렴 줄 \(hookLines)")
let hookStarts = vocal.filter(\.hookStart).map(\.time)
check(hookStarts == [15, 45], "후렴 시작 \(hookStarts)")
check(song.recap?.reaction == .love && song.recap?.count == 4, "곡 기록 \(String(describing: song.recap))")

// 전주가 길면 간주 음표와 첫 줄 카운트다운.
if let intro = song.cue(at: 2.5) {
    check(intro.isInterlude, "전주는 간주")
    check(near(intro.nextStart, 5), "전주 다음 줄 시각 \(String(describing: intro.nextStart))")
    check(near(intro.countdown(at: 2.5), 2.5), "전주 카운트다운")
}
// 첫 줄을 부르는 중.
if let cue = song.cue(at: 6) {
    check(cue.current == vocal[0].text && !cue.isInterlude, "첫 줄 \(cue.current)")
    check(near(cue.start, 5), "줄 시작 시각")
    let progress = cue.progress(at: 6) ?? -1
    check(progress > 0 && progress < 1, "부르는 중 진행 \(progress)")
    check(cue.progress(at: 4.9) == 0, "시작 전 진행은 0")
    check(cue.progress(at: 8.99) == 1, "다음 줄 직전에는 다 부름")
    check(cue.countdown(at: 6) == nil, "부르는 중에는 카운트다운 없음")
}
// 후렴 줄.
if let cue = song.cue(at: 16) {
    check(cue.isHook && cue.hookStart, "후렴 큐")
}
// 다시 부르는 같은 글은 다른 줄로 본다.
if let a = song.cue(at: 16), let b = song.cue(at: 24) {
    check(a.current == b.current && !a.isSameLine(as: b), "되풀이 줄은 새 줄")
    check(a.isSameLine(as: song.cue(at: 17)!), "같은 줄은 그대로")
}
// 마지막 줄 뒤 후주에는 곡 기록.
if let outro = song.cue(at: 57) {
    check(outro.recap?.reaction == .love, "후주 곡 기록 \(outro)")
}
if let late = song.cue(at: 66) {
    check(late.isInterlude, "곡 기록 뒤에는 간주")
}

// 낱말 시각이 있는 줄은 그 시각을 따라 채운다.
let enhanced = """
[00:10.00]<00:10.00>하나 <00:11.00>둘 <00:13.00>셋<00:14.00>
[00:16.00]다음 줄
"""
let enhancedSong = LyricSong.make(synced: enhanced, plain: nil, duration: 30, instrumental: false)
if let cue = enhancedSong.cue(at: 10.5) {
    check(cue.marks.count == 4, "낱말 표시 \(cue.marks)")
    check(near(cue.end, 14, 0.05), "낱말 끝 시각 \(String(describing: cue.end))")
    let p1 = cue.progress(at: 11) ?? -1
    let p2 = cue.progress(at: 12) ?? -1
    check(near(p1, 0.5, 0.01), "둘째 낱말 시작 \(p1)")
    check(p2 > p1 && p2 < 0.75, "둘째 낱말 중간 \(p2)")
}

// 거의 모든 줄이 되풀이되는 곡은 가장 많이 되풀이되는 줄만 후렴으로 본다.
var loopLRC = ""
let loopLines = ["춤을 춰 춤을 춰요", "밤새도록 춤을 춰", "춤을 춰 춤을 춰요", "밤새도록 춤을 춰",
                 "춤을 춰 춤을 춰요", "새벽까지 달려가", "춤을 춰 춤을 춰요", "새벽까지 달려가"]
for (index, text) in loopLines.enumerated() {
    loopLRC += String(format: "[00:%02d.00]%@\n", 10 + index * 4, text)
}
let loopSong = LyricSong.make(synced: loopLRC, plain: nil, duration: 60, instrumental: false)
let loopHooks = loopSong.lines.filter(\.isHook).map(\.text)
check(!loopHooks.isEmpty && loopHooks.count < loopLines.count, "반복곡 후렴을 다 잡지는 않는다 \(loopHooks)")
check(loopHooks.allSatisfy { $0 == "춤을 춰 춤을 춰요" }, "가장 많이 되풀이되는 줄만 후렴 \(loopHooks)")

// 연주곡은 늘 간주.
let instrumental = LyricSong.make(synced: nil, plain: nil, duration: 200, instrumental: true)
check(instrumental.cue(at: 30)?.isInterlude == true, "연주곡은 간주")

// 낱말 시각이 다음 줄을 넘어가도 다음 줄 전에 끝낸다.
let overflow = """
[00:10.00]<00:10.00>하나 <00:13.00>둘 <00:19.00>셋
[00:14.00]다음 줄
"""
let overflowSong = LyricSong.make(synced: overflow, plain: nil, duration: 30, instrumental: false)
if let end = overflowSong.lines.first(where: { $0.time == 10 })?.end {
    check(end <= 14, "다음 줄 전에 끝난다 \(end)")
}

// 평문 가사는 노래방 채움을 하지 않는다.
let plain = LyricSong.make(synced: nil, plain: "하나 둘\n셋 넷", duration: 20, instrumental: false)
check(!plain.synced, "평문은 동기 아님")
check(plain.cue(at: 1)?.progress(at: 1) == nil, "평문은 진행 없음")

// 부르는 빠르기는 곡마다 잰다.
let rate = LyricInsight.syllableRate(vocal, duration: 60)
check(rate >= 2.2 && rate <= 8.5, "빠르기 \(rate)")

// MARK: - 박 시계

/// 0.5초마다 킥이 들어오는 곡. `missing` 에 든 박은 타격이 묻힌다.
func runClock(seconds: Double, missing: (Int) -> Bool = { _ in false }) -> (BeatClock, [Double]) {
    var clock = BeatClock()
    var beats: [Double] = []
    var last = 0
    let frames = Int(seconds * 60)
    for step in 0..<frames {
        let t = Double(step) / 60
        let kick = step % 30 == 0 && !missing(step / 30)
        clock.ingest(low: kick ? 4e-3 : 2e-4, high: 1e-4, full: kick ? 6e-3 : 5e-4, dt: 1.0 / 60, now: t)
        if clock.beatCount != last {
            beats.append(t)
            last = clock.beatCount
        }
    }
    return (clock, beats)
}

let (steady, steadyBeats) = runClock(seconds: 10)
check(near(steady.tempo, 120, 1), "템포 \(String(describing: steady.tempo))")
check(steadyBeats.count == 20, "킥마다 한 번만 뛴다 \(steadyBeats.count)")
let offGrid = steadyBeats.filter { abs($0 * 2 - ($0 * 2).rounded()) > 0.02 }
check(offGrid.isEmpty, "박보다 먼저 뛰지 않는다 \(offGrid)")

// 네 박에 한 번 타격이 묻혀도 그 자리를 채워 밟고 템포를 지킨다.
let (gappy, gappyBeats) = runClock(seconds: 10, missing: { $0 > 4 && $0 % 4 == 0 })
check(near(gappy.tempo, 120, 1), "묻힌 박이 있어도 템포 \(String(describing: gappy.tempo))")
check(gappyBeats.count >= 19, "묻힌 박을 채운다 \(gappyBeats.count)")
let gappyIntervals = zip(gappyBeats.dropFirst(), gappyBeats).map { $0 - $1 }
check(gappyIntervals.allSatisfy { $0 > 0.45 && $0 < 0.58 }, "채운 박 간격 \(gappyIntervals)")

// 잔잔하다가 저음과 함께 크게 터지면 드롭으로 센다. 고르게 시끄럽기만 하면 세지 않는다.
func runSurge(breakdown: Bool) -> Int {
    var clock = BeatClock()
    for step in 0..<(60 * 40) {
        let t = Double(step) / 60
        let kick = step % 30 == 0
        var low = kick ? 2e-3 : 2e-4, full = kick ? 3e-3 : 4e-4
        if breakdown, t >= 24, t < 28 {
            low = 2e-5
            full = 5e-5
        } else if breakdown, t >= 28 {
            low = kick ? 2e-2 : 2e-3
            full = kick ? 2.6e-2 : 3e-3
        }
        clock.ingest(low: low, high: 1e-4, full: full, dt: 1.0 / 60, now: t)
    }
    return clock.surgeCount
}
check(runSurge(breakdown: true) == 1, "드롭을 한 번 센다 \(runSurge(breakdown: true))")
check(runSurge(breakdown: false) == 0, "고른 곡에서는 드롭이 없다 \(runSurge(breakdown: false))")

// 제목 카드는 판본·영상 꼬리표를 뗀다.
check(LyricMatch.baseTitle("Supernova (Official Video)") == "Supernova", "제목 꼬리표 \(LyricMatch.baseTitle("Supernova (Official Video)"))")
check(LyricMatch.baseTitle("Love Wins All - Official Audio") == "Love Wins All", "제목 꼬리표 2")

// MARK: - 오늘의 리듬

var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let morning = Date(timeIntervalSince1970: 1_793_000_000)
var daily = DailyRhythm(day: "", seconds: 0, beats: 0)
daily = daily.adding(seconds: 30, beats: 60, on: morning, calendar: utc)
check(daily.summary(on: morning, calendar: utc) == nil, "1분이 안 되면 숨긴다")
daily = daily.adding(seconds: 4_300, beats: 8_180, on: morning, calendar: utc)
check(daily.summary(on: morning, calendar: utc) == "오늘 Clawd 와 1시간 12분 동안 8,240박을 탔어요",
      "오늘의 리듬 \(daily.summary(on: morning, calendar: utc) ?? "nil")")
let tomorrow = morning.addingTimeInterval(86_400)
check(daily.summary(on: tomorrow, calendar: utc) == nil, "날짜가 바뀌면 어제 기록은 보이지 않는다")
let fresh = daily.adding(seconds: 90, beats: 120, on: tomorrow, calendar: utc)
check(fresh.beats == 120 && fresh.seconds == 90, "날짜가 바뀌면 새로 센다")

// MARK: - 픽셀 그림·폭죽·전광판

for reaction in LyricReaction.allCases {
    let large = PixelGlyph.large(reaction)
    check(large.rows.allSatisfy { $0.count == large.width } && large.height >= 8 && large.width >= 7,
          "\(reaction) 큰 그림의 줄 길이가 같다")
    let glyph = PixelGlyph.reaction(reaction)
    check(glyph.width == 5 && glyph.height == 5 && glyph.rows.allSatisfy { $0.count == 5 }, "\(reaction) 그림은 5×5")
    check(glyph.pixels.count >= 9, "\(reaction) 그림이 비지 않았다")
}

let burst = ConfettiBurst(originX: 100, originY: 0, scale: 1, count: 40, seed: 7,
                          colors: MoodPalette.of(.groove).confetti, glyph: .love, upward: false)
let early = burst.pieces(at: 0.05)
let later = burst.pieces(at: 1.2)
check(early.count == 40 && later.count == 40, "폭죽 조각 수")
check(burst.pieces(at: ConfettiBurst.lifetime + 0.1).isEmpty, "폭죽은 끝나면 사라진다")
let fell = zip(early, later).filter { $0.1.y > $0.0.y }.count
check(fell >= 36, "폭죽은 아래로 떨어진다 \(fell)")
check(later.contains { $0.glyph == .love }, "반응 그림도 섞어 뿌린다")
check(burst.pieces(at: 0.5) == burst.pieces(at: 0.5), "같은 시각이면 같은 모양")
check(burst.pieces(at: 2.3).allSatisfy { $0.alpha < 0.3 }, "끝날 즈음 흐려진다")
let negativeSeed = ConfettiBurst(originX: 0, originY: 0, scale: 1, count: 12, seed: -5, colors: [.white, .coral], glyph: nil, upward: true)
check(negativeSeed.pieces(at: 0.3).count == 12, "음수 씨앗도 괜찮다")

var meter = SpectrumMeter()
let loud: [Double] = [1e-3, 8e-4, 5e-4, 3e-4, 2e-4, 1e-4, 5e-5, 1e-6]
for step in 0..<120 {
    meter.ingest(loud, dt: 1.0 / 60, now: Double(step) / 60, audible: true)
}
let shown = meter.levels(at: 2.0)
check(shown.count == SpectrumMeter.bandCount, "대역 수")
check(near(shown[0], 1, 0.05), "가장 큰 대역은 꼭대기 \(shown[0])")
check(shown[7] < shown[3] && shown[3] < shown[0], "작은 대역은 낮다 \(shown)")
check(meter.levels(at: 5.0).allSatisfy { $0 < 0.01 }, "소리가 끊기면 내려간다")

check(BeatClock.foldBPM(240) == 120 && BeatClock.foldBPM(60) == 120 && BeatClock.foldBPM(nil) == nil, "BPM 접기")

print("\(passes) 통과, \(failures) 실패")
exit(failures == 0 ? 0 : 1)
