import Foundation

/// 한 시점에 부를 가사 한 줄. `text` 는 이미 한글 발음이고, 빈 문자열은 숨 고르는 간격이다.
struct LyricLine: Equatable {
    var time: TimeInterval
    var text: String
    /// 발음으로 바꾸기 전 원문. 무대에서 작게 같이 보여 준다.
    var original = ""
    /// 이 줄을 다 부르는 곡 시각(추정). 동기 가사에서만 있다.
    var end: TimeInterval?
    /// 낱말마다 시각이 적힌 가사(`<mm:ss.xx>`)에서 읽은 진행 표시.
    var marks: [LyricMark] = []
    var reaction: LyricReaction?
    /// 곡에서 되풀이되는 후렴 줄.
    var isHook = false
    /// 후렴 덩어리의 첫 줄.
    var hookStart = false

    init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

/// 지금 부르는 가사와 다음에 올 가사 한 쌍.
struct LyricCue: Equatable {
    static let interludeToken = "♪ ♫ ♬"
    static let hummingToken = "♪ ~ ♫ ~ ♬"
    var current: String
    var next: String?
    var isInterlude = false
    var isHumming = false
    /// 곡이 바뀌었을 때 잠깐 보여 주는 제목 카드. `current` 는 제목, `next` 는 가수.
    var isTitle = false
    /// 후주에 보여 주는 곡 기록.
    var recap: LyricRecap?
    /// 지금 줄을 부르기 시작하는 곡 시각. 동기 가사에서만 있다.
    var start: TimeInterval?
    /// 지금 줄을 다 부르는 곡 시각(추정).
    var end: TimeInterval?
    var marks: [LyricMark] = []
    /// 다음 줄이 시작하는 곡 시각. 간주 끝 카운트다운에 쓴다.
    var nextStart: TimeInterval?
    var original = ""
    var reaction: LyricReaction?
    var isHook = false
    var hookStart = false

    init(current: String, next: String?, isInterlude: Bool = false, isHumming: Bool = false) {
        self.current = current
        self.next = next
        self.isInterlude = isInterlude
        self.isHumming = isHumming
    }

    static func interlude(next: String? = nil) -> LyricCue {
        LyricCue(current: interludeToken, next: next, isInterlude: true)
    }

    static func humming() -> LyricCue {
        LyricCue(current: hummingToken, next: nil, isHumming: true)
    }

    static func title(_ title: String, artist: String) -> LyricCue {
        var cue = LyricCue(current: title, next: artist.isEmpty ? nil : artist)
        cue.isTitle = true
        return cue
    }

    static func recap(_ recap: LyricRecap) -> LyricCue {
        var cue = LyricCue(current: recap.headline, next: recap.caption)
        cue.recap = recap
        cue.reaction = recap.reaction
        return cue
    }

    /// 글자는 같아도 다시 부르는 줄이면 다른 줄로 본다. 말풍선이 새 줄로 넘기는 기준이다.
    func isSameLine(as other: LyricCue) -> Bool {
        current == other.current && isInterlude == other.isInterlude && isHumming == other.isHumming
            && isTitle == other.isTitle && (recap == nil) == (other.recap == nil) && start == other.start
    }

    /// 노래방처럼 지금 줄을 얼마나 불렀는지(0...1). 시각을 모르면 nil.
    func progress(at elapsed: TimeInterval) -> Double? {
        guard let start, let end, end > start, !isInterlude, !isHumming, !isTitle, recap == nil else { return nil }
        if elapsed <= start { return 0 }
        if elapsed >= end { return 1 }
        var times = [start]
        var fractions = [0.0]
        for mark in marks where mark.time > times[times.count - 1] && mark.time < end {
            times.append(mark.time)
            fractions.append(max(fractions[fractions.count - 1], min(1, mark.fraction)))
        }
        times.append(end)
        fractions.append(1)
        for index in 1..<times.count where elapsed <= times[index] {
            let span = times[index] - times[index - 1]
            guard span > 0 else { return fractions[index] }
            let t = (elapsed - times[index - 1]) / span
            return fractions[index - 1] + (fractions[index] - fractions[index - 1]) * t
        }
        return 1
    }

    /// 다음 줄(또는 아직 시작하지 않은 지금 줄)까지 남은 초. 간주 끝 카운트다운에 쓴다.
    func countdown(at elapsed: TimeInterval) -> TimeInterval? {
        if isInterlude, let nextStart, nextStart > elapsed { return nextStart - elapsed }
        if !isInterlude, !isHumming, !isTitle, recap == nil, let start, start > elapsed { return start - elapsed }
        return nil
    }
}

/// 곡 시각을 시스템 시각에 잇는다. 그릴 때마다 지금 곡 시각을 다시 구해 노래방 채움이 매끄럽게 흐른다.
struct PlaybackClock: Equatable {
    /// `uptime` 에서의 곡 시각.
    var elapsed: TimeInterval
    var uptime: TimeInterval
    var rate: Double

