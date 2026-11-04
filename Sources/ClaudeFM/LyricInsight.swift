import Foundation

/// 가사에 나온 말에 맞춰 띄우는 작은 그림. 발음으로 바꾸기 전 원문에서 찾는다.
enum LyricReaction: String, CaseIterable, Equatable {
    case love, star, fire, tears, moon, flower, sun, snow

    /// 뜻을 한국어로. 곡 끝 기록에 쓴다.
    var label: String {
        switch self {
        case .love: return "사랑"
        case .star: return "별"
        case .fire: return "불꽃"
        case .tears: return "눈물"
        case .moon: return "달"
        case .flower: return "꽃"
        case .sun: return "햇살"
        case .snow: return "눈"
        }
    }
}

/// 곡에서 가장 많이 부른 반응 낱말. 후주에 한 번 보여 준다.
struct LyricRecap: Equatable {
    var reaction: LyricReaction
    /// 원문에서 가장 자주 나온 꼴. 영어는 소문자로 둔다.
    var word: String
    var count: Int

    /// `사랑 ×12`
    var headline: String { "\(reaction.label) ×\(count)" }

    /// 원문 낱말이 뜻과 다르면(love, 愛) 같이 적는다.
    var caption: String {
        word == reaction.label ? "이 곡에서 부른 횟수" : "‘\(word)’ · 이 곡에서 부른 횟수"
    }
}

/// 줄 안에서 이 시각에 이만큼 불렀다는 표시. `fraction` 은 글자 수 기준 0...1.
struct LyricMark: Equatable {
    var time: TimeInterval
    var fraction: Double
}

/// 원문 한 줄에서 반응 낱말을 찾는다. 여러 개면 먼저 나온 것을 고른다.
enum LyricReactionFinder {
    private struct Rule {
        var reaction: LyricReaction
        var pattern: NSRegularExpression
    }

    /// 원문에서 반응 낱말이 나온 곳들. 곡 끝 기록을 셀 때 쓴다.
    static func matches(in text: String) -> [(reaction: LyricReaction, word: String, location: Int)] {
        guard text.contains(where: \.isLetter) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        var found: [(reaction: LyricReaction, word: String, location: Int)] = []
        for rule in rules {
            for match in rule.pattern.matches(in: text, range: range) {
                let word = (text as NSString).substring(with: match.range)
                found.append((rule.reaction, word.lowercased(), match.range.location))
            }
        }
        // 같은 자리에서 두 규칙이 걸리면(눈꽃 → 눈·꽃) 앞에 적은 규칙을 남긴다.
        found.sort { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return order(lhs.reaction) < order(rhs.reaction)
        }
        var kept: [(reaction: LyricReaction, word: String, location: Int)] = []
        var coveredUntil = -1
        for item in found where item.location > coveredUntil {
            kept.append(item)
            coveredUntil = item.location + (item.word as NSString).length - 1
        }
        return kept
    }

    static func find(in text: String) -> LyricReaction? {
        matches(in: text).first?.reaction
    }

    private static func order(_ reaction: LyricReaction) -> Int {
        LyricReaction.allCases.firstIndex(of: reaction) ?? 0
    }

    private static func rule(_ reaction: LyricReaction, _ pattern: String) -> Rule {
        // 규칙은 고정 문자열이라 컴파일 실패는 개발 중에 바로 드러난다.
        Rule(reaction: reaction, pattern: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
    }

    // 한국어는 띄어쓰기 단위가 길어서, 다른 낱말 속에 묻힌 글자(이별의 별, 불러의 불)는 피하도록 꼴을 정해 둔다.
    // 영어는 낱말 경계로 자르고, 일본어·중국어는 글자로 찾는다.
    private static let rules: [Rule] = [
        rule(.snow, #"눈이\s?(?:내|와|오)|눈송이|첫눈|함박눈|눈꽃|눈사람|겨울|\b(?:snow\w*|winter|frozen|freez\w*)\b|雪|冬|ゆき"#),
        rule(.fire, #"불꽃|불타|불길|불처럼|불이\s?붙|불을\s?붙|불태|타오르|타올라|뜨거|열정|\b(?:fire|fires|burn\w*|flames?|blaz\w*|ignite\w*|lit|hot|heat)\b|花火|火|炎|燃|熱|烧|ファイア"#),
        rule(.love, #"사랑|좋아해|좋아했|하트|심장|두근|설레|키스|입맞|\b(?:lov(?:e|es|ed|ing|er|ers|ely)|heart\w*|kiss\w*|darling|sweetheart)\b|愛|爱|恋|好き|すき|スキ|ハート|キス|(?<!ク)ラブ|ドキドキ|どきどき|喜欢|心"#),
        rule(.star, #"(?<![이특개차구분])별(?:빛|들|자리|처럼|이|을|만|과|에|의|님|똥)|샛별|반짝|은하|빛나|\b(?:\w*star(?:s|light|dust|ry)?|shin(?:e|es|ing)|sparkl\w*|twinkl\w*|glitter\w*|galax\w*)\b|星|輝|煌|キラキラ|きらきら|スター|闪|耀"#),
        rule(.tears, #"눈물|울어|울고|울지|울었|울음|비가|빗물|빗소리|빗속|빗방울|비\s?내리|비처럼|소나기|장마|\b(?:tears?|cry|cries|crying|cried|rain(?:s|y|ing|ed|drops?)?|weep\w*)\b|涙|泣|雨|なみだ|泪|哭"#),
        rule(.moon, #"달빛|달님|보름달|초승달|반달|달이\s?뜨|달\s?아래|달처럼|밤하늘|한밤|\b(?:moon\w*|midnight)\b|(?<!岁|歲)月|夜空|真夜中|ムーン|午夜"#),
        rule(.flower, #"(?<!불|눈)꽃|장미|피어나|\b(?:flowers?|bloom\w*|blossom\w*|roses?|petals?|daisy|daisies)\b|花|咲|桜|さくら|サクラ|薔薇|バラ|玫瑰|樱"#),
        rule(.sun, #"햇살|햇빛|햇볕|태양|해가\s?뜨|해처럼|눈부시|눈부신|눈부셔|\b(?:sun|suns|sunny|sunshine|sunlight|sunrise|sunset|summer)\b|太陽|太阳|陽|阳光|日差し|ひざし|夏"#),
    ]
}

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
            lines[index].end = lines[index].time + min(max(sing, min(0.5, limit)), max(limit, 0.2))
        }
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
