import Foundation

/// 동기 가사 한 곡을 훑어 노래방 채움 시각, 후렴, 반응을 붙인다.
enum LyricInsight {
    /// 부르는 빠르기를 모를 때 쓰는 초당 음절 수.
    static let defaultSyllableRate = 4.5

    /// 줄마다 다 부르는 시각을 추정한다. 빈 줄(숨 고르기)이나 다음 줄 시작 전에 끝난다.
    /// 곡에서 쉼 없이 이어 부르는 줄들의 빠르기를 기준으로 삼는다.
    static func estimateEnds(_ lines: inout [LyricLine], duration: TimeInterval?) {
        let rate = syllableRate(lines, duration: duration)
        for index in lines.indices where !lines[index].text.isEmpty {
            let gap = gapAfter(index, in: lines, duration: duration)
            let syllables = syllableCount(lines[index].text)
            let sing: TimeInterval
            if let last = lines[index].marks.last {
                // 낱말 시각이 있으면 마지막 표시에서 남은 글자만 추정한다.
                let rest = max(0, 1 - last.fraction) * syllables / rate * 1.08
                sing = max(0.3, last.time - lines[index].time + max(rest, last.fraction >= 0.999 ? 0 : 0.25))
            } else {
                sing = syllables / rate * 1.08
            }
            let limit = gap > 0.6 ? gap - 0.08 : gap * 0.9
            let end = lines[index].time + min(max(sing, min(0.5, limit)), max(limit, 0.2))
            lines[index].end = end
            if lines[index].marks.isEmpty {
                lines[index].marks = phrasedMarks(lines[index].text, start: lines[index].time, end: end, rate: rate)
            }
        }
    }

    /// 낱말 시각이 없는 줄을 부르는 모양대로 음절마다 나눈다. 줄 몸통은 고른 빠르기로 부르고,
    /// 낱말 끝과 쉼표 앞에서 조금 머물고, 마지막 음절은 길게 끈다. 빠른 곡일수록 덜 끈다.
    /// 비율은 낱말 시각(`wordMarks`)과 같이 글자(문자·숫자) 수로 센다.
    static func phrasedMarks(_ text: String, start: TimeInterval, end: TimeInterval, rate: Double) -> [LyricMark] {
        let chars = Array(text)
        var weights: [Double] = []
        for (index, char) in chars.enumerated() where char.isLetter || char.isNumber {
            var weight = 1.0
            if index + 1 < chars.count {
                let next = chars[index + 1]
                if next.isWhitespace {
                    weight = 1.15
                } else if ",.!?~…、。，！？".contains(next) {
                    weight = 1.5
                }
            }
            weights.append(weight)
        }
        guard weights.count >= 2, end - start >= 0.6 else { return [] }
        weights[weights.count - 1] = min(2.8, max(1.3, 2.6 - (rate - 3) * 0.25))
        let unit = (end - start) / weights.reduce(0, +)
        var marks: [LyricMark] = []
        var time = start
        for index in 0..<(weights.count - 1) {
            time += weights[index] * unit
            marks.append(LyricMark(time: time, fraction: Double(index + 1) / Double(weights.count)))
        }
        return marks
    }

    /// 쉼 없이 부르는 줄은 다음 줄까지 거의 꽉 차므로, 빠른 쪽 줄들의 빠르기가 그 곡의 빠르기다.
    static func syllableRate(_ lines: [LyricLine], duration: TimeInterval?) -> Double {
        var rates: [Double] = []
        for index in lines.indices where !lines[index].text.isEmpty {
            let gap = gapAfter(index, in: lines, duration: duration)
            let syllables = syllableCount(lines[index].text)
            guard gap >= 0.8, gap <= 12, syllables >= 3 else { continue }
            rates.append(syllables / gap)
        }
        guard rates.count >= 3 else { return defaultSyllableRate }
        rates.sort()
        let pick = rates[min(rates.count - 1, Int(Double(rates.count - 1) * 0.8 + 0.5))]
        return min(8.5, max(2.2, pick))
    }

    /// 이 줄 시작부터 다음 줄(빈 줄 포함) 시작까지. 마지막 줄은 곡 끝이나 5초까지.
    static func gapAfter(_ index: Int, in lines: [LyricLine], duration: TimeInterval?) -> TimeInterval {
        let start = lines[index].time
        if let next = lines[(index + 1)...].first(where: { $0.time > start + 0.05 }) {
            return next.time - start
        }
        if let duration, duration > start + 1 { return min(duration - start, 8) }
        return 5
    }