    func elapsed(at now: TimeInterval) -> TimeInterval {
        elapsed + rate * (now - uptime)
    }
}

/// 지금 곡에서 보여 줄 한 장면. 말풍선과 무대가 같이 쓴다.
struct LyricPerformance: Equatable {
    var cue: LyricCue
    /// 동기 가사일 때만 있다.
    var clock: PlaybackClock?
    var title: String
    var artist: String
}

struct LyricSong: Equatable {
    var instrumental: Bool
    var lines: [LyricLine]
    /// 시각이 적힌 가사인지. 평문을 길이에 맞춰 펼친 가사는 노래방 채움을 하지 않는다.
    var synced = false
    var recap: LyricRecap?

    init(instrumental: Bool, lines: [LyricLine], synced: Bool = false, recap: LyricRecap? = nil) {
        self.instrumental = instrumental
        self.lines = lines
        self.synced = synced
        self.recap = recap
    }

    func text(at elapsed: TimeInterval) -> String? {
        guard let cue = cue(at: elapsed), !cue.isInterlude, !cue.isHumming else { return nil }
        return cue.current
    }

    func cue(at elapsed: TimeInterval) -> LyricCue? {
        if instrumental {
            return .interlude()
        }
        guard let firstIndex = lines.firstIndex(where: { !$0.text.isEmpty }) else { return nil }
        let firstLine = lines[firstIndex]
        let secondLine = lines[(firstIndex + 1)...].first(where: { !$0.text.isEmpty })

        var latestIndex: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= elapsed + 0.12 {
                latestIndex = index
            } else {
                break
            }
        }
        let upcoming = lines.first(where: { $0.time > elapsed + 0.12 && !$0.text.isEmpty })

        // 첫 소절 시작 전 구간: 전주가 짧거나(3.8초 이하) 첫 소절이 곧 시작될 때(0.85초 이내)는 첫 소절을 바로 보여준다.
        if latestIndex == nil || latestIndex! < firstIndex {
            if firstLine.time <= 3.8 || firstLine.time - elapsed <= 0.85 {
                return sung(firstLine, next: secondLine)
            }
            return interlude(before: firstLine)
        }

        let idx = latestIndex!
        let activeLine = lines[idx]
        if activeLine.text.isEmpty {
            if let prevVocalIndex = lines[..<idx].lastIndex(where: { !$0.text.isEmpty }) {
                let prevLine = lines[prevVocalIndex]
                if let upcoming {
                    let emptyGap = upcoming.time - activeLine.time
                    let totalGap = upcoming.time - prevLine.time
                    // 숨 고르기 수준의 짧은 빈 줄(3.5초 미만)에서는 직전 소절이 끊기지 않게 유지한다.
                    if emptyGap < 3.5 && totalGap < 6.0 {
                        return sung(prevLine, next: upcoming)
                    }
                }
            }
            return interlude(before: upcoming)
        }

        let nextLine = lines[(idx + 1)...].first(where: { !$0.text.isEmpty })
        let sungElapsed = elapsed - activeLine.time
        if let nextLine {
            let gap = nextLine.time - activeLine.time
            if gap >= 10.0, sungElapsed >= 6.0 {
                // 다음 가사까지 간격이 긴 간주 구간이면 다음 가사가 시작될 때까지 음표가 흐른다.
                return interlude(before: nextLine)
            }
        } else if sungElapsed >= 7.0 {
            // 마지막 가사가 끝난 뒤 후주 구간에서는 곡에서 가장 많이 부른 말을 잠깐 보여 주고 음표가 흐른다.
            if let recap, sungElapsed < 15.0 { return .recap(recap) }
            return .interlude()
        }
        return sung(activeLine, next: nextLine)
    }

    private func sung(_ line: LyricLine, next: LyricLine?) -> LyricCue {
        var cue = LyricCue(current: line.text, next: next?.text)
        cue.original = line.original
        cue.reaction = line.reaction
        cue.isHook = line.isHook
        cue.hookStart = line.hookStart
        if synced {
            cue.start = line.time
            cue.end = line.end
            cue.marks = line.marks
            cue.nextStart = next?.time
        }
        return cue
    }

    private func interlude(before line: LyricLine?) -> LyricCue {
        var cue = LyricCue.interlude(next: line?.text)
        if synced { cue.nextStart = line?.time }
        return cue
    }

