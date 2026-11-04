import Foundation

/// 중국어: 병음을 한글 음절로 옮긴다. 표기는 외래어 표기법의 중국어 표기를 따른다.
extension HangulReading {
    /// 낱말마다 받은 병음을 음절로 나눠 한글로 적는다. 낱말끼리는 띄운다.
    static func chinese(_ text: String, orJapanese: Bool = true) -> String {
        let chars = Array(text)
        var plain: [String?] = Array(repeating: nil, count: chars.count)
        // 글자 하나만 읽은 병음(성조 뺀 글자). 낱말 병음을 글자별로 나누는 데 쓴다.
        func letters(at index: Int) -> String {
            if let hit = plain[index] { return hit }
            let reading = mandarinTokens(String(chars[index])).first.flatMap(pinyinLetters)?.joined().map(\.char) ?? []
            plain[index] = String(reading)
            return plain[index]!
        }
        var cursor = 0
        var spoken: [String] = []
        var spokenRaw: [String] = []
        for token in mandarinTokens(text) {
            guard let parts = pinyinLetters(token) else {
                cursor += token.filter(isHan).count
                continue
            }
            let word = Array(parts.joined())
            let target = String(word.map(\.char))
            var syllables: [(initial: String, final: String)] = []
            var built = ""
            var cuts: [Int] = []
            while cursor + cuts.count < chars.count, built.count < target.count {
                built += letters(at: cursor + cuts.count)
                cuts.append(built.count)
            }
            if built == target {
                // 亲爱 qīnài 처럼 ' 없이 붙은 병음도 글자 읽기에 맞춰 qin·ai 로 나눈다.
                var start = 0
                for cut in cuts {
                    syllables += segmentPinyin(Array(word[start..<cut]))
                    start = cut
                }
            } else {
                for part in parts { syllables += segmentPinyin(part) }
                cuts = Array(repeating: 0, count: max(1, syllables.count))
            }
            if cuts.count == 1, cursor < chars.count, syllables.count == 1,
               let fixed = mandarinPolyphone(chars, at: cursor, syllables[0]) {
                syllables = [fixed]
            }
            let raw = String(chars[min(cursor, chars.count)..<min(cursor + cuts.count, chars.count)])
            cursor += cuts.count
            let reading = renderPinyinSyllables(syllables)
            guard !reading.isEmpty else { continue }
            // 一九九九年·二零零八年 처럼 글자마다 끊긴 숫자와 그 뒤 단위는 한 낱말로 잇는다.
            if let last = spokenRaw.last, isChineseNumeral(last),
               isChineseNumeral(raw) || (raw.count == 1 && chineseNumberUnits.contains(raw)) {
                spoken[spoken.count - 1] += reading
                spokenRaw[spokenRaw.count - 1] += raw
            } else {
                spoken.append(reading)
                spokenRaw.append(raw)
            }
        }
        if spoken.isEmpty { return orJapanese ? japanese(text) : text }
        return spoken.joined(separator: " ")
    }

    /// 병음 낱말 하나를 한글로 적는다. 병음이 아닌 글자가 섞인 낱말은 읽지 않는다.
    static func pinyinToken(_ raw: String) -> String {
        guard let letters = pinyinLetters(raw) else { return "" }
        return renderPinyinSyllables(letters.flatMap(segmentPinyin))
    }

    static func renderPinyinSyllables(_ syllables: [(initial: String, final: String)]) -> String {
        var out = ""
        for syllable in syllables {
            if syllable.initial == "r", syllable.final.isEmpty {
                out = appendErhua(to: out)
            } else {
                out += renderPinyin(initial: syllable.initial, final: syllable.final)
            }
        }
        return out
    }

    /// 낱말 사전이 홀로 선 글자에 흔하지 않은 소리를 고를 때 가사 문맥으로 고친다.
    /// 还 는 还给 가 아니면 hái, 重来·重新 의 重 은 chóng, 忘不了·睡不着 의 了·着 는 liǎo·zháo.
    static func mandarinPolyphone(_ chars: [Character], at index: Int, _ syllable: (initial: String, final: String)) -> (initial: String, final: String)? {
        let char = chars[index]
        let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
        let previous: Character? = index > 0 ? chars[index - 1] : nil
        switch (char, syllable.initial, syllable.final) {
        case ("还", "h", "uan"), ("還", "h", "uan"):
            return next.map { "给給钱錢书書债債".contains($0) } == true ? nil : ("h", "ai")
        case ("重", "zh", "ong"):
            return next.map { "来來新逢复復生演回温溫叠疊返申播建燃启啟现現".contains($0) } == true ? ("ch", "ong") : nil
        case ("了", "l", "e"):
            return previous == "不" && next.map { "解".contains($0) } != true ? ("l", "iao") : nil
        case ("着", "zh", "e"), ("著", "zh", "e"):
            return previous == "不" ? ("zh", "ao") : nil
        default:
            return nil
        }
    }