    /// 한글 음절은 한 박씩, 남은 라틴 글자는 대략 세 글자에 한 음절로 센다.
    static func syllableCount(_ text: String) -> Double {
        var syllables = 0.0
        var latin = 0.0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7A3, 0x3040...0x30FF, 0x4E00...0x9FFF:
                syllables += 1
            case 0x41...0x5A, 0x61...0x7A:
                latin += 1
            case 0x30...0x39:
                syllables += 1
            default:
                break
            }
        }
        return max(1, syllables + latin / 3)
    }

    /// 두 번 넘게 되풀이되는 줄이나, 되풀이되는 줄끼리 붙어 있는 덩어리를 후렴으로 본다.
    static func markHooks(_ lines: inout [LyricLine]) {
        let vocal = lines.indices.filter { !lines[$0].text.isEmpty }
        guard vocal.count >= 4 else { return }
        let keys = lines.map { hookKey($0.text) }
        var counts: [String: Int] = [:]
        for index in vocal where keys[index].count >= 4 {
            counts[keys[index], default: 0] += 1
        }
        func count(_ index: Int) -> Int { keys[index].count >= 4 ? counts[keys[index]] ?? 0 : 0 }

        func flag(minimum: Int) -> Set<Int> {
            var hooks = Set<Int>()
            for (position, index) in vocal.enumerated() {
                let repeats = count(index)
                guard repeats >= 2 else { continue }
                if repeats >= minimum {
                    hooks.insert(index)
                    continue
                }
                let previous = position > 0 ? vocal[position - 1] : nil
                let next = position + 1 < vocal.count ? vocal[position + 1] : nil
                let nearPrevious = previous.map { count($0) >= 2 && lines[index].time - lines[$0].time < 12 } ?? false
                let nearNext = next.map { count($0) >= 2 && lines[$0].time - lines[index].time < 12 } ?? false
                if nearPrevious || nearNext { hooks.insert(index) }
            }
            return hooks
        }

        var hooks = flag(minimum: 3)
        // 거의 모든 줄이 되풀이되는 곡은 가장 많이 되풀이되는 줄만 후렴으로 남긴다.
        if Double(hooks.count) > Double(vocal.count) * 0.65 {
            hooks = hooks.filter { count($0) >= 3 }
            if Double(hooks.count) > Double(vocal.count) * 0.65, let top = hooks.map(count).max() {
                hooks = hooks.filter { count($0) >= top }
            }
        }
        for (position, index) in vocal.enumerated() where hooks.contains(index) {
            lines[index].isHook = true
            let previous = position > 0 ? vocal[position - 1] : nil
            let continues = previous.map { hooks.contains($0) && lines[index].time - lines[$0].time < 9 } ?? false
            lines[index].hookStart = !continues
        }
    }

    /// 띄어쓰기·문장부호·대소문자를 빼고 비교한다.
    static func hookKey(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// 원문 줄들에서 가장 많이 부른 반응 낱말을 센다. 세 번 이상일 때만.
    static func recap(_ originals: [String]) -> LyricRecap? {
        var totals: [LyricReaction: Int] = [:]
        var words: [LyricReaction: [String: Int]] = [:]
        for line in originals {
            for match in LyricReactionFinder.matches(in: line) {
                totals[match.reaction, default: 0] += 1
                words[match.reaction, default: [:]][match.word, default: 0] += 1
            }
        }
        guard let best = totals.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : order(lhs.key) > order(rhs.key)
        }), best.value >= 3 else { return nil }
        let word = words[best.key]?.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key ?? best.key.label
        return LyricRecap(reaction: best.key, word: word, count: best.value)
    }

    private static func order(_ reaction: LyricReaction) -> Int {
        LyricReaction.allCases.firstIndex(of: reaction) ?? 0
    }

    /// `<mm:ss.xx>` 낱말 시각을 떼어 내고, 그 자리까지의 글자 비율과 묶는다.
    static func wordMarks(_ raw: String, offset: TimeInterval) -> (text: String, marks: [LyricMark]) {
        let ns = raw as NSString
        let matches = wordStampPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (raw, []) }
        var clean = ""
        var stamps: [(letters: Int, time: TimeInterval)] = []
        var cursor = 0
        var letters = 0
        for match in matches {
            let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            clean += before
            letters += before.reduce(0) { $0 + ($1.isLetter || $1.isNumber ? 1 : 0) }
            if let time = stampTime(ns, match) {
                stamps.append((letters, time + offset))
            }
            cursor = match.range.location + match.range.length
        }
        let tail = ns.substring(from: cursor)
        clean += tail
        let total = letters + tail.reduce(0) { $0 + ($1.isLetter || $1.isNumber ? 1 : 0) }
        guard total > 0, !stamps.isEmpty else { return (clean, []) }
        var marks: [LyricMark] = []
        for stamp in stamps {
            let fraction = min(1, Double(stamp.letters) / Double(total))
            if let last = marks.last, stamp.time < last.time || fraction < last.fraction { continue }
            marks.append(LyricMark(time: stamp.time, fraction: fraction))
        }
        return (clean, marks)
    }

    private static func stampTime(_ line: NSString, _ match: NSTextCheckingResult) -> TimeInterval? {
        func part(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return line.substring(with: range)
        }
        guard let minutes = part(1).flatMap(Double.init), let seconds = part(2).flatMap(Double.init) else { return nil }
        var fraction = 0.0
        if let digits = part(3), let value = Double(digits) {
            fraction = value / pow(10, Double(digits.count))
        }
        return minutes * 60 + seconds + fraction
    }

    private static let wordStampPattern = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>"#)
}