    /// 동기 가사가 있으면 그 시각을 쓰고, 없으면 길이에 맞춰 평문을 펼친다.
    static func make(synced: String?, plain: String?, duration: TimeInterval?, instrumental: Bool) -> LyricSong {
        if instrumental { return LyricSong(instrumental: true, lines: []) }
        if let synced, let song = parseSynced(synced, duration: duration), song.lines.contains(where: { !$0.text.isEmpty }) {
            return song
        }
        return parsePlain(plain ?? "", duration: duration)
    }
}

extension LyricSong {
    fileprivate static func parseSynced(_ raw: String, duration: TimeInterval?) -> LyricSong? {
        let source = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var offset = 0.0
        if let match = offsetPattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range(at: 1), in: source),
           let milliseconds = Double(source[range]) {
            offset = milliseconds / 1000
        }
        var rows: [(time: TimeInterval, text: String)] = []
        var marksByTime: [TimeInterval: [LyricMark]] = [:]
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let ns = line as NSString
            let matches = timePattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }
            guard let last = matches.last else { continue }
            let start = last.range.location + last.range.length
            var text = start < ns.length ? ns.substring(from: start) : ""
            let worded = LyricInsight.wordMarks(text, offset: offset)
            text = wordTimePattern.stringByReplacingMatches(in: worded.text, range: NSRange(worded.text.startIndex..., in: worded.text), withTemplate: "")
            if isCreditOrSectionLine(text) { continue }
            text = sanitize(text)
            for match in matches {
                guard let time = timestamp(ns, match) else { continue }
                rows.append((time: time + offset, text: text))
                // 낱말 시각은 첫 타임스탬프 줄에만 맞는다. 같은 줄을 여러 시각에 되풀이하면 쓰지 않는다.
                if matches.count == 1, !worded.marks.isEmpty, !text.isEmpty, marksByTime[time + offset] == nil {
                    marksByTime[time + offset] = worded.marks
                }
            }
        }
        guard !rows.isEmpty else { return nil }
        rows.sort { $0.time < $1.time }
        let kanaSong = rows.reduce(0) { $0 + LyricScript.kanaCount($1.text) } >= 8
        let filtered = mergeSameTimeRows(LyricScript.keepingMainLanguage(rows))
        var lines = filtered.map { row -> LyricLine in
            var line = LyricLine(time: row.time, text: row.text.isEmpty ? "" : HangulReading.line(row.text, preferJapanese: kanaSong))
            if !line.text.isEmpty {
                line.original = row.text
                line.reaction = LyricReactionFinder.find(in: row.text)
                line.marks = marksByTime[row.time] ?? []
            }
            return line
        }
        LyricInsight.estimateEnds(&lines, duration: duration)
        LyricInsight.markHooks(&lines)
        let recap = LyricInsight.recap(filtered.map(\.text))
        return LyricSong(instrumental: false, lines: lines, synced: true, recap: recap)
    }

    fileprivate static func parsePlain(_ raw: String, duration: TimeInterval?) -> LyricSong {
        var rows = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map(sanitize)
        while rows.last?.isEmpty == true, !rows.isEmpty {
            rows.removeLast()
        }
        guard !rows.isEmpty else { return LyricSong(instrumental: false, lines: []) }
        let step: TimeInterval
        if let duration, duration > 1 {
            step = duration / Double(rows.count)
        } else {
            step = 4
        }
        let kanaSong = rows.reduce(0) { $0 + LyricScript.kanaCount($1) } >= 8
        let texts = LyricScript.keepingMainLanguage(rows)
        var lines = texts.enumerated().map { index, text -> LyricLine in
            var line = LyricLine(time: Double(index) * step, text: text.isEmpty ? "" : HangulReading.line(text, preferJapanese: kanaSong))
            if !line.text.isEmpty {
                line.original = text
                line.reaction = LyricReactionFinder.find(in: text)
            }
            return line
        }
        LyricInsight.markHooks(&lines)
        return LyricSong(instrumental: false, lines: lines, synced: false, recap: LyricInsight.recap(texts))
    }

    /// LRC 끝에 붙는 `^` 표기나 기호만 있는 줄, 또는 `(간주)`·`[Instrumental]` 같은 간주 표기 줄을 정리한다.
    fileprivate static func sanitize(_ raw: String) -> String {
        var text = raw
        for caret in ["^", "＾", "ˆ", "‸", "⌃", "︿"] {
            text = text.replacingOccurrences(of: caret, with: " ")
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/／|｜·・^＾"))
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return "" }
        if isInterludeMarker(text) { return "" }
        return text
    }

    private static let interludeWords: Set<String> = [
        "간주", "간주중", "간주 중", "전주", "후주", "연주", "연주중", "연주 중",
        "instrumental", "interlude", "intro", "outro", "music", "inst",
        "solo", "guitar solo", "piano solo", "drum solo", "bass solo", "sax solo", "synth solo",
        "dance break", "break", "bgm", "間奏", "前奏", "後奏",
    ]

    private static let creditPrefixes: [String] = [
        "作词", "作曲", "编曲", "制作", "作詞", "編曲", "작사", "작곡", "편곡",
        "lyrics by", "lyricist", "composed by", "composer", "arranged by", "produced by",
    ]

    private static let sectionLabels: Set<String> = [
        "verse", "verse 1", "verse 2", "verse 3", "verse 4",
        "chorus", "pre-chorus", "prechorus", "post-chorus", "postchorus",
        "bridge", "hook", "refrain",
    ]

    /// 작사·작곡 크레딧이나 `[Verse]`, `[Chorus]` 같은 구간 헤더 줄은 빈 간주 줄로 바뀌어 첫 소절을 가리지 않게 아예 건너뛴다.
    fileprivate static func isCreditOrSectionLine(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let stripped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]［］{}<>「」『』 "))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        for prefix in creditPrefixes {
            if stripped.hasPrefix(prefix), stripped.contains(":") || stripped.contains("：") {
                return true
            }
        }
        let hasBrackets = (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            || (trimmed.hasPrefix("［") && trimmed.hasSuffix("］"))
        if hasBrackets, sectionLabels.contains(stripped) {
            return true
        }
        return false
    }

    private static func isInterludeMarker(_ text: String) -> Bool {
        let stripped = text
            .trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]［］{}<>「」『』~～-—–·・*＊♪♫♬♩.…!！?？ "))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        if interludeWords.contains(stripped) { return true }
        if isCreditOrSectionLine(text) { return true }
        let hasBrackets = (text.hasPrefix("(") && text.hasSuffix(")"))
            || (text.hasPrefix("（") && text.hasSuffix("）"))
            || (text.hasPrefix("[") && text.hasSuffix("]"))
            || (text.hasPrefix("［") && text.hasSuffix("］"))
        if hasBrackets {
            for word in ["간주", "전주", "후주", "instrumental", "interlude", "間奏"] where stripped.contains(word) {
                return true
            }
        }
        return false
    }

    /// 같은 시각에 두 줄(예: 영어 코러스와 일본어 본문)이 함께 있으면 덮어쓰여 사라지지 않게 합친다.
    private static func mergeSameTimeRows(_ rows: [(time: TimeInterval, text: String)]) -> [(time: TimeInterval, text: String)] {
        var merged: [(time: TimeInterval, text: String)] = []
        for row in rows {
            if let lastIndex = merged.indices.last, abs(merged[lastIndex].time - row.time) <= 0.05 {
                if merged[lastIndex].text.isEmpty {
                    merged[lastIndex].text = row.text
                } else if !row.text.isEmpty, merged[lastIndex].text != row.text {
                    merged[lastIndex].text += " " + row.text
                }
            } else {
                merged.append(row)
            }
        }
        return merged
    }

    private static func timestamp(_ line: NSString, _ match: NSTextCheckingResult) -> TimeInterval? {
        func part(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return line.substring(with: range)
        }
        guard let minutes = part(1).flatMap(Double.init), let seconds = part(2).flatMap(Double.init) else { return nil }
        var fraction = 0.0
        if let digits = part(3), let value = Double(digits) {
            switch digits.count {
            case 3: fraction = value / 1000
            case 2: fraction = value / 100
            default: fraction = value / 10
            }
        }
        return minutes * 60 + seconds + fraction
    }

    private static let timePattern = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    private static let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#, options: [.caseInsensitive])
    private static let wordTimePattern = try! NSRegularExpression(pattern: #"<[^>]+>"#)
}