    // MARK: - 숫자

    static let chineseDigitNames: [Character: String] = [
        "0": "零", "1": "一", "2": "二", "3": "三", "4": "四", "5": "五", "6": "六", "7": "七", "8": "八", "9": "九",
    ]

    /// 숫자만으로 된 말(第 로 시작해도 된다).
    static func isChineseNumeral(_ raw: String) -> Bool {
        let body = raw.hasPrefix("第") ? raw.dropFirst() : Substring(raw)
        return !body.isEmpty && body.allSatisfy { "零〇一二三四五六七八九十百千万亿两萬億兩".contains($0) }
    }

    static let chineseNumberUnits: Set<String> = ["年", "月", "日", "号", "號", "点", "點", "岁", "歲"]

    static func chineseDigits(_ digits: String) -> String {
        digits.map { chineseDigitNames[$0] ?? String($0) }.joined()
    }

    /// 중국어 가사의 숫자를 한자 숫자로 푼다. 年 앞의 네 자리 해와 0 으로 시작하는 숫자는 한 자씩(一九九九年),
    /// 나머지는 자리를 붙여(二十四, 一千年, 两千零二十) 읽고, 第 가 없는 양사 앞의 2 는 两 이다.
    static func chineseNumberWord(_ digits: String, before next: Character?, after previous: Character? = nil) -> String {
        let year = next == "年" && digits.count == 4 && (Int(digits) ?? 0) % 1000 != 0
        if (digits.count > 1 && digits.first == "0") || year || digits.count > 12 {
            return chineseDigits(digits)
        }
        guard let value = Int(digits) else { return chineseDigits(digits) }
        if value == 2, previous != "第", let next, "个個次天只位本张張件条條种種首点點岁歲年辆輛双雙对對杯颗顆片句步遍回场場".contains(next) {
            return "两"
        }
        return chineseNumeral(value)
    }

    static func chineseNumeral(_ value: Int) -> String {
        guard value > 0 else { return "零" }
        let groups: [(Int, String)] = [(100_000_000, "亿"), (10_000, "万"), (1, "")]
        var out = ""
        var remaining = value
        var pendingZero = false
        for (unit, name) in groups {
            let section = remaining / unit
            remaining %= unit
            guard section > 0 else {
                if !out.isEmpty { pendingZero = true }
                continue
            }
            if !out.isEmpty, pendingZero || section < 1000 { out += "零" }
            out += (section == 2 && !name.isEmpty ? "两" : chineseSection(section, leading: out.isEmpty)) + name
            pendingZero = false
        }
        return out
    }

    /// 1~9999. 맨 앞의 10~19 는 一 없이 十 으로 시작하고, 천 자리의 2 는 两 으로 읽는다.
    static func chineseSection(_ value: Int, leading: Bool) -> String {
        let names = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let units = ["千", "百", "十", ""]
        let places = [value / 1000, (value / 100) % 10, (value / 10) % 10, value % 10]
        var out = ""
        var zero = false
        for (offset, digit) in places.enumerated() {
            guard digit > 0 else {
                if !out.isEmpty { zero = true }
                continue
            }
            if zero { out += "零" }
            zero = false
            if offset == 2, digit == 1, out.isEmpty, leading {
                out += "十"
            } else if offset == 0, digit == 2 {
                out += "两千"
            } else {
                out += names[digit] + units[offset]
            }
        }
        return out
    }

    struct PinyinLetter {
        var char: Character
        var toned: Bool
    }