/// 한 줄에 원문과 번역이 같이 있으면 곡에서 줄 수가 가장 많은 언어만 남긴다.
/// 가사 중간에 섞인 짧은 다른 언어 단어는 실제로 부르는 말로 보고 둔다.
private enum LyricScript {
    private enum Language {
        case korean, japanese, chinese, latin
    }

    private struct Run {
        var language: Language
        var text: String
    }

    static func kanaCount(_ text: String) -> Int {
        count(text, isKana)
    }

    static func keepingMainLanguage(_ lines: [String]) -> [String] {
        let kanaSong = lines.reduce(0) { $0 + count($1, isKana) } >= 8
        guard let main = dominant(lines, kanaSong: kanaSong) else { return lines }
        guard translationSong(lines, main: main, kanaSong: kanaSong) else { return lines }
        return lines.map { strip($0, main: main, kanaSong: kanaSong) }
    }

    /// 일본어·한국어 곡에 섞인 영어(라틴 문자)는 번역이 아니라 실제 부르는 가사로 유지한다.
    private static func isTranslationLanguage(_ candidate: Language, main: Language) -> Bool {
        guard candidate != main else { return false }
        if (main == .japanese || main == .korean) && candidate == .latin {
            return false
        }
        return true
    }

    /// 줄마다 같은 방향으로 번역이 붙어 있으면 번역 가사로 본다.
    /// 영어와 일본어가 왔다 갔다 하면 둘 다 부르는 곡이므로 그대로 둔다.
    private static func translationSong(_ lines: [String], main: Language, kanaSong: Bool) -> Bool {
        var suffix = 0
        var prefix = 0
        var messy = 0
        for line in lines {
            let runs = segment(line, kanaSong: kanaSong)
            guard runs.contains(where: { !isTranslationLanguage($0.language, main: main) }) else { continue }
            let foreign = runs.enumerated().filter {
                isTranslationLanguage($0.element.language, main: main) && isParallel($0.element)
            }
            guard !foreign.isEmpty else { continue }
            if foreign.count > 1 {
                messy += 1
                continue
            }
            let index = foreign[0].offset
            if index == runs.count - 1 {
                suffix += 1
            } else if index == 0 {
                prefix += 1
            } else {
                messy += 1
            }
        }
        let edge = max(suffix, prefix)
        let other = min(suffix, prefix) + messy
        return edge >= 1 && edge >= other * 3 && (other == 0 || edge >= 3)
    }

    static func keepingMainLanguage(_ rows: [(time: TimeInterval, text: String)]) -> [(time: TimeInterval, text: String)] {
        let source = rows.map(\.text)
        let kanaSong = source.reduce(0) { $0 + count($1, isKana) } >= 8
        let lead = leadLines(rows)
        guard let main = dominant(lead, kanaSong: kanaSong) ?? dominant(source, kanaSong: kanaSong) else {
            return rows
        }
        let texts = translationSong(source, main: main, kanaSong: kanaSong)
            ? source.map { strip($0, main: main, kanaSong: kanaSong) }
            : source
        let paired = zip(rows, texts).map { (time: $0.0.time, text: $0.1) }
        var drop = Set<Int>()
        for index in paired.indices {
            let text = paired[index].text
            guard text.contains(where: \.isLetter),
                  !containsKeptLanguage(main: main, text: text, kanaSong: kanaSong) else { continue }
            let time = paired[index].time
            let besideMain = paired.indices.contains { other in
                other != index && abs(paired[other].time - time) <= 0.25
                    && containsKeptLanguage(main: main, text: paired[other].text, kanaSong: kanaSong)
            }
            if besideMain { drop.insert(index) }
        }
        return paired.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
    }

    private static func leadLines(_ rows: [(time: TimeInterval, text: String)]) -> [String] {
        var out: [String] = []
        var lastTime: TimeInterval?
        for row in rows where row.text.contains(where: \.isLetter) {
            if let prev = lastTime, abs(row.time - prev) <= 0.25 { continue }
            out.append(row.text)
            lastTime = row.time
        }
        return out
    }