    /// 성조 부호를 떼어 내고 ü 는 v 로 둔다. 아포스트로피·띄어쓰기에서 음절 묶음을 나눈다.
    static func pinyinLetters(_ raw: String) -> [[PinyinLetter]]? {
        var parts: [[PinyinLetter]] = []
        var current: [PinyinLetter] = []
        for scalar in raw.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.value {
            case 0x61...0x7A:
                current.append(PinyinLetter(char: Character(scalar), toned: false))
            case 0x0304, 0x0301, 0x030C, 0x0300:
                if !current.isEmpty { current[current.count - 1].toned = true }
            case 0x0308:
                if let last = current.last, last.char == "u" { current[current.count - 1].char = "v" }
            case 0x0302:
                break
            case 0x27, 0x2019, 0x20, 0x2D:
                if !current.isEmpty { parts.append(current) }
                current = []
            default:
                return nil
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.isEmpty ? nil : parts
    }

    static let pinyinInitials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]

    /// 성모마다 붙을 수 있는 운모. 성모 없는 음절은 a·o·e 로 시작하는 것만 따로 둔다.
    static let pinyinSyllableSet: Set<String> = {
        let common = ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"]
        let labial = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "i", "ie", "iao", "iu", "ian", "in", "ing", "u"]
        let alveolar = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing", "u", "uo", "ui", "uan", "un", "v", "ve", "ue"]
        let palatal = ["i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing", "iong", "u", "ue", "uan", "un", "v", "ve"]
        let retroflex = common + ["i"]
        var set: Set<String> = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "er", "m", "n", "ng", "hm", "hng"]
        for initial in ["b", "p", "m", "f"] { for final in labial { set.insert(initial + final) } }
        for initial in ["d", "t", "n", "l"] { for final in alveolar { set.insert(initial + final) } }
        for initial in ["g", "k", "h"] { for final in common { set.insert(initial + final) } }
        for initial in ["zh", "ch", "sh", "r", "z", "c", "s"] { for final in retroflex { set.insert(initial + final) } }
        for initial in ["j", "q", "x"] { for final in palatal { set.insert(initial + final) } }
        for final in ["a", "o", "e", "i", "ai", "ao", "ou", "an", "in", "ang", "ing", "ong", "u", "ue", "uan", "un"] { set.insert("y" + final) }
        for final in ["a", "o", "u", "ai", "ei", "an", "en", "ang", "eng"] { set.insert("w" + final) }
        return set
    }()

    /// 한 묶음을 음절로 나눈다. 둘째 음절부터는 a·o·e 로 시작하지 않고(병음은 그 앞에 ' 를 쓴다)
    /// 음절마다 성조 부호가 하나뿐인 나눔을 고른다.
    static func segmentPinyin(_ letters: [PinyinLetter]) -> [(initial: String, final: String)] {
        let chars = letters.map(\.char)
        let count = chars.count
        var best: [(cost: Int, cuts: [Int])?] = Array(repeating: nil, count: count + 1)
        best[0] = (0, [])
        for start in 0..<count {
            guard let here = best[start] else { continue }
            for length in 1...min(6, count - start) {
                let piece = String(chars[start..<(start + length)])
                var cost = here.cost + 1
                if pinyinSyllableSet.contains(piece) {
                    if start > 0, "aoe".contains(chars[start]) { cost += 10 }
                    if letters[start..<(start + length)].filter(\.toned).count > 1 { cost += 10 }
                } else if piece == "r", start > 0, start + 1 == count {
                    cost += 1
                } else {
                    continue
                }
                let end = start + length
                if best[end] == nil || cost < best[end]!.cost {
                    best[end] = (cost, here.cuts + [end])
                }
            }
            if best[start + 1] == nil || here.cost + 20 < best[start + 1]!.cost {
                best[start + 1] = (here.cost + 20, here.cuts + [-(start + 1)])
            }
        }
        guard let path = best[count] else { return [] }
        var syllables: [(initial: String, final: String)] = []
        var start = 0
        for cut in path.cuts {
            let end = abs(cut)
            defer { start = end }
            guard cut > 0 else { continue }
            let piece = String(chars[start..<end])
            if piece == "r" {
                syllables.append(("r", ""))
                continue
            }
            let initial = pinyinInitials.first { piece.hasPrefix($0) && piece.count > $0.count && !["m", "n", "ng", "hm", "hng"].contains(piece) } ?? ""
            syllables.append((initial, String(piece.dropFirst(initial.count))))
        }
        return syllables
    }

    /// 儿化 r 은 낱말 사전이 儿 을 따로 읽은 ér 과 같이 얼로 잇는다. (哪儿 나얼, 玩儿 완얼)
    static func appendErhua(to text: String) -> String {
        text + "얼"
    }

    static func renderPinyin(initial: String, final: String) -> String {
        var final = final
        if initial == "y" {
            let table: [String: String] = [
                "a": "ia", "o": "io", "e": "ie", "ai": "iai", "ao": "iao", "ou": "iu", "an": "ian", "ang": "iang",
                "ong": "iong", "u": "v", "ue": "ve", "uan": "van", "un": "vn",
            ]
            final = table[final] ?? final
        } else if initial == "w" {
            let table: [String: String] = [
                "a": "ua", "o": "uo", "ai": "uai", "ei": "ui", "an": "uan", "en": "un", "ang": "uang", "eng": "ueng",
            ]
            final = table[final] ?? final
        } else if ["j", "q", "x"].contains(initial) {
            let table: [String: String] = ["u": "v", "ue": "ve", "uan": "van", "un": "vn"]
            final = table[final] ?? final
        } else if final == "ue" {
            final = "ve"
        }
        if initial.isEmpty {
            switch final {
            case "m": return "음"
            case "n", "ng": return "응"
            case "hm": return "흠"
            case "hng": return "흥"
            default: break
            }
        }
        let buzz = final == "i" && ["zh", "ch", "sh", "r", "z", "c", "s"].contains(initial)
        return pinyinSyllables(cho: pinyinCho(initial), final: final, buzz: buzz,
                               palatal: ["j", "q"].contains(initial), glide: initial == "w" || initial == "y")
    }

    /// 성모는 표기법대로 z 는 ㅉ, s 는 ㅆ, zh·j 는 ㅈ, ch·q·c 는 ㅊ, sh·x 는 ㅅ 으로 적는다.
    static func pinyinCho(_ initial: String) -> Int {
        switch initial {
        case "b": return 7
        case "p", "f": return 17
        case "m": return 6
        case "d": return 3
        case "t": return 16
        case "n": return 2
        case "l", "r": return 5
        case "g": return 0
        case "k": return 15
        case "h": return 18
        case "j", "zh": return 12
        case "z": return 13
        case "q", "ch", "c": return 14
        case "x", "sh": return 9
        case "s": return 10
        default: return 11
        }
    }

    /// 운모를 한글로. ㅈ·ㅊ 뒤의 ㅑ·ㅖ·ㅛ·ㅠ 는 ㅏ·ㅔ·ㅗ·ㅜ 로 적고, ian 은 옌, ong 은 웅, üe 는 웨로 적는다.
    static func pinyinSyllables(cho: Int, final: String, buzz: Bool, palatal: Bool, glide: Bool) -> String {
        func one(_ jung: Int, _ jong: Int = 0) -> String { syllable(cho, jung, jong) }
        func rest(_ jung: Int, _ jong: Int = 0) -> String { syllable(11, jung, jong) }
        let ya = palatal ? 0 : 2
        let ye = palatal ? 5 : 7
        let yu = palatal ? 13 : 17
        switch final {
        case "a": return one(0)
        case "o": return one(8)
        case "e": return one(4)
        case "i": return one(buzz ? 18 : 20)
        case "u": return one(13)
        case "v": return one(16)
        case "ai": return one(0) + rest(20)
        case "ei": return one(5) + rest(20)
        case "ao": return one(0) + rest(8)
        case "ou": return one(4) + rest(13)
        case "an": return one(0, 4)
        case "en": return one(4, 4)
        case "ang": return one(0, 21)
        case "eng": return one(4, 21)
        case "ong": return one(13, 21)
        case "er": return one(4, 8)
        case "ia": return one(ya)
        case "io": return one(12)
        case "ie": return one(ye)
        case "iai": return one(2) + rest(20)
        case "iao": return one(ya) + rest(8)
        case "iu": return one(yu)
        case "ian": return one(ye, 4)
        case "in": return one(20, 4)
        case "iang": return one(ya, 21)
        case "ing": return one(20, 21)
        case "iong": return one(yu, 21)
        case "ua": return one(9)
        case "uo": return one(14)
        case "uai": return one(9) + rest(20)
        case "ui": return glide ? one(15) + rest(20) : one(13) + rest(20)
        case "uan": return one(9, 4)
        case "un": return glide ? one(14, 4) : one(13, 4)
        case "uang": return one(9, 21)
        case "ueng": return one(14, 21)
        case "ve": return one(15)
        case "van": return one(16) + rest(0, 4)
        case "vn": return one(16, 4)
        default: return ""
        }
    }
}