    private static func dominant(_ lines: [String], kanaSong: Bool) -> Language? {
        var votes: [Language: Int] = [:]
        for line in lines {
            guard let vote = vote(line, kanaSong: kanaSong) else { continue }
            votes[vote, default: 0] += 1
        }
        return votes.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return rank(lhs.key) > rank(rhs.key)
        }?.key
    }

    /// 줄 맨 앞의 짧은 라틴 단어 하나는 건너뛰고, 그 다음 글자를 그 줄의 언어로 센다.
    private static func vote(_ line: String, kanaSong: Bool) -> Language? {
        let runs = segment(line, kanaSong: kanaSong)
        for (index, run) in runs.enumerated() {
            if run.language == .latin, latinWords(run.text) == 1, latinLetters(run.text) < 8, index + 1 < runs.count {
                continue
            }
            return run.language
        }
        return runs.first?.language
    }

    private static func strip(_ line: String, main: Language, kanaSong: Bool) -> String {
        let runs = segment(line, kanaSong: kanaSong)
        guard runs.contains(where: { !isTranslationLanguage($0.language, main: main) }) else { return line }
        let kept = runs.filter { !isTranslationLanguage($0.language, main: main) || !isParallel($0) }
        guard kept.count != runs.count else { return line }
        return cleanup(kept.map(\.text).joined())
    }

    /// 번역으로 볼 만큼 긴 다른 언어 덩어리만 뺀다. 같은 말만 되풀이하는 후렴구는 남긴다.
    private static func isParallel(_ run: Run) -> Bool {
        switch run.language {
        case .latin:
            return latinWords(run.text) >= 3 && distinctLatinWords(run.text) >= 3
        case .korean, .japanese, .chinese:
            return count(run.text, letter(of: run.language)) >= 2
        }
    }

    private static func containsKeptLanguage(main: Language, text: String, kanaSong: Bool) -> Bool {
        segment(text, kanaSong: kanaSong).contains { !isTranslationLanguage($0.language, main: main) }
    }

    private static func segment(_ line: String, kanaSong: Bool) -> [Run] {
        let lineHasKana = line.contains(where: isKana)
        let openers: Set<Character> = ["(", "（", "[", "［", "「", "『"]
        var runs: [Run] = []
        var neutral = ""
        for char in line {
            guard let language = language(of: char, lineHasKana: lineHasKana, kanaSong: kanaSong) else {
                neutral.append(char)
                continue
            }
            if let index = runs.indices.last, runs[index].language == language {
                runs[index].text += neutral + String(char)
            } else if let index = runs.indices.last {
                if let open = neutral.firstIndex(where: { openers.contains($0) }) {
                    runs[index].text += String(neutral[..<open])
                    runs.append(Run(language: language, text: String(neutral[open...]) + String(char)))
                } else {
                    runs[index].text += neutral
                    runs.append(Run(language: language, text: String(char)))
                }
            } else {
                runs.append(Run(language: language, text: neutral + String(char)))
            }
            neutral = ""
        }
        if !neutral.isEmpty, let index = runs.indices.last {
            runs[index].text += neutral
        }
        return runs
    }

    private static func language(of char: Character, lineHasKana: Bool, kanaSong: Bool) -> Language? {
        if isHangul(char) { return .korean }
        if isKana(char) { return .japanese }
        if isHan(char) { return (lineHasKana || kanaSong) ? .japanese : .chinese }
        if isLatinLetter(char) { return .latin }
        return nil
    }

    private static func letter(of language: Language) -> (Character) -> Bool {
        switch language {
        case .korean: return isHangul
        case .japanese: return { isKana($0) || isHan($0) }
        case .chinese: return isHan
        case .latin: return isLatinLetter
        }
    }

    private static func cleanup(_ text: String) -> String {
        var value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let empties = ["()", "（）", "[]", "［］", "「」", "『』"]
        var changed = true
        while changed {
            changed = false
            for empty in empties where value.contains(empty) {
                value = value.replacingOccurrences(of: empty, with: " ")
                changed = true
            }
            let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if collapsed != value {
                value = collapsed
                changed = true
            }
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/／|｜·・^＾ˆ‸⌃︿"))
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains(where: \.isLetter) ? value : ""
    }

    private static func latinWords(_ text: String) -> Int {
        latinWordList(text).count
    }

    private static func distinctLatinWords(_ text: String) -> Int {
        Set(latinWordList(text)).count
    }

    private static func latinWordList(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for char in text where char.unicodeScalars.allSatisfy(\.isASCII) {
            if isLatinLetter(char) {
                current.append(contentsOf: char.lowercased())
            } else if (char == "'" || char == "’"), !current.isEmpty {
                current.append("'")
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func latinLetters(_ text: String) -> Int {
        text.reduce(0) { $0 + (isLatinLetter($1) ? 1 : 0) }
    }

    private static func count(_ text: String, _ match: (Character) -> Bool) -> Int {
        text.reduce(0) { $0 + (match($1) ? 1 : 0) }
    }

    private static func rank(_ language: Language) -> Int {
        switch language {
        case .korean: return 0
        case .japanese: return 1
        case .chinese: return 2
        case .latin: return 3
        }
    }

    private static func isHangul(_ char: Character) -> Bool {
        char.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(scalar.value)
                || (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
        }
    }

    private static func isKana(_ char: Character) -> Bool {
        char.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    private static func isHan(_ char: Character) -> Bool {
        char.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func isLatinLetter(_ char: Character) -> Bool {
        char.isLetter && char.unicodeScalars.allSatisfy(\.isASCII)
    }
}

/// 크롬이 알려 주는 제목·가수와 LRCLIB 기록을 비교한다.
/// 유튜브 뮤직은 `곡 (7" Version)`, `가수 (LATIN)` 처럼 판본과 다른 표기를 붙인다.
enum LyricMatch {
    static func titleVariants(_ title: String) -> [String] {
        var variants = [title]
        let base = baseTitle(title)
        if !base.isEmpty, base.caseInsensitiveCompare(title) != .orderedSame {
            variants.append(base)
        }
        return variants
    }

    static func artistVariants(_ artist: String) -> [String] {
        var variants: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !variants.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            variants.append(trimmed)
        }
        add(artist)
        let ns = artist as NSString
        for match in aliasPattern.matches(in: artist, range: NSRange(location: 0, length: ns.length)) {
            for index in 1..<match.numberOfRanges {
                let range = match.range(at: index)
                if range.location != NSNotFound { add(ns.substring(with: range)) }
            }
        }
        add(aliasPattern.stringByReplacingMatches(
            in: artist,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: " "
        ))
        if artist.contains("&") { add(artist.replacingOccurrences(of: "&", with: "and")) }
        return variants
    }

    static func baseTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for pattern in [suffixPattern, noisePattern] {
                let range = NSRange(location: 0, length: (text as NSString).length)
                let next = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if next != text, !next.isEmpty {
                    text = next
                    changed = true
                }
            }
        }
        return text
    }

    /// 맞으면 점수, 다른 곡이면 nil.
    static func score(
        title: String,
        artist: String,
        duration: Double?,
        synced: Bool,
        wantedTitle: String,
        wantedArtist: String,
        wantedDuration: TimeInterval?
    ) -> Double? {
        guard titlesMatch(title, wantedTitle) else { return nil }
        if !wantedArtist.isEmpty, !artistsMatch(artist, wantedArtist) { return nil }
        var score = normalize(title) == normalize(wantedTitle) ? 10.0 : 4.0
        if !wantedArtist.isEmpty {
            score += normalize(artist) == normalize(wantedArtist) ? 10 : 4
        }
        if let wantedDuration, let duration {
            let gap = abs(duration - wantedDuration)
            if gap > 15, gap / max(wantedDuration, 1) > 0.08 { return nil }
            score += max(0, 8 - gap)
        }
        if synced { score += 2 }
        return score
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func titlesMatch(_ record: String, _ wanted: String) -> Bool {
        if normalize(record) == normalize(wanted) { return true }
        let base = normalize(baseTitle(record))
        let wantedBase = normalize(baseTitle(wanted))
        return !base.isEmpty && base == wantedBase
    }

    private static func artistsMatch(_ record: String, _ wanted: String) -> Bool {
        let recordName = normalize(record)
        let wantedName = normalize(wanted)
        if recordName.isEmpty || wantedName.isEmpty { return false }
        if recordName == wantedName || recordName.contains(wantedName) || wantedName.contains(recordName) { return true }
        let recordTokens = tokens(recordName)
        let wantedTokens = tokens(wantedName)
        if recordTokens == wantedTokens { return true }
        let smaller = recordTokens.count < wantedTokens.count ? recordTokens : wantedTokens
        let larger = recordTokens.count < wantedTokens.count ? wantedTokens : recordTokens
        return smaller.count >= 2 && smaller.isSubset(of: larger)
    }

    private static func tokens(_ name: String) -> Set<String> {
        Set(name.split(separator: " ").map(String.init).filter { !stopwords.contains($0) })
    }

    private static let stopwords: Set<String> = ["a", "an", "and", "feat", "featuring", "ft", "of", "the"]
    private static let aliasPattern = try! NSRegularExpression(pattern: #"\(([^)]+)\)|（([^）]+)）"#)
    private static let suffixPattern = try! NSRegularExpression(pattern: #"\s*[\(（\[][^\)）\]]*[\)）\]]\s*$"#)
    private static let noisePattern = try! NSRegularExpression(
        pattern: #"\s*[-|–—]\s*(official\s+(video|audio|music\s+video)|lyrics?|lyric\s+video|audio|topic)\s*$"#,
        options: [.caseInsensitive]
    )
}

/// LRCLIB 에서 가사를 찾는다. 응답은 메모리에만 두고 디스크 캐시는 쓰지 않는다.
actor LyricLibrary {
    static let shared = LyricLibrary()

    private struct Record: Decodable {
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    private enum Entry {
        case song(LyricSong)
        case missing
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.httpAdditionalHeaders = ["User-Agent": "Claude FM 1.0"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func song(title: String, artist: String, album: String, duration: TimeInterval?) async -> LyricSong? {
        let key = cacheKey(title: title, artist: artist)
        if let entry = entries[key] {
            if case .song(let song) = entry { return song }
            return nil
        }
        let found = await fetch(title: title, artist: artist, album: album, duration: duration)
        switch found {
        case .song(let song):
            store(song, for: key)
            return song
        case .missing:
            storeMissing(for: key)
            return nil
        case .failed:
            return nil
        }
    }

    private enum Fetch: Sendable {
        case song(LyricSong)
        case missing
        case failed
    }

    private func fetch(title: String, artist: String, album: String, duration: TimeInterval?) async -> Fetch {
        // LRCLIB 자체 DB를 바로 조회하는 search를 먼저 호출해 외부 업스트림 503 지연을 피하고, 없을 때만 get을 시도한다.
        let searched = await search(title: title, artist: artist, duration: duration)
        if case .song = searched {
            return searched
        }
        if let duration, duration > 1,
           case .records(let records) = await request(getURL(title: title, artist: artist, album: album, duration: duration), retryOnBusy: false),
           let record = records.first, record.trackName != nil {
            return .song(song(from: record, duration: duration))
        }
        return searched
    }

    private func search(title: String, artist: String, duration: TimeInterval?) async -> Fetch {
        var sawFailure = false
        var attempts = 0
        var seen = Set<String>()
        var pairs: [(String, String)] = []
        let titles = LyricMatch.titleVariants(title)
        for candidateTitle in titles {
            for candidateArtist in LyricMatch.artistVariants(artist) {
                pairs.append((candidateTitle, candidateArtist))
            }
        }
        if let bare = titles.last { pairs.append((bare, "")) }
        for (candidateTitle, candidateArtist) in pairs {
            let key = LyricMatch.normalize(candidateTitle) + "\n" + LyricMatch.normalize(candidateArtist)
            guard seen.insert(key).inserted else { continue }
            attempts += 1
            switch await request(searchURL(title: candidateTitle, artist: candidateArtist), retryOnBusy: attempts == 1) {
            case .records(let records):
                if let record = best(records, title: title, artist: artist, duration: duration) {
                    return .song(song(from: record, duration: duration))
                }
            case .missing:
                break
            case .failed:
                sawFailure = true
            }
        }
        return sawFailure ? .failed : .missing
    }

    private func song(from record: Record, duration: TimeInterval?) -> LyricSong {
        LyricSong.make(
            synced: record.syncedLyrics,
            plain: record.plainLyrics,
            duration: record.duration ?? duration,
            instrumental: record.instrumental == true
                || ((record.syncedLyrics ?? "").isEmpty && (record.plainLyrics ?? "").isEmpty)
        )
    }

    private func best(_ records: [Record], title: String, artist: String, duration: TimeInterval?) -> Record? {
        var winner: (Record, Double)?
        for record in records {
            guard let score = LyricMatch.score(
                title: record.trackName ?? "",
                artist: record.artistName ?? "",
                duration: record.duration,
                synced: record.syncedLyrics?.isEmpty == false,
                wantedTitle: title,
                wantedArtist: artist,
                wantedDuration: duration
            ) else { continue }
            if winner == nil || score > winner!.1 { winner = (record, score) }
        }
        return winner?.0
    }

    private enum Response {
        case records([Record])
        case missing
        case failed
    }

    private func request(_ url: URL?, retryOnBusy: Bool) async -> Response {
        guard let url else { return .failed }
        var attempt = 0
        while attempt < 2 {
            attempt += 1
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Claude FM 1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failed }
                if http.statusCode == 404 { return .missing }
                if http.statusCode == 429 || http.statusCode == 503 {
                    if retryOnBusy, attempt == 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    return .failed
                }
                guard (200...299).contains(http.statusCode) else { return .failed }
                let decoder = JSONDecoder()
                if let many = try? decoder.decode([Record].self, from: data) { return .records(many) }
                if let one = try? decoder.decode(Record.self, from: data), one.trackName != nil { return .records([one]) }
                return .missing
            } catch {
                return .failed
            }
        }
        return .failed
    }

    private func getURL(title: String, artist: String, album: String, duration: TimeInterval) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        return components?.url
    }

    private func searchURL(title: String, artist: String) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        components?.queryItems = items
        return components?.url
    }

    private func cacheKey(title: String, artist: String) -> String {
        LyricMatch.normalize(title) + "\n" + LyricMatch.normalize(artist)
    }

    private func store(_ song: LyricSong, for key: String) {
        entries[key] = .song(song)
        remember(key)
    }

    private func storeMissing(for key: String) {
        entries[key] = .missing
        remember(key)
    }

    private func remember(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > 12 {
            entries[order.removeFirst()] = nil
        }
    }
}
