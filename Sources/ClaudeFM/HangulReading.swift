import Foundation
import NaturalLanguage

/// 가사 한 줄을 부르는 소리로 바꾼다.
/// 한글은 그대로 두고, 일본어·중국어·영어는 뜻이 아니라 한국어 발음으로 적는다.
enum HangulReading {
    static func line(_ raw: String, preferJapanese: Bool = false) -> String {
        var cleaned = raw
        for caret in ["^", "＾", "ˆ", "‸", "⌃", "︿"] {
            cleaned = cleaned.replacingOccurrences(of: caret, with: " ")
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let text = normalizeWidth(trimmed)
        let rawChars = Array(text)
        guard rawChars.contains(where: { $0.isLetter || $0.isNumber }) else { return "" }
        let hanIsJapanese = preferJapanese || rawChars.contains(where: isKana) || (rawChars.contains(where: isHan) && soundsJapanese(text))
        let expanded = expandNumbers(in: text, hanIsJapanese: hanIsJapanese, preferJapanese: preferJapanese)
        let chars = Array(expanded)

        var out = ""
        var index = 0
        while index < chars.count {
            let kind = kind(of: chars[index], hanIsJapanese: hanIsJapanese)
            var next = index + 1
            while next < chars.count {
                let nextKind = self.kind(of: chars[next], hanIsJapanese: hanIsJapanese)
                if nextKind == kind {
                    next += 1
                } else if kind == .latin, chars[next].isWhitespace,
                          next + 1 < chars.count,
                          self.kind(of: chars[next + 1], hanIsJapanese: hanIsJapanese) == .latin {
                    next += 1
                } else {
                    break
                }
            }
            let slice = String(chars[index..<next])
            let piece: String
            switch kind {
            case .hangul, .other:
                piece = slice
            case .japanese:
                piece = japanese(slice)
            case .han:
                piece = chinese(slice)
            case .latin:
                piece = latin(slice)
            }
            if kind != .other, !piece.isEmpty, let last = out.last,
               !last.isWhitespace, !"([（［「『\"'".contains(last),
               let first = piece.first, !first.isWhitespace {
                out.append(" ")
            }
            out += piece
            index = next
        }
        return collapseSpaces(out)
    }

    // MARK: - 글자 갈래

    private enum Kind { case hangul, japanese, han, latin, other }

    private static func kind(of char: Character, hanIsJapanese: Bool) -> Kind {
        if isHangul(char) { return .hangul }
        if isKana(char) { return .japanese }
        if isHan(char) { return hanIsJapanese ? .japanese : .han }
        if isLatinLetter(char) || char == "'" { return .latin }
        return .other
    }

    /// 전각 영숫자·기호·아포스트로피만 반각으로 바꾸고, 가타카나는 전각 그대로 둔다.
    private static func normalizeWidth(_ text: String) -> String {
        let homoglyphs: [ UnicodeScalar: UnicodeScalar ] = [
            "’": "'", "‘": "'", "ʼ": "'", "｀": "'", "´": "'",
            "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i",
            "А": "A", "Е": "E", "О": "O", "Р": "P", "С": "C", "У": "Y", "Х": "X", "І": "I",
        ]
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if let mapped = homoglyphs[scalar] {
                scalars.append(mapped)
            } else if (0xFF01...0xFF5E).contains(scalar.value), let half = UnicodeScalar(scalar.value - 0xFEE0) {
                scalars.append(half)
            } else if scalar.value == 0x3000 {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func scalarValue(_ char: Character) -> UInt32? {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return nil }
        return scalar.value
    }

    private static func isHangul(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value)
    }

    private static func isKana(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value) || (0xFF65...0xFF9F).contains(value)
    }

    private static func isHan(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }

    private static func isLatinLetter(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) || (0xC0...0x24F).contains(value)
    }

    private static func isAsciiDigit(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x30...0x39).contains(value)
    }

    private static let jaSpellOutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja")
        formatter.numberStyle = .spellOut
        return formatter
    }()

    private static let enSpellOutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter
    }()

    private static let enOrdinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        return formatter
    }()

    /// 일본어·영어 가사에 들어 있는 숫자를 문맥에 맞는 발음용 글자로 풀어 적는다.
    private static func expandNumbers(in text: String, hanIsJapanese: Bool, preferJapanese: Bool) -> String {
        let chars = Array(text)
        guard chars.contains(where: isAsciiDigit) else { return text }
        let lineHasCJK = chars.contains { isKana($0) || isHan($0) }
        let lineHasLatin = chars.contains(where: isLatinLetter)

        var out = ""
        var index = 0
        while index < chars.count {
            guard isAsciiDigit(chars[index]) else {
                out.append(chars[index])
                index += 1
                continue
            }
            let start = index
            var digits = ""
            while index < chars.count {
                if isAsciiDigit(chars[index]) {
                    digits.append(chars[index])
                    index += 1
                } else if chars[index] == ",",
                          index + 3 < chars.count,
                          isAsciiDigit(chars[index + 1]),
                          isAsciiDigit(chars[index + 2]),
                          isAsciiDigit(chars[index + 3]),
                          (index + 4 == chars.count || !isAsciiDigit(chars[index + 4])) {
                    index += 1
                } else {
                    break
                }
            }

            let prevImmediate: Character? = start > 0 ? chars[start - 1] : nil
            let nextImmediate: Character? = index < chars.count ? chars[index] : nil
            if (prevImmediate.map(isHangul) ?? false) || (nextImmediate.map(isHangul) ?? false) {
                out.append(String(chars[start..<index]))
                continue
            }

            // 24/7, 365/24 같은 영어 관용 숫자 표현
            if digits == "24", index + 1 < chars.count, chars[index] == "/", chars[index + 1] == "7",
               (index + 2 == chars.count || !isAsciiDigit(chars[index + 2])) {
                appendEnglishPiece("twenty four seven", to: &out)
                index += 2
                continue
            }

            // 1st, 2nd, 3rd, 4th 같은 영어 서수 표현
            if index + 2 <= chars.count {
                let suffix = String(chars[index..<(index + 2)]).lowercased()
                let afterSuffix: Character? = index + 2 < chars.count ? chars[index + 2] : nil
                if ["st", "nd", "rd", "th"].contains(suffix), !(afterSuffix.map(isLatinLetter) ?? false),
                   let value = Int(digits) {
                    appendEnglishPiece(englishOrdinalWord(value), to: &out)
                    index += 2
                    continue
                }
            }

            var prevNonSpace: Character?
            if start > 0 {
                var p = start - 1
                while p >= 0, chars[p].isWhitespace { p -= 1 }
                if p >= 0 { prevNonSpace = chars[p] }
            }
            var nextNonSpace: Character?
            var lookahead = index
            if lookahead < chars.count, chars[lookahead] == "%" { lookahead += 1 }
            while lookahead < chars.count, chars[lookahead].isWhitespace { lookahead += 1 }
            if lookahead < chars.count { nextNonSpace = chars[lookahead] }

            let attachedToJapanese = (prevImmediate.map { isKana($0) || isHan($0) } ?? false)
                || (nextImmediate.map { isKana($0) || isHan($0) } ?? false)
                || (nextNonSpace.map { isKana($0) || isHan($0) } ?? false && !(prevNonSpace.map(isLatinLetter) ?? false))
            let attachedToEnglish = (prevImmediate.map(isLatinLetter) ?? false)
                || (nextImmediate.map(isLatinLetter) ?? false)
                || (nextNonSpace.map(isLatinLetter) ?? false)

            let useJapanese: Bool
            if attachedToJapanese {
                useJapanese = true
            } else if attachedToEnglish {
                useJapanese = false
            } else if lineHasCJK {
                useJapanese = hanIsJapanese
            } else if preferJapanese && !lineHasLatin {
                useJapanese = true
            } else {
                useJapanese = false
            }

            // 소수점 숫자 (예: 99.9, 3.14 — 단 1.2.3 같은 점 구분은 제외)
            if index + 1 < chars.count, chars[index] == ".", isAsciiDigit(chars[index + 1]) {
                var fracEnd = index + 1
                while fracEnd < chars.count, isAsciiDigit(chars[fracEnd]) { fracEnd += 1 }
                let isMultiDot = fracEnd < chars.count && chars[fracEnd] == "."
                if !isMultiDot {
                    let fracDigits = Array(chars[(index + 1)..<fracEnd])
                    index = fracEnd
                    if useJapanese {
                        var ja = japaneseNumberWord(digits) + "点" + fracDigits.map { japaneseDigitWord($0) }.joined()
                        if index < chars.count, chars[index] == "%" {
                            ja += "パーセント"
                            index += 1
                        }
                        out += ja
                    } else {
                        var en = englishNumberWord(digits) + " point " + fracDigits.map { englishDigitWord($0) }.joined(separator: " ")
                        if index < chars.count, chars[index] == "%" {
                            en += " percent"
                            index += 1
                        }
                        appendEnglishPiece(en, to: &out)
                    }
                    continue
                }
            }

            if useJapanese {
                var ja = japaneseNumberWord(digits)
                if index < chars.count, chars[index] == "%" {
                    ja += "パーセント"
                    index += 1
                }
                out += ja
            } else {
                var en = englishNumberWord(digits)
                if index < chars.count, chars[index] == "%" {
                    en += " percent"
                    index += 1
                }
                appendEnglishPiece(en, to: &out)
            }
        }
        return out
    }

    private static func appendEnglishPiece(_ piece: String, to out: inout String) {
        if let last = out.last, isLatinLetter(last) {
            out.append(" ")
        }
        out += piece
    }

    private static func japaneseNumberWord(_ digits: String) -> String {
        if digits.count > 1, digits.first == "0" {
            return digits.map(japaneseDigitWord).joined()
        }
        guard let value = Int(digits) else {
            return digits.map(japaneseDigitWord).joined()
        }
        if value == 0 { return "ゼロ" }
        return jaSpellOutFormatter.string(from: NSNumber(value: value)) ?? digits.map(japaneseDigitWord).joined()
    }

    private static func japaneseDigitWord(_ char: Character) -> String {
        switch char {
        case "0": return "ゼロ"
        case "1": return "一"
        case "2": return "二"
        case "3": return "三"
        case "4": return "四"
        case "5": return "五"
        case "6": return "六"
        case "7": return "七"
        case "8": return "八"
        case "9": return "九"
        default: return String(char)
        }
    }

    private static func englishNumberWord(_ digits: String) -> String {
        if digits.count > 1, digits.first == "0" {
            return digits.map(englishDigitWord).joined(separator: " ")
        }
        guard let value = Int(digits) else {
            return digits.map(englishDigitWord).joined(separator: " ")
        }
        if value == 0 { return "zero" }
        return (enSpellOutFormatter.string(from: NSNumber(value: value)) ?? digits)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: "")
    }

    private static func englishOrdinalWord(_ value: Int) -> String {
        let exact: [Int: String] = [
            1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth",
            6: "sixth", 7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
            11: "eleventh", 12: "twelfth", 13: "thirteenth", 14: "fourteenth", 15: "fifteenth",
            16: "sixteenth", 17: "seventeenth", 18: "eighteenth", 19: "nineteenth", 20: "twentieth",
            30: "thirtieth", 40: "fortieth", 50: "fiftieth", 60: "sixtieth",
            70: "seventieth", 80: "eightieth", 90: "ninetieth", 100: "hundredth",
        ]
        if let hit = exact[value] { return hit }
        let spelled = englishNumberWord(String(value))
        var parts = spelled.split(separator: " ").map(String.init)
        guard let last = parts.last else { return spelled + "th" }
        let rem = value % 10
        if rem > 0, let tail = exact[rem] {
            parts[parts.count - 1] = tail
            return parts.joined(separator: " ")
        }
        if last.hasSuffix("y") {
            parts[parts.count - 1] = String(last.dropLast()) + "ieth"
        } else {
            parts[parts.count - 1] = last + "th"
        }
        return parts.joined(separator: " ")
    }

    private static func englishDigitWord(_ char: Character) -> String {
        switch char {
        case "0": return "zero"
        case "1": return "one"
        case "2": return "two"
        case "3": return "three"
        case "4": return "four"
        case "5": return "five"
        case "6": return "six"
        case "7": return "seven"
        case "8": return "eight"
        case "9": return "nine"
        default: return String(char)
        }
    }

    /// 가나가 없는 한자는 중국어로 두고, 언어 인식이 일본어일 때만 일본어로 읽는다.
    private static func soundsJapanese(_ text: String) -> Bool {
        let cjkOnly = String(text.filter { isHan($0) || isKana($0) })
        let sample = cjkOnly.isEmpty ? text : cjkOnly
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage == .japanese
    }

    private static func collapseSpaces(_ text: String) -> String {
        var out = ""
        var pendingSpace = false
        for char in text {
            if char.isWhitespace {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace { out.append(" ") }
            pendingSpace = false
            out.append(char)
        }
        return out
    }

    private static func syllable(_ cho: Int, _ jung: Int, _ jong: Int = 0) -> String {
        let scalar = 0xAC00 + (cho * 21 + jung) * 28 + jong
        guard let unicode = UnicodeScalar(scalar) else { return "" }
        return String(unicode)
    }

    // MARK: - 일본어

    private static func japanese(_ text: String) -> String {
        var prepared = text
        for (target, kana) in japaneseReadingReplacements {
            prepared = prepared.replacingOccurrences(of: target, with: kana)
        }
        let source = prepared as CFString
        let full = CFRange(location: 0, length: CFStringGetLength(source))
        let locale = Locale(identifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(nil, source, full, kCFStringTokenizerUnitWord, locale)
        var words: [[Syl]] = []
        var pendingSokuon = false
        var attachNextToPrefix = false
        let prefixKanji: Set<String> = ["未", "非", "不", "無", "超", "再", "新", "全", "反", "真", "最", "大", "小", "高", "低"]
        while true {
            let type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            if type.rawValue == 0 { break }
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let raw = substring(source, tokenRange)
            var latin = (CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw == "は", latin == "ha" { latin = "wa" }
            if raw == "へ", latin == "he" { latin = "e" }
            if raw == "私", latin == "watakushi" { latin = "watashi" }
            if raw == "明日" || raw == "明日の" || raw == "明日も" || raw == "明日へ" {
                latin = latin.replacingOccurrences(of: "myounichi", with: "ashita")
                    .replacingOccurrences(of: "asu", with: "ashita")
            }
            let attachSuffix = attachNextToPrefix || shouldAttachJapaneseToken(raw: raw, latin: latin)
            attachNextToPrefix = prefixKanji.contains(raw)
            let token = romajiSyllables(latin)
            if token.syllables.isEmpty, !token.trailingSokuon {
                // 일본어로 못 읽는 한자(爱你처럼 중국어만 있는 글자)는 중국어 발음으로 남긴다.
                if raw.contains(where: isHan) {
                    let fallback = chinese(raw, orJapanese: false)
                    if !fallback.isEmpty {
                        words.append([Syl(cho: 11, jung: 0, raw: fallback)])
                    }
                }
                pendingSokuon = false
                continue
            }
            if (token.leadingSokuon || pendingSokuon), let lastWord = words.indices.last,
               let lastSyl = words[lastWord].indices.last {
                words[lastWord][lastSyl].jong = 19
                words[lastWord].append(contentsOf: token.syllables)
            } else if attachSuffix, let lastWord = words.indices.last {
                if token.syllables.first?.cho == 11, token.syllables.first?.jung == 18,
                   let firstJong = token.syllables.first?.jong, firstJong != 0,
                   let lastSyl = words[lastWord].indices.last, words[lastWord][lastSyl].jong == 0 {
                    words[lastWord][lastSyl].jong = firstJong
                    words[lastWord].append(contentsOf: token.syllables.dropFirst())
                } else {
                    words[lastWord].append(contentsOf: token.syllables)
                }
            } else if !token.syllables.isEmpty {
                words.append(token.syllables)
            }
            if token.trailingSokuon, let lastWord = words.indices.last,
               let lastSyl = words[lastWord].indices.last {
                words[lastWord][lastSyl].jong = 19
            }
            pendingSokuon = token.trailingSokuon
        }
        let pieces = words.map { $0.map(\.text).joined() }.filter { !$0.isEmpty }
        if pieces.isEmpty, text.contains(where: isHan) {
            return chinese(text, orJapanese: false)
        }
        return pieces.joined(separator: " ")
    }

    private static let japaneseReadingReplacements: [(String, String)] = [
        ("何時だって", "いつだって"), ("何時でも", "いつでも"), ("何時か", "いつか"), ("何時も", "いつも"),
        ("百回", "ひゃっかい"), ("一回", "いっかい"), ("六回", "ろっかい"), ("八回", "はっかい"), ("十回", "じゅっかい"),
        ("一分", "いっぷん"), ("三分", "さんぷん"), ("四分", "よんぷん"), ("六分", "ろっぷん"), ("八分", "はっぷん"), ("十分", "じゅっぷん"),
        ("一個", "いっこ"), ("六個", "ろっこ"), ("八個", "はっこ"), ("十個", "じゅっこ"),
        ("一杯", "いっぱい"), ("三杯", "さんばい"), ("一歩", "いっぽ"), ("一瞬", "いっしゅん"), ("一生", "いっしょう"), ("一緒", "いっしょ"),
        ("二十歳", "はたち"), ("一歳", "いっさい"), ("八歳", "はっさい"), ("十歳", "じゅっさい"),
        ("二十四時間", "にじゅうよじかん"), ("四時間", "よじかん"), ("四時", "よじ"), ("七時", "しちじ"), ("九時", "くじ"),
        ("三人", "さんにん"), ("四人", "よにん"), ("七人", "しちにん"),
    ]

    /// 조사·어미·보조용언처럼 앞말에 붙여 부르는 짧은 가나 조각은 띄어쓰지 않고 잇는다.
    private static func shouldAttachJapaneseToken(raw: String, latin: String) -> Bool {
        guard !raw.isEmpty, raw.allSatisfy(isKana) else { return false }
        if attachedJapaneseTokens.contains(raw) || attachedJapaneseRomaji.contains(latin.lowercased()) {
            return true
        }
        return raw.count == 1
    }

    private static let attachedJapaneseTokens: Set<String> = [
        "て", "で", "た", "だ", "ない", "たい", "たら", "たり", "てる", "でる", "てた", "でた", "てん", "でん", "てんだ", "でんだ",
        "れる", "られる", "せる", "させる", "れ", "せ", "られ", "させ", "ちゃう", "じゃう", "ちゃ", "じゃ",
        "よう", "ましょう", "ましょ", "だろう", "だろ", "でしょう", "でしょ",
        "から", "まで", "より", "だけ", "ばかり", "ほど", "くらい", "ぐらい", "なんて", "なんか",
        "って", "っぱなし", "いく", "くる", "おく", "みる",
    ]

    private static let attachedJapaneseRomaji: Set<String> = [
        "te", "de", "ta", "da", "nai", "tai", "tara", "tari", "teru", "deru", "teta", "deta", "ten", "den", "tenda", "denda",
        "reru", "rareru", "seru", "saseru", "re", "se", "rare", "sase", "chau", "jau", "cha", "ja",
        "you", "mashou", "masho", "darou", "daro", "deshou", "desho",
        "kara", "made", "yori", "dake", "bakari", "hodo", "kurai", "gurai", "nante", "nanka",
        "iku", "kuru", "oku", "miru",
    ]

    private static func substring(_ source: CFString, _ range: CFRange) -> String {
        let length = CFStringGetLength(source)
        guard range.location >= 0, range.length > 0, range.location + range.length <= length,
              let part = CFStringCreateWithSubstring(nil, source, range) else { return "" }
        return part as String
    }

    /// 실제 노래 발음에 맞춰 カ·タ·チャ·ツ 행을 ㅋ·ㅌ·ㅊ·츠로 적고, 촉음은 ㅅ 받침으로 적는다.
    private static func romajiSyllables(_ raw: String) -> (syllables: [Syl], leadingSokuon: Bool, trailingSokuon: Bool) {
        var text = raw.lowercased()
            .replacingOccurrences(of: "~tsu", with: "q")
            .replacingOccurrences(of: "~tu", with: "q")
        let macron: [Character: Character] = ["ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o"]
        text = String(text.map { macron[$0] ?? $0 })
        let parts = text.split(whereSeparator: { $0 == "'" || $0 == "’" })
        var syllables: [Syl] = []
        var leadingSokuon = false
        var trailingSokuon = false
        for part in parts {
            let state = parseRomaji(String(part), into: &syllables)
            if state.leadingSokuon { leadingSokuon = true }
            trailingSokuon = state.trailingSokuon
        }
        return (syllables, leadingSokuon, trailingSokuon)
    }

    private struct Syl {
        var cho: Int
        var jung: Int
        var jong: Int = 0
        var raw: String? = nil
        var text: String { raw ?? HangulReading.syllable(cho, jung, jong) }
    }

    private static func parseRomaji(_ raw: String, into syllables: inout [Syl]) -> (leadingSokuon: Bool, trailingSokuon: Bool) {
        let collapsed = collapseJapaneseLongVowels(raw.filter { $0.isLetter })
        let chars = Array(collapsed)
        var index = 0
        var leadingSokuon = false
        var trailingSokuon = false
        while index < chars.count {
            if let mark = sokuon(chars, index) {
                if !syllables.isEmpty {
                    syllables[syllables.count - 1].jong = 19
                    trailingSokuon = index + mark >= chars.count
                } else {
                    leadingSokuon = true
                }
                index += mark
                continue
            }
            trailingSokuon = false
            if let (cho, jung, length) = mora(chars, index) {
                syllables.append(Syl(cho: cho, jung: jung))
                index += length
                continue
            }
            if chars[index] == "n" {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                let jong = (next == "b" || next == "p" || next == "m") ? 16 : 4
                if syllables.isEmpty {
                    syllables.append(Syl(cho: 11, jung: 18, jong: jong))
                } else if syllables[syllables.count - 1].jong == 0 {
                    syllables[syllables.count - 1].jong = jong
                } else {
                    syllables.append(Syl(cho: 11, jung: 18, jong: jong))
                }
                index += 1
                continue
            }
            index += 1
        }
        return (leadingSokuon, trailingSokuon)
    }

    /// っ. `nn` 은 ん 이라 겹자음으로 보지 않고, `tch`/`cch` 는 ち 앞의 촉음이며 `q` 는 토큰 끝의 っ 표기다.
    private static func sokuon(_ chars: [Character], _ index: Int) -> Int? {
        if chars[index] == "q" { return 1 }
        guard index + 1 < chars.count else { return nil }
        if index + 2 < chars.count, chars[index] == "t" || chars[index] == "c",
           String(chars[index..<(index + 3)]) == "tch" || String(chars[index..<(index + 3)]) == "cch" {
            return 1
        }
        if chars[index] == chars[index + 1], chars[index] != "n", isRomajiConsonant(chars[index]) {
            return 1
        }
        return nil
    }

    private static func isRomajiConsonant(_ char: Character) -> Bool {
        "kgstdnhbpmrjcfywz".contains(char)
    }

    private static func collapseJapaneseLongVowels(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        while index < chars.count {
            if index + 1 < chars.count {
                let pair = String(chars[index...index + 1])
                if pair == "ou" || pair == "oo" || pair == "aa" || pair == "uu" || pair == "ii" {
                    out.append(chars[index])
                    index += 2
                    continue
                }
            }
            out.append(chars[index])
            index += 1
        }
        return out
    }

    private static func mora(_ chars: [Character], _ index: Int) -> (Int, Int, Int)? {
        for length in [3, 2, 1] where index + length <= chars.count {
            let key = String(chars[index..<(index + length)])
            if let hit = moraMap[key] { return (hit.0, hit.1, length) }
        }
        return nil
    }

    /// カ·タ·チャ 행은 언제나 ㅋ·ㅌ·ㅊ, ツ 는 츠로 적는다.
    private static let moraMap: [String: (Int, Int)] = {
        var map: [String: (Int, Int)] = [:]
        let rows: [(String, Int)] = [
            ("", 11), ("k", 15), ("g", 0), ("s", 9), ("z", 12),
            ("t", 16), ("d", 3), ("n", 2), ("h", 18), ("b", 7),
            ("p", 17), ("m", 6), ("r", 5),
        ]
        let vowels: [(String, Int)] = [("a", 0), ("i", 20), ("u", 13), ("e", 5), ("o", 8)]
        for (consonant, cho) in rows {
            for (vowel, jung) in vowels {
                map[consonant + vowel] = (cho, jung)
            }
        }
        let yoon: [(String, Int)] = [
            ("y", 11), ("ky", 15), ("gy", 0), ("ny", 2), ("hy", 18), ("by", 7),
            ("py", 17), ("my", 6), ("ry", 5),
        ]
        let yoonVowels: [(String, Int)] = [("a", 2), ("u", 17), ("o", 12)]
        for (consonant, cho) in yoon {
            for (vowel, jung) in yoonVowels {
                map[consonant + vowel] = (cho, jung)
            }
        }
        map["ye"] = (11, 7)
        map["su"] = (9, 18)
        map["zu"] = (12, 18)
        map["du"] = (3, 13)
        map["shi"] = (9, 20)
        map["si"] = (9, 20)
        map["sha"] = (9, 2)
        map["shu"] = (9, 17)
        map["sho"] = (9, 12)
        map["she"] = (9, 7)
        map["chi"] = (14, 20)
        map["ti"] = (16, 20)
        map["cha"] = (14, 0)
        map["chu"] = (14, 13)
        map["cho"] = (14, 8)
        map["che"] = (14, 5)
        map["tsu"] = (14, 18)
        map["tu"] = (16, 13)
        map["fu"] = (18, 13)
        map["fa"] = (17, 0)
        map["fi"] = (17, 20)
        map["fe"] = (17, 5)
        map["fo"] = (17, 8)
        map["va"] = (7, 0)
        map["vi"] = (7, 20)
        map["vu"] = (7, 13)
        map["ve"] = (7, 5)
        map["vo"] = (7, 8)
        map["ji"] = (12, 20)
        map["zi"] = (12, 20)
        map["di"] = (3, 20)
        map["ja"] = (12, 0)
        map["ju"] = (12, 13)
        map["jo"] = (12, 8)
        map["je"] = (12, 5)
        map["wa"] = (11, 9)
        map["wo"] = (11, 8)
        map["wi"] = (11, 20)
        map["we"] = (11, 5)
        return map
    }()

    // MARK: - 중국어

    private static func chinese(_ text: String, orJapanese: Bool = true) -> String {
        let tokens = transcribe(text, locale: "zh-Hans")
        let marks = Set("āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü".unicodeScalars)
        let readable = tokens.filter { token in
            token.unicodeScalars.allSatisfy { scalar in
                if scalar.value < 128 {
                    return scalar.properties.isAlphabetic || scalar == " " || scalar == "'"
                }
                return marks.contains(scalar)
            }
        }
        if readable.isEmpty { return orJapanese ? japanese(text) : text }
        let spoken = readable.map(pinyinToken).filter { !$0.isEmpty }
        return spoken.isEmpty ? (orJapanese ? japanese(text) : text) : spoken.joined(separator: " ")
    }

    private static func pinyinToken(_ raw: String) -> String {
        let flat = stripTones(raw.lowercased()).filter { $0.isLetter || $0 == "v" }
        let chars = Array(flat)
        var index = 0
        var parts: [String] = []
        while index < chars.count {
            guard let hit = matchPinyin(chars, index) else {
                index += 1
                continue
            }
            parts.append(renderPinyin(initial: hit.initial, final: hit.final))
            index += hit.length
        }
        return parts.joined()
    }

    private static func stripTones(_ text: String) -> String {
        let marks: [Character: Character] = [
            "ā": "a", "á": "a", "ǎ": "a", "à": "a",
            "ē": "e", "é": "e", "ě": "e", "è": "e",
            "ī": "i", "í": "i", "ǐ": "i", "ì": "i",
            "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
            "ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
            "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v", "ü": "v",
        ]
        return String(text.map { marks[$0] ?? $0 })
    }

    private static let pinyinInitials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]
    private static let pinyinFinals: [String] = [
        "iang", "iong", "uang", "ueng", "ang", "eng", "ong", "iao", "ian", "ing", "uai", "uan",
        "ai", "ei", "ao", "ou", "ia", "ie", "iu", "in", "ua", "uo", "ue", "ui", "ve", "er",
        "an", "en", "a", "o", "e", "i", "u", "v",
    ].sorted { $0.count > $1.count }

    private static func matchPinyin(_ chars: [Character], _ index: Int) -> (initial: String, final: String, length: Int)? {
        let rest = String(chars[index...])
        var best: (initial: String, final: String, length: Int)?
        for head in ([""] + pinyinInitials).sorted(by: { $0.count > $1.count }) {
            guard rest.hasPrefix(head) else { continue }
            let tail = rest.dropFirst(head.count)
            for final in pinyinFinals where tail.hasPrefix(final) {
                let length = head.count + final.count
                if best == nil || length > best!.length {
                    best = (head, final, length)
                }
                break
            }
        }
        return best
    }

    private static func renderPinyin(initial: String, final: String) -> String {
        var initial = initial
        var final = final
        if initial == "y" {
            switch final {
            case "a": final = "ia"
            case "e": final = "ie"
            case "o": final = "io"
            case "i": final = "i"
            case "u": final = "v"
            case "ao": final = "iao"
            case "ou": final = "iu"
            case "an": final = "ian"
            case "ang": final = "iang"
            case "in": final = "in"
            case "ing": final = "ing"
            case "ong": final = "iong"
            case "ue": final = "ve"
            case "uan": final = "van"
            case "un": final = "vn"
            default: break
            }
            initial = ""
        } else if initial == "w" {
            switch final {
            case "a": final = "ua"
            case "o": final = "uo"
            case "u": final = "u"
            case "ai": final = "uai"
            case "ei": final = "ui"
            case "an": final = "uan"
            case "en": final = "un"
            case "ang": final = "uang"
            case "eng": final = "ueng"
            default: break
            }
            initial = ""
        }
        if initial == "j" || initial == "q" || initial == "x" {
            switch final {
            case "u": final = "v"
            case "ue": final = "ve"
            case "uan": final = "van"
            case "un": final = "vn"
            default: break
            }
        }
        let buzz = final == "i" && ["zh", "ch", "sh", "r", "z", "c", "s"].contains(initial)
        let cho = pinyinCho(initial, final: final)
        return pinyinSyllables(cho: cho, final: final, buzz: buzz)
    }

    private static func pinyinCho(_ initial: String, final: String) -> Int {
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
        case "q", "ch", "c": return 14
        case "x", "sh": return 9
        case "z": return final == "i" ? 13 : 12
        case "s": return final == "i" ? 10 : 9
        default: return 11
        }
    }

    private static func pinyinSyllables(cho: Int, final: String, buzz: Bool) -> String {
        func one(_ jung: Int, _ jong: Int = 0) -> String { syllable(cho, jung, jong) }
        func rest(_ jung: Int, _ jong: Int = 0) -> String { syllable(11, jung, jong) }
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
        case "ong": return one(8, 21)
        case "er": return one(4, 8)
        case "ia": return one(2)
        case "ie": return one(7)
        case "iao": return one(2) + rest(8)
        case "iu": return one(17)
        case "ian": return one(2, 4)
        case "in": return one(20, 4)
        case "iang": return one(2, 21)
        case "ing": return one(20, 21)
        case "iong": return one(17, 21)
        case "io": return one(12)
        case "ua": return one(9)
        case "uo": return one(14)
        case "uai": return one(9) + rest(20)
        case "ui": return cho == 11 ? one(15) + rest(20) : one(13) + rest(20)
        case "uan": return one(9, 4)
        case "un": return one(13, 4)
        case "uang": return one(9, 21)
        case "ueng": return one(15, 21)
        case "ue": return one(14) + rest(5)
        case "ve": return one(16) + rest(5)
        case "van": return one(16) + rest(0, 4)
        case "vn": return one(16, 4)
        default: return ""
        }
    }

    // MARK: - 영어

    private enum LatinToken {
        case word(String)
        case sep(String)
    }

    private static func latin(_ text: String) -> String {
        var tokens: [LatinToken] = []
        var current = ""
        var isWord = false
        for char in text {
            let charIsWord = isLatinLetter(char) || char == "'"
            if current.isEmpty {
                isWord = charIsWord
                current.append(char)
            } else if charIsWord == isWord {
                current.append(char)
            } else {
                tokens.append(isWord ? .word(current) : .sep(current))
                isWord = charIsWord
                current = String(char)
            }
        }
        if !current.isEmpty {
            tokens.append(isWord ? .word(current) : .sep(current))
        }

        var out = ""
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .sep(let sep):
                out += sep
                i += 1
            case .word(let w1):
                let k1 = normalizeApostrophe(w1)
                if i + 4 < tokens.count,
                   case .sep(let s1) = tokens[i + 1], isSpaceOnly(s1),
                   case .word(let w2) = tokens[i + 2],
                   case .sep(let s2) = tokens[i + 3], isSpaceOnly(s2),
                   case .word(let w3) = tokens[i + 4] {
                    let phrase3 = "\(k1) \(normalizeApostrophe(w2)) \(normalizeApostrophe(w3))"
                    if let hit3 = phraseLexicon[phrase3] {
                        out += hit3
                        i += 5
                        continue
                    }
                }
                if i + 2 < tokens.count,
                   case .sep(let s1) = tokens[i + 1], isSpaceOnly(s1),
                   case .word(let w2) = tokens[i + 2] {
                    let k2 = normalizeApostrophe(w2)
                    if let linked = linkedPair(w1: w1, k1: k1, w2: w2, k2: k2, sep: s1) {
                        out += linked
                        i += 3
                        continue
                    }
                }
                out += englishWord(w1)
                i += 1
            }
        }
        return out
    }

    private static func normalizeApostrophe(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static func isSpaceOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }

    /// 원어민이 이어 부르는 두 단어 연음(`don't you` -> `돈츄`, `let it` -> `레릿`, `wake up` -> `웨이컵`, `don't stop` -> `돈 스탑`).
    private static func linkedPair(w1: String, k1: String, w2: String, k2: String, sep: String) -> String? {
        let pair = "\(k1) \(k2)"
        if let hit = phraseLexicon[pair] { return hit }
        let barePair = "\(k1.replacingOccurrences(of: "'", with: "")) \(k2.replacingOccurrences(of: "'", with: ""))"
        if barePair != pair, let hit = phraseLexicon[barePair] { return hit }

        // don't / can't / won't / didn't 뒤에 자음으로 시작하는 단어가 오면 끝 t를 삼킨다 (don't stop -> 돈 스탑).
        if let droppedNt = droppedNtStem[k1],
           let firstChar = k2.first(where: \.isLetter),
           isConsonantChar(firstChar), firstChar != "y" {
            return droppedNt + sep + englishWord(w2)
        }

        // -t/-d/-s/-z + your 연음 (close your -> 클로쥬어, miss your -> 미쓔어)
        if k2 == "your" || k2 == "yours" {
            let suffix = k2 == "yours" ? "어즈" : "어"
            if let youForm = phraseLexicon["\(k1) you"] {
                return youForm + suffix
            }
        }

        // 앞 단어가 ㅅ(-t), ㄱ(-k), ㅂ(-p), ㄹ(-l) 받침으로 끝나고 뒤에 모음 기능어(it, in, on, up, out, at)가 오면 연음한다.
        let spoken1 = englishWord(w1)
        guard let lastChar = spoken1.last,
              let scalar = lastChar.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        let offset = Int(scalar.value - 0xAC00)
        let cho = offset / (21 * 28)
        let jung = (offset / 28) % 21
        let jong = offset % 28
        let prefix = String(spoken1.dropLast())

        if let tail = vowelParticleTails[k2] {
            switch jong {
            case 19: // ㅅ 받침 (-t -> flap ㄹ 연음: let it -> 레릿, get out -> 게라웃)
                return prefix + syllable(cho, jung, 0) + tail.flapR
            case 1:  // ㄱ 받침 (-k -> ㅋ 연음: make it -> 메이킷, wake up -> 웨이컵)
                return prefix + syllable(cho, jung, 0) + tail.velarK
            case 17: // ㅂ 받침 (-p -> ㅍ 연음: keep it -> 키핏, drop out -> 드라파웃)
                return prefix + syllable(cho, jung, 0) + tail.labialP
            case 8:  // ㄹ 받침 (-l -> ㄹ+ㄹ 연음: feel it -> 필릿, fall in -> 폴린)
                return spoken1 + tail.flapR
            default:
                break
            }
        }
        return nil
    }

    private struct ParticleLink {
        var flapR: String
        var velarK: String
        var labialP: String
    }

    private static let vowelParticleTails: [String: ParticleLink] = [
        "it": ParticleLink(flapR: "릿", velarK: "킷", labialP: "핏"),
        "in": ParticleLink(flapR: "린", velarK: "킨", labialP: "핀"),
        "on": ParticleLink(flapR: "론", velarK: "콘", labialP: "폰"),
        "up": ParticleLink(flapR: "럽", velarK: "컵", labialP: "펍"),
        "out": ParticleLink(flapR: "라웃", velarK: "카웃", labialP: "파웃"),
        "at": ParticleLink(flapR: "랫", velarK: "캣", labialP: "팻"),
    ]

    private static let droppedNtStem: [String: String] = [
        "don't": "돈", "dont": "돈",
        "won't": "원", "wont": "원",
        "can't": "캔", "cant": "캔",
        "didn't": "디든", "didnt": "디든",
        "wouldn't": "우든", "wouldnt": "우든",
        "couldn't": "쿠든", "couldnt": "쿠든",
        "shouldn't": "슈든", "shouldnt": "슈든",
        "isn't": "이즌", "isnt": "이즌",
        "aren't": "안", "arent": "안",
        "wasn't": "워즌", "wasnt": "워즌",
        "weren't": "원", "werent": "원",
        "haven't": "해븐", "havent": "해븐",
        "hasn't": "해즌", "hasnt": "해즌",
        "hadn't": "해든", "hadnt": "해든",
        "ain't": "에인", "aint": "에인",
    ]

    private static func englishWord(_ raw: String) -> String {
        let key = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        if let hit = lexicon[key] { return hit }
        let bare = key.replacingOccurrences(of: "'", with: "")
        if bare != key, let hit = lexicon[bare] { return hit }
        if let inflected = inflectedLexicon(key, bare: bare) { return inflected }
        let letters = bare.filter { $0.isLetter }
        guard !letters.isEmpty else { return raw }
        if let romaji = romajiIfJapaneseWord(letters) { return romaji }
        let spoken = speak(letters)
        return spoken.isEmpty ? raw : spoken
    }

    /// 사전 단어에 축약형·복수형·접미사가 붙은 경우 어간 발음을 살려 읽는다.
    private static func inflectedLexicon(_ key: String, bare: String) -> String? {
        for (suffix, tail) in [("n't", "트"), ("'ll", "을"), ("'ve", "브"), ("'re", "어"), ("'d", "드")] {
            if key.hasSuffix(suffix) {
                let stem = String(key.dropLast(suffix.count))
                if let hit = lexicon[stem] { return hit + tail }
            }
        }
        if key.hasSuffix("'s") || key.hasSuffix("s'") {
            let stem = String(key.dropLast(2)).replacingOccurrences(of: "'", with: "")
            if let hit = lexicon[stem] ?? inflectedLexicon(stem, bare: stem) {
                return appendPlural(hit)
            }
        }
        for (suffix, tail) in [
            ("lessness", "리스니스"), ("fulness", "풀니스"),
            ("less", "리스"), ("ness", "니스"), ("ful", "풀"), ("ment", "먼트"), ("able", "어블"),
        ] {
            if bare.count > suffix.count + 2, bare.hasSuffix(suffix) {
                let stem = String(bare.dropLast(suffix.count))
                if let hit = lexicon[stem] ?? lexicon[stem + "e"] { return hit + tail }
            }
        }
        if bare.count > 4, bare.hasSuffix("ly") {
            let stem = String(bare.dropLast(2))
            if let hit = lexicon[stem] { return hit + "리" }
        }
        if bare.count > 5, bare.hasSuffix("ing") {
            let stem = String(bare.dropLast(3))
            if let hit = lexicon[stem] ?? lexicon[stem + "e"] {
                return attachIng(hit)
            }
        }
        if bare.count > 4, bare.hasSuffix("es") {
            let stem = String(bare.dropLast(2))
            if let hit = lexicon[stem] ?? lexicon[stem + "e"] {
                return appendPlural(hit)
            }
        }
        if bare.count > 3, bare.hasSuffix("s"), !bare.hasSuffix("ss") {
            let stem = String(bare.dropLast(1))
            if let hit = lexicon[stem] {
                return appendPlural(hit)
            }
        }
        if bare.count > 4, bare.hasSuffix("ed") {
            let stem = String(bare.dropLast(2))
            if let hit = lexicon[stem] ?? lexicon[stem + "e"] {
                return hit + "드"
            }
        }
        if bare.count > 4, bare.hasSuffix("er") {
            let stem = String(bare.dropLast(2))
            if let hit = lexicon[stem] ?? lexicon[stem + "e"] {
                return hit + "어"
            }
        }
        return nil
    }

    private static func appendPlural(_ spoken: String) -> String {
        guard let last = spoken.last,
              let scalar = last.unicodeScalars.first else { return spoken + "스" }
        if (0xAC00...0xD7A3).contains(scalar.value) {
            let offset = Int(scalar.value - 0xAC00)
            let cho = offset / (21 * 28)
            let jung = (offset / 28) % 21
            let jong = offset % 28
            let prefix = String(spoken.dropLast())
            if jong == 19 { // ㅅ 받침 (-t + s -> 츠: 나잇 -> 나이츠, 라잇 -> 라이츠)
                return prefix + syllable(cho, jung, 0) + "츠"
            }
            if jong == 1 || jong == 17 { // ㄱ/ㅂ 받침 (-k/-p + s -> 스: 메잌 -> 메잌스, 스탑 -> 스탑스)
                return spoken + "스"
            }
        }
        let voiceless: Set<Character> = ["트", "크", "프", "스", "쓰", "츠"]
        if last == "치" || last == "시" || last == "쉬" || last == "지" { return spoken + "즈" }
        return spoken + (voiceless.contains(last) ? "스" : "즈")
    }

    private static func attachIng(_ spoken: String) -> String {
        if spoken.hasSuffix("으") || spoken.hasSuffix("어") {
            return String(spoken.dropLast()) + "잉"
        }
        if spoken.hasSuffix("브") { return String(spoken.dropLast()) + "빙" }
        if spoken.hasSuffix("크") { return String(spoken.dropLast()) + "킹" }
        if spoken.hasSuffix("트") { return String(spoken.dropLast()) + "팅" }
        if spoken.hasSuffix("드") { return String(spoken.dropLast()) + "딩" }
        if spoken.hasSuffix("스") { return String(spoken.dropLast()) + "싱" }
        if spoken.hasSuffix("쓰") { return String(spoken.dropLast()) + "씽" }
        if spoken.hasSuffix("즈") { return String(spoken.dropLast()) + "징" }
        if spoken.hasSuffix("프") { return String(spoken.dropLast()) + "핑" }
        if spoken.hasSuffix("쉬") { return String(spoken.dropLast()) + "슁" }
        if spoken.hasSuffix("치") { return String(spoken.dropLast()) + "칭" }
        if let last = spoken.last,
           let scalar = last.unicodeScalars.first,
           (0xAC00...0xD7A3).contains(scalar.value) {
            let offset = Int(scalar.value - 0xAC00)
            let cho = offset / (21 * 28)
            let jung = (offset / 28) % 21
            let jong = offset % 28
            let prefix = String(spoken.dropLast())
            switch jong {
            case 19: return prefix + syllable(cho, jung, 0) + "링" // 웨잇 -> 웨이링, 겟 -> 게링
            case 1:  return prefix + syllable(cho, jung, 0) + "킹" // 메잌 -> 메이킹, 룩 -> 루킹
            case 17: return prefix + syllable(cho, jung, 0) + "핑" // 킵 -> 키핑, 드랍 -> 드라핑
            case 8:  return spoken + "링"                          // 필 -> 필링, 콜 -> 콜링
            case 4:  return prefix + syllable(cho, jung, 0) + "닝" // 런 -> 러닝, 번 -> 버닝
            case 16: return prefix + syllable(cho, jung, 0) + "밍" // 드림 -> 드리밍, 컴 -> 커밍
            default: break
            }
        }
        return spoken + "잉"
    }

    /// 로마자로 적힌 일본어 가사(`aizou`, `uzumaite` 등)는 일본어 고유 모라 패턴이 있을 때만 일본어로 읽는다.
    private static func romajiIfJapaneseWord(_ word: String) -> String? {
        guard word.count >= 5,
              let last = word.last, "aiueon".contains(last),
              !word.contains(where: { "lqvxyc".contains($0) }) else { return nil }
        let englishPatterns = [
            "ea", "oa", "oi", "oo", "ee", "ai", "au", "aw", "ew", "ow", "gh", "ph", "th", "wh", "ck",
            "ine", "one", "une", "ane", "ase", "ise", "ose", "use", "ate", "ite", "ote", "ute",
            "ure", "ire", "ore", "are", "ere", "age", "ige", "oge", "uge", "son", "ton", "don", "mon", "ron",
        ]
        if englishPatterns.contains(where: { word.contains($0) }) { return nil }
        let japanHints = [
            "aizou", "uzuma", "tsu", "kya", "kyu", "kyo", "sha", "shu", "sho", "cha", "chu", "cho",
            "nya", "nyu", "nyo", "hya", "hyu", "hyo", "mya", "myu", "myo", "rya", "ryu", "ryo",
            "shite", "naide", "kokoro", "watashi", "ashita", "hikari", "namida", "sakura", "sayonara", "arigato",
        ]
        guard japanHints.contains(where: { word.contains($0) }) else { return nil }
        let chars = Array(collapseJapaneseLongVowels(word))
        var index = 0
        var moras = 0
        while index < chars.count {
            if let mark = sokuon(chars, index) {
                index += mark
                continue
            }
            if let (_, _, length) = mora(chars, index) {
                moras += 1
                index += length
                continue
            }
            if chars[index] == "n" {
                moras += 1
                index += 1
                continue
            }
            return nil
        }
        guard moras >= 3 else { return nil }
        let syllables = romajiSyllables(word).syllables
        guard !syllables.isEmpty else { return nil }
        return syllables.map(\.text).joined()
    }

    /// 가사에 자주 나오는 말은 규칙을 타지 않고 읽는 대로 고정한다.
    private static let lexicon: [String: String] = {
        var map: [String: String] = [:]
        for line in lexiconTable.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { map[parts[0]] = parts[1] }
        }
        return map
    }()

    /// 원어민이 이어 부르는 구절 단위 연음 사전 (`don't you` -> `돈츄`, `want to` -> `워너`, `out of` -> `아우러브`).
    private static let phraseLexicon: [String: String] = {
        var map: [String: String] = [:]
        for line in phraseLexiconTable.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let splitIndex = trimmed.lastIndex(of: " ") else { continue }
            let key = String(trimmed[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: splitIndex)...]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: " ")
            if !key.isEmpty, !value.isEmpty { map[key] = value }
        }
        return map
    }()

    private static func speak(_ word: String) -> String {
        pack(atoms(of: word)).map(\.rendered).joined()
    }

    private enum Consonant { case b, ch, d, f, g, h, j, k, l, m, n, ng, p, r, s, ss, sh, t, v, w, y, z }
    private enum Vowel { case a, ae, eo, e, i, o, u, eu, yu, ay, ey, oy, aw }

    private enum Atom {
        case c(Consonant)
        case v(Vowel)
    }

    private struct Piece {
        var onset: [Consonant]
        var vowel: Vowel
        var coda: [Consonant]

        var rendered: String { HangulReading.render(self) }
    }

    private static func atoms(of word: String) -> [Atom] {
        let raw = Array(word)
        let count = raw.count
        var silent = Set<Int>()
        var long = Set<Int>()
        for index in 0..<count where isVowelChar(raw[index]) {
            if index + 2 < count, isConsonantChar(raw[index + 1]), raw[index + 2] == "e",
               index + 3 == count || (index + 4 == count && raw[index + 3] == "s") || (index + 4 == count && raw[index + 3] == "d"),
               !(raw[index] == "e" && raw[index + 1] == "e") {
                silent.insert(index + 2)
                long.insert(index)
            } else if index + 3 < count, raw[index + 1] == "n", raw[index + 2] == "g", raw[index + 3] == "e",
                      index + 4 == count || (index + 5 == count && (raw[index + 4] == "s" || raw[index + 4] == "d" || raw[index + 4] == "r"))
                      || (index + 6 == count && raw[index + 4] == "r" && raw[index + 5] == "s") {
                // change, strange, stranger, changed 등
                if index + 4 == count || (index + 5 == count && (raw[index + 4] == "s" || raw[index + 4] == "d")) {
                    silent.insert(index + 3)
                }
                long.insert(index)
            } else if index + 3 < count, isConsonantChar(raw[index + 1]),
                      raw[index + 2] == "e", raw[index + 3] == "r",
                      index + 4 == count || (index + 5 == count && raw[index + 4] == "s") {
                // maker, later 처럼 e 가 빠져도 앞 모음이 긴 채 -er 이 붙는다.
                long.insert(index)
            } else if index + 2 < count, isConsonantChar(raw[index + 1]), raw[index + 2] == "y", index + 3 == count {
                if index == 0 || !raw[..<index].contains(where: isVowelChar) {
                    long.insert(index)
                }
            }
        }

        var out: [Atom] = []
        var index = 0
        func hasPrefix(_ text: String) -> Bool {
            let prefix = Array(text)
            guard index + prefix.count <= count else { return false }
            return Array(raw[index..<(index + prefix.count)]) == prefix
        }
        func emit(_ atoms: [Atom], consuming: Int) {
            out.append(contentsOf: atoms)
            index += consuming
        }
        let prefixes: [(String, [Atom])] = [
            ("ssion", [.c(.sh), .v(.eo), .c(.n)]),
            ("tion", [.c(.sh), .v(.eo), .c(.n)]),
            ("cion", [.c(.sh), .v(.eo), .c(.n)]),
            ("sion", [.c(.sh), .v(.eo), .c(.n)]),
            ("ture", [.c(.ch), .v(.eo)]),
            ("sure", [.c(.j), .v(.eo)]),
            ("ther", [.c(.d), .v(.eo)]),
            ("ight", [.v(.ay), .c(.t)]),
            ("eigh", [.v(.ey)]),
            ("ought", [.v(.o), .c(.t)]),
            ("aught", [.v(.o), .c(.t)]),
            ("air", [.v(.e), .v(.eo)]),
            ("are", [.v(.e), .v(.eo)]),
            ("ear", [.v(.i), .v(.eo)]),
            ("ire", [.v(.ay), .v(.eo)]),
            ("yre", [.v(.ay), .v(.eo)]),
            ("eer", [.v(.i), .v(.eo)]),
            ("ore", [.v(.o), .v(.eo)]),
            ("our", [.v(.aw), .v(.eo)]),
            ("ous", [.v(.eo), .c(.s)]),
            ("igh", [.v(.ay)]),
            ("dge", [.c(.j)]),
            ("tch", [.c(.ch)]),
            ("nge", [.c(.n), .c(.j)]),
            ("ngi", [.c(.n), .c(.j), .v(.i)]),
            ("ph", [.c(.f)]),
            ("ch", [.c(.ch)]),
            ("sh", [.c(.sh)]),
            ("th", [.c(.ss)]),
            ("ck", [.c(.k)]),
            ("nk", [.c(.ng), .c(.k)]),
            ("qu", [.c(.k), .c(.w)]),
            ("wh", [.c(.w)]),
            ("wr", [.c(.r)]),
            ("kn", [.c(.n)]),
            ("ee", [.v(.i)]),
            ("oo", [.v(.u)]),
            ("ea", [.v(.i)]),
            ("ie", [.v(.i)]),
            ("ai", [.v(.ey)]),
            ("ay", [.v(.ey)]),
            ("ey", [.v(.ey)]),
            ("oi", [.v(.oy)]),
            ("oy", [.v(.oy)]),
            ("ou", [.v(.aw)]),
            ("au", [.v(.o)]),
            ("aw", [.v(.o)]),
            ("oa", [.v(.o)]),
            ("ew", [.v(.yu)]),
        ]
        while index < count {
            if silent.contains(index) {
                index += 1
                continue
            }
            if index == 0, raw[index] == "a", index + 2 < count,
               raw[index + 1] == "l" || raw[index + 1] == "w" || raw[index + 1] == "r" || raw[index + 1] == "g" || raw[index + 1] == "s",
               isVowelChar(raw[index + 2]), count >= 5 {
                emit([.v(.eo)], consuming: 1)
                continue
            }
            if index == 0, hasPrefix("ex"), index + 2 < count, isConsonantChar(raw[index + 2]) {
                emit([.v(.i), .c(.k), .c(.s)], consuming: 2)
                continue
            }
            if index == 0, hasPrefix("con") || hasPrefix("com"), index + 3 < count, isConsonantChar(raw[index + 3]) {
                let tail: Consonant = raw[index + 2] == "m" ? .m : .n
                emit([.c(.k), .v(.eo), .c(tail)], consuming: 3)
                continue
            }
            if index == 0, hasPrefix("be") || hasPrefix("de") || hasPrefix("re"),
               index + 2 < count, isConsonantChar(raw[index + 2]), count >= 6 {
                let head: Consonant = raw[0] == "b" ? .b : (raw[0] == "d" ? .d : .r)
                emit([.c(head), .v(.i)], consuming: 2)
                continue
            }
            if hasPrefix("wor"), index + 3 == count || (index + 3 < count && isConsonantChar(raw[index + 3])) {
                emit([.c(.w), .v(.eo)], consuming: 3)
                continue
            }
            if hasPrefix("war"), index + 3 == count || (index + 3 < count && isConsonantChar(raw[index + 3])) {
                emit([.c(.w), .v(.o)], consuming: 3)
                continue
            }
            if (hasPrefix("ches") || hasPrefix("shes")) && index + 4 == count {
                let head: Consonant = raw[index] == "c" ? .ch : .sh
                emit([.c(head), .v(.i), .c(.z)], consuming: 4)
                continue
            }
            if (hasPrefix("ces") || hasPrefix("ses") || hasPrefix("zes") || hasPrefix("ges")) && index + 3 == count {
                let head: Consonant = (raw[index] == "g" || raw[index] == "z") ? .j : .s
                emit([.c(head), .v(.i), .c(.s)], consuming: 3)
                continue
            }
            if hasPrefix("ed"), index + 2 == count, index > 1 {
                let prev = raw[index - 1]
                if prev == "t" || prev == "d" {
                    emit([.v(.i), .c(.d)], consuming: 2)
                } else {
                    emit([.c(.d)], consuming: 2)
                }
                continue
            }
            if (hasPrefix("er") || hasPrefix("or") || hasPrefix("ar")) && (index + 2 == count || (index + 3 == count && raw[index + 2] == "s")) {
                emit([.v(.eo)], consuming: 2)
                continue
            }
            if (hasPrefix("ir") || hasPrefix("ur") || hasPrefix("er")),
               index + 2 < count, isConsonantChar(raw[index + 2]) {
                emit([.v(.eo)], consuming: 2)
                continue
            }
            if hasPrefix("ar"), index + 2 == count || (index + 2 < count && isConsonantChar(raw[index + 2])) {
                emit([.v(.a)], consuming: 2)
                continue
            }
            if hasPrefix("or"), index + 2 == count || (index + 2 < count && isConsonantChar(raw[index + 2])) {
                emit([.v(.o)], consuming: 2)
                continue
            }
            if hasPrefix("ng") {
                if index + 2 < count, raw[index + 2] == "e" || raw[index + 2] == "i" || raw[index + 2] == "y" {
                    emit([.c(.n), .c(.j)], consuming: 2)
                } else {
                    emit([.c(.ng)], consuming: 2)
                }
                continue
            }
            if hasPrefix("ow") {
                let atEnd = index + 2 == count || (index + 3 == count && raw[index + 2] == "s")
                emit([.v(atEnd ? .o : .aw)], consuming: 2)
                continue
            }
            if hasPrefix("le"), index > 0, isConsonantChar(raw[index - 1]), index + 2 == count {
                emit([.v(.eu), .c(.l)], consuming: 2)
                continue
            }
            if (hasPrefix("al") || hasPrefix("el")), index > 1, index + 2 == count {
                emit([.v(.eo), .c(.l)], consuming: 2)
                continue
            }
            var matched = false
            for (prefix, atoms) in prefixes where hasPrefix(prefix) {
                emit(atoms, consuming: prefix.count)
                matched = true
                break
            }
            if matched { continue }
            let char = raw[index]
            if char == "x" {
                emit(index == 0 ? [.c(.z)] : [.c(.k), .c(.s)], consuming: 1)
                continue
            }
            if char == "y", index + 1 < count, isVowelChar(raw[index + 1]) {
                emit([.c(.y)], consuming: 1)
                continue
            }
            if isVowelChar(char) || char == "y" {
                emit([.v(vowel(char, at: index, in: raw, long: long.contains(index)))], consuming: 1)
                continue
            }
            // 단어 첫머리 s + 모음은 원어민 발음처럼 된소리 ㅆ 으로 적는다 (so -> 쏘, sing -> 씽, summer -> 써머).
            if index == 0, char == "s", index + 1 < count, isVowelChar(raw[index + 1]) {
                emit([.c(.ss)], consuming: 1)
                continue
            }
            // 모음(또는 모음+r) 뒤의 t/tt 가 비강세 모음 어미(-er, -le, -al, -el, -y, -ing, -ed, -om) 앞에 오면 미국식 플랩 ㄹ 로 적는다 (water -> 워러, little -> 리를, party -> 파리).
            if char == "t", index > 0, isFlapT(in: raw, at: index) {
                let consume = (index + 1 < count && raw[index + 1] == "t") ? 2 : 1
                emit([.c(.r)], consuming: consume)
                continue
            }
            if index + 1 < count, char == raw[index + 1], isConsonantChar(char) {
                index += 1
            }
            emit([.c(consonant(char, next: index + 1 < count ? raw[index + 1] : nil))], consuming: 1)
        }
        return out
    }

    private static func isFlapT(in raw: [Character], at index: Int) -> Bool {
        let prev = raw[index - 1]
        let afterVowelOrR = isVowelChar(prev) || (prev == "r" && index >= 2 && isVowelChar(raw[index - 2]))
        guard afterVowelOrR else { return false }
        let afterT = (index + 1 < raw.count && raw[index + 1] == "t") ? index + 2 : index + 1
        guard afterT < raw.count else { return false }
        let tail = String(raw[afterT...])
        let flapTails = [
            "er", "ers", "le", "les", "al", "als", "el", "els",
            "y", "ies", "ied", "ing", "ed", "om", "oms", "iful", "able",
        ]
        return flapTails.contains(tail)
    }

    private static func vowel(_ char: Character, at index: Int, in raw: [Character], long: Bool) -> Vowel {
        switch char {
        case "a": return long ? .ey : .ae
        case "e": return long ? .i : .e
        case "i": return long ? .ay : .i
        case "o": return (long || index + 1 == raw.count) ? .o : .a
        case "u": return long ? .yu : .eo
        case "y":
            let onlyVowel = !raw[..<index].contains(where: isVowelChar)
            return (index + 1 == raw.count && onlyVowel) ? .ay : .i
        default: return .eo
        }
    }

    private static func consonant(_ char: Character, next: Character?) -> Consonant {
        switch char {
        case "b": return .b
        case "c":
            if next == "e" || next == "i" || next == "y" { return .s }
            return .k
        case "d": return .d
        case "f": return .f
        case "g":
            if next == "e" || next == "i" || next == "y" { return .j }
            return .g
        case "h": return .h
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "p": return .p
        case "q": return .k
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "v": return .v
        case "w": return .w
        case "x": return .k
        case "z": return .z
        default: return .s
        }
    }

    private static func isVowelChar(_ char: Character) -> Bool {
        "aeiouy".contains(char)
    }

    private static func isConsonantChar(_ char: Character) -> Bool {
        char.isLetter && !isVowelChar(char)
    }

    private static func pack(_ atoms: [Atom]) -> [Piece] {
        var pieces: [Piece] = []
        var pending: [Consonant] = []
        for atom in atoms {
            switch atom {
            case .c(let consonant):
                pending.append(consonant)
            case .v(let vowel):
                var onset = pending
                pending = []
                if !pieces.isEmpty, pieces[pieces.count - 1].coda.isEmpty {
                    if onset == [.l] {
                        // 모음 사이의 l 은 앞 음절 받침 ㄹ 과 뒤 음절 초성 ㄹ 로 이어 읽는다 (feeling -> 필링).
                        pieces[pieces.count - 1].coda = [.l]
                    } else if let head = onset.first, onset.count >= 2, batchim(head) != nil {
                        pieces[pieces.count - 1].coda = [head]
                        onset.removeFirst()
                    }
                }
                pieces.append(Piece(onset: onset, vowel: vowel, coda: []))
            }
        }
        guard !pending.isEmpty else { return pieces }
        if !pieces.isEmpty, pieces[pieces.count - 1].coda.isEmpty {
            pieces[pieces.count - 1].coda = pending
        } else {
            for consonant in pending {
                pieces.append(Piece(onset: [consonant], vowel: .eu, coda: []))
            }
        }
        return pieces
    }

    private static func render(_ piece: Piece) -> String {
        var onset = piece.onset
        var palatal = false
        var rounded = false
        if onset.last == .y {
            palatal = true
            onset.removeLast()
        } else if onset.last == .w {
            rounded = true
            onset.removeLast()
        }
        if onset.last == .sh { palatal = true }
        let liquidCluster = onset.count >= 2 && onset.last == .l
        var head = ""
        if onset.count >= 2 {
            let prefix = Array(onset.dropLast())
            for (idx, consonant) in prefix.enumerated() {
                let jong = (liquidCluster && idx == prefix.count - 1) ? 8 : 0
                head += syllable(cho(consonant), 18, jong)
            }
        }
        let choIndex = onset.last.map { cho($0) } ?? 11
        let coda = piece.coda.filter { $0 != .r }
        return head + renderVowel(cho: choIndex, vowel: piece.vowel, coda: coda, palatal: palatal, rounded: rounded)
    }

    private static func renderVowel(cho: Int, vowel: Vowel, coda: [Consonant], palatal: Bool, rounded: Bool) -> String {
        switch vowel {
        case .ay:
            return diphthong(cho: cho, first: palatal ? 2 : 0, second: 20, coda: coda)
        case .ey:
            return diphthong(cho: cho, first: palatal ? 7 : 5, second: 20, coda: coda)
        case .oy:
            return diphthong(cho: cho, first: palatal ? 12 : 8, second: 20, coda: coda)
        case .aw:
            return diphthong(cho: cho, first: palatal ? 2 : 0, second: 13, coda: coda)
        default:
            let jung = glide(jung(vowel), cho: cho, palatal: palatal, rounded: rounded)
            return codaSyllable(cho: cho, jung: jung, coda: coda, diphthongTail: false)
        }
    }

    private static func diphthong(cho: Int, first: Int, second: Int, coda: [Consonant]) -> String {
        syllable(cho, first) + codaSyllable(cho: 11, jung: second, coda: coda, diphthongTail: true)
    }

    private static func codaSyllable(cho: Int, jung: Int, coda: [Consonant], diphthongTail: Bool) -> String {
        var rest = coda
        var jong = 0
        if rest == [.t, .s] {
            return syllable(cho, jung, 0) + syllable(14, 18)
        }
        if let head = rest.first {
            if let nasalOrLiquid = batchim(head) {
                jong = nasalOrLiquid
                rest.removeFirst()
            } else if let stop = stopBatchim(head),
                      rest.count == 1 || (rest.count == 2 && (rest[1] == .s || rest[1] == .z) && head != .t) {
                jong = stop
                rest.removeFirst()
            }
        }
        var text = syllable(cho, jung, jong)
        for consonant in rest {
            switch consonant {
            case .sh:
                text += syllable(9, 16)
            case .ch:
                text += syllable(14, 20)
            case .j:
                text += syllable(12, 20)
            default:
                text += syllable(self.cho(consonant), 18)
            }
        }
        return text
    }

    private static func stopBatchim(_ consonant: Consonant) -> Int? {
        switch consonant {
        case .k, .g: return 1
        case .p, .b: return 17
        case .t: return 19
        default: return nil
        }
    }

    private static func jung(_ vowel: Vowel) -> Int {
        switch vowel {
        case .a: return 0
        case .ae: return 1
        case .eo: return 4
        case .e: return 5
        case .o: return 8
        case .u: return 13
        case .yu: return 17
        case .eu: return 18
        case .i: return 20
        case .ay, .ey, .oy, .aw: return 4
        }
    }

    private static func glide(_ jung: Int, cho: Int, palatal: Bool, rounded: Bool) -> Int {
        if rounded {
            switch jung {
            case 0: return 9
            case 1: return 10
            case 4: return 14
            case 5: return 15
            case 20: return 16
            default: break
            }
        }
        if palatal {
            switch jung {
            case 0: return 2
            case 1: return 3
            case 4: return 6
            case 5: return 7
            case 8: return 12
            case 13: return 17
            case 20 where cho == 9: return 16
            default: break
            }
        }
        return jung
    }

    private static func cho(_ consonant: Consonant) -> Int {
        switch consonant {
        case .g: return 0
        case .n: return 2
        case .d: return 3
        case .r, .l: return 5
        case .m: return 6
        case .b, .v: return 7
        case .s, .sh: return 9
        case .ss: return 10
        case .ng, .w, .y: return 11
        case .j, .z: return 12
        case .ch: return 14
        case .k: return 15
        case .t: return 16
        case .p, .f: return 17
        case .h: return 18
        }
    }

    private static func batchim(_ consonant: Consonant) -> Int? {
        switch consonant {
        case .n: return 4
        case .l: return 8
        case .m: return 16
        case .ng: return 21
        default: return nil
        }
    }

    private static func transcribe(_ text: String, locale identifier: String) -> [String] {
        let source = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(source))
        let locale = Locale(identifier: identifier) as CFLocale
        let tokenizer = CFStringTokenizerCreate(nil, source, range, kCFStringTokenizerUnitWord, locale)
        var tokens: [String] = []
        while true {
            let type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            if type.rawValue == 0 { break }
            guard let value = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) else { continue }
            let token = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { tokens.append(token) }
        }
        return tokens
    }
}

extension HangulReading {
    fileprivate static let phraseLexiconTable = """
    not at all 나래롤
    at all 애롤
    it all 이롤
    that all 대롤
    for all 포올
    after all 애프터롤
    don't you 돈츄
    dont you 돈츄
    won't you 원츄
    wont you 원츄
    can't you 캔츄
    cant you 캔츄
    didn't you 디든츄
    didnt you 디든츄
    wouldn't you 우든츄
    wouldnt you 우든츄
    couldn't you 쿠든츄
    couldnt you 쿠든츄
    shouldn't you 슈든츄
    shouldnt you 슈든츄
    aren't you 안츄
    arent you 안츄
    isn't you 이즌츄
    isnt you 이즌츄
    did you 디쥬
    would you 우쥬
    could you 쿠쥬
    should you 슈쥬
    had you 해쥬
    want you 원츄
    wanted you 워니쥬
    need you 니쥬
    needed you 니디쥬
    got you 가츄
    get you 게츄
    let you 레츄
    set you 쎄츄
    put you 푸츄
    hit you 히츄
    meet you 미츄
    bet you 베츄
    hate you 헤이츄
    hurt you 허츄
    trust you 트러스츄
    hold you 홀쥬
    told you 톨쥬
    find you 파인쥬
    found you 파운쥬
    around you 어라운쥬
    behind you 비하인쥬
    beside you 비싸이쥬
    inside you 인싸이쥬
    without you 위다우츄
    about you 어바우츄
    with you 위츄
    miss you 미쓔
    kiss you 키쓔
    pass you 패쓔
    bless you 블레쓔
    lose you 루쥬
    use you 유쥬
    choose you 추쥬
    close you 클로쥬
    cause you 커쥬
    'cause you 커쥬
    because you 비커쥬
    what you 와츄
    that you 대츄
    when you 웨뉴
    if you 이퓨
    of you 어뷰
    love you 러뷰
    give you 기뷰
    leave you 리뷰
    save you 쎄이뷰
    have you 해뷰
    tell you 텔유
    call you 콜유
    feel you 필유
    want to 워너
    going to 거너
    got to 가러
    ought to 오러
    have to 해프투
    has to 해스투
    had to 해투
    used to 유스투
    supposed to 써포즈투
    trying to 트라이너
    out of 아우러브
    kind of 카인더
    sort of 쏘러
    lot of 라러
    lots of 라츠어브
    all of 올러브
    full of 풀러브
    tired of 타이어더브
    sick of 씨커브
    think of 띵커브
    dream of 드리머브
    made of 메이더브
    afraid of 어프레이더브
    instead of 인스테더브
    front of 프런터브
    top of 타퍼브
    side of 싸이더브
    part of 파러브
    heart of 하러브
    end of 엔더브
    middle of 미들러브
    rest of 레스터브
    best of 베스터브
    most of 모스터브
    none of 너너브
    one of 워너브
    some of 써머브
    both of 보써브
    each of 이쳐브
    let me 레미
    give me 기미
    tell me 텔미
    call me 콜미
    feel me 필미
    hold me 홀미
    find me 파인미
    send me 쎈미
    mind me 마인미
    remind me 리마인미
    behind me 비하인미
    around me 어라운미
    let it 레릿
    get it 게릿
    got it 가릿
    put it 푸릿
    hit it 히릿
    set it 쎄릿
    cut it 커릿
    shut it 셔릿
    forget it 포게릿
    make it 메이킷
    take it 테이킷
    shake it 쉐이킷
    break it 브레이킷
    fake it 페이킷
    like it 라이킷
    kick it 키킷
    rock it 라킷
    check it 체킷
    work it 워킷
    keep it 키핏
    drop it 드라핏
    stop it 스타핏
    pop it 파핏
    hold it 홀딧
    find it 파인딧
    need it 니딧
    read it 리딧
    feel it 필릿
    call it 콜릿
    pull it 풀릿
    tell it 텔릿
    fill it 필릿
    kill it 킬릿
    roll it 롤릿
    say it 쎄잇
    do it 두잇
    know it 노잇
    throw it 쓰로잇
    show it 쇼잇
    blow it 블로잇
    grow it 그로잇
    lose it 루짓
    use it 유짓
    choose it 추짓
    close it 클로짓
    love it 러빗
    give it 기빗
    leave it 리빗
    live it 리빗
    have it 해빗
    move it 무빗
    prove it 프루빗
    save it 쎄이빗
    touch it 터칫
    watch it 와칫
    catch it 캐칫
    reach it 리칫
    push it 푸쉣
    wish it 위쉣
    worth it 워씟
    with it 위딧
    in it 이닛
    on it 오닛
    is it 이짓
    was it 워짓
    does it 더짓
    come on 커몬
    hold on 홀돈
    move on 무본
    go on 고온
    keep on 키폰
    put on 푸론
    get on 게론
    sit on 씨론
    wait on 웨이론
    right on 라이론
    turn on 터논
    hang on 행온
    count on 카운톤
    depend on 디펜돈
    come in 커민
    fall in 폴린
    all in 올린
    fill in 필린
    call in 콜린
    pull in 풀린
    roll in 롤린
    give in 기빈
    live in 리빈
    believe in 빌리빈
    deep in 디핀
    step in 스테핀
    drop in 드라핀
    jump in 점핀
    back in 배킨
    stuck in 스터킨
    lock in 라킨
    kick in 키킨
    walk in 워킨
    sink in 씽킨
    break in 브레이킨
    take in 테이킨
    lost in 로스틴
    get in 게린
    let in 레린
    put in 푸린
    fit in 피린
    sit in 씨린
    wake up 웨이컵
    make up 메이컵
    take up 테이컵
    break up 브레이컵
    shake up 쉐이컵
    pick up 피컵
    look up 루컵
    lock up 라컵
    back up 배컵
    pack up 패컵
    hook up 후컵
    fuck up 퍼컵
    shut up 셔럽
    get up 게럽
    got up 가럽
    put up 푸럽
    set up 쎄럽
    cut up 커럽
    light up 라이럽
    lit up 리럽
    heat up 히럽
    split up 스플리럽
    start up 스타럽
    caught up 코럽
    give up 기법
    gave up 게이법
    live up 리법
    save up 쎄이법
    keep up 키펍
    step up 스테펍
    wrap up 래펍
    pop up 파펍
    end up 엔덥
    stand up 스탠덥
    hold up 홀덥
    build up 빌덥
    fold up 폴더업
    pull up 풀럽
    fill up 필럽
    call up 콜럽
    roll up 롤럽
    turn up 터넙
    burn up 버넙
    open up 오프넙
    clean up 클리넙
    run up 러넙
    grow up 그로업
    show up 쇼업
    blow up 블로업
    slow up 슬로업
    throw up 쓰로업
    go up 고업
    wake me 웨잌미
    make me 메잌미
    take me 테잌미
    break me 브레잌미
    shake me 쉐잌미
    like me 라잌미
    let out 레라웃
    get out 게라웃
    got out 가라웃
    put out 푸라웃
    cut out 커라웃
    set out 쎄라웃
    sit out 씨라웃
    shut out 셔라웃
    spit out 스피라웃
    right out 라이라웃
    night out 나이라웃
    light out 라이라웃
    shout out 샤우라웃
    find out 파인다웃
    found out 파운다웃
    stand out 스탠다웃
    hand out 핸다웃
    hold out 홀다웃
    fade out 페이다웃
    hide out 하이다웃
    ride out 라이다웃
    slide out 슬라이다웃
    work out 워카웃
    walk out 워카웃
    talk out 토카웃
    look out 루카웃
    check out 체카웃
    black out 블래카웃
    knock out 나카웃
    lock out 라카웃
    rock out 라카웃
    break out 브레이카웃
    take out 테이카웃
    make out 메이카웃
    shake out 쉐이카웃
    freak out 프리카웃
    speak out 스피카웃
    sneak out 스니카웃
    stick out 스티카웃
    kick out 키카웃
    pick out 피카웃
    step out 스테파웃
    drop out 드라파웃
    keep out 키파웃
    pop out 파파웃
    slip out 슬리파웃
    flip out 플리파웃
    trip out 트리파웃
    help out 헬파웃
    jump out 점파웃
    run out 러나웃
    ran out 래나웃
    burn out 버나웃
    turn out 터나웃
    worn out 워나웃
    all out 올라웃
    fall out 폴라웃
    call out 콜라웃
    pull out 풀라웃
    roll out 롤라웃
    sell out 쎌라웃
    chill out 칠라웃
    spell out 스펠라웃
    fill out 필라웃
    watch out 와챠웃
    reach out 리챠웃
    stretch out 스트레챠웃
    catch out 캐챠웃
    wash out 워샤웃
    push out 푸샤웃
    rush out 러샤웃
    crash out 크래샤웃
    pass out 패싸웃
    miss out 미싸웃
    cross out 크로싸웃
    go out 고아웃
    throw out 쓰로아웃
    blow out 블로아웃
    show out 쇼아웃
    grow out 그로아웃
    figure out 피겨라웃
    look at 루캣
    back at 배캣
    laugh at 래팻
    right now 라잇_나우
    good night 군나잇
    all night 올라잇
    all right 올라잇
    alright 올라잇
    last night 래스나잇
    one more 원_모어
    no more 노_모어
    once more 원스_모어
    right here 라잇_히어
    right there 라잇_데어
    out there 아웃_데어
    in there 인_데어
    over there 오버_데어
    up there 업_데어
    down there 다운_데어
    """

    fileprivate static let lexiconTable = """
    a 어
    i 아이
    the 더
    an 언
    oh 오
    yeah 예
    yes 예스
    no 노
    go 고
    so 쏘
    know 노
    dont 돈트
    don't 돈트
    can't 캔트
    cant 캔트
    wont 원트
    won't 원트
    didnt 디든트
    didn't 디든트
    wouldnt 우든트
    wouldn't 우든트
    couldnt 쿠든트
    couldn't 쿠든트
    shouldnt 슈든트
    shouldn't 슈든트
    isnt 이즌트
    isn't 이즌트
    arent 안트
    aren't 안트
    wasnt 워즌트
    wasn't 워즌트
    werent 원트
    weren't 원트
    havent 해븐트
    haven't 해븐트
    hasnt 해즌트
    hasn't 해즌트
    hadnt 해든트
    hadn't 해든트
    zero 제로
    one 원
    two 투
    three 쓰리
    four 포
    five 파이브
    six 씩스
    seven 쎄븐
    eight 에잇
    nine 나인
    ten 텐
    eleven 일레븐
    twelve 트웰브
    thirteen 써틴
    fourteen 포틴
    fifteen 피프틴
    sixteen 씩스틴
    seventeen 쎄븐틴
    eighteen 에이틴
    nineteen 나인틴
    twenty 트웬티
    thirty 써리
    forty 포리
    fifty 피프티
    sixty 씩스티
    seventy 쎄븐티
    eighty 에이리
    ninety 나인티
    hundred 헌드레드
    thousand 싸우전드
    million 밀리언
    billion 빌리언
    first 퍼스트
    second 쎄컨드
    third 써드
    fourth 포쓰
    fifth 피프쓰
    sixth 씩스쓰
    seventh 쎄븐쓰
    eighth 에잇쓰
    ninth 나인쓰
    tenth 텐쓰
    percent 퍼센트
    point 포인트
    time 타임
    life 라이프
    world 월드
    girl 걸
    boy 보이
    man 맨
    woman 우먼
    feel 필
    feeling 필링
    feels 필즈
    away 어웨이
    tonight 투나잇
    today 투데이
    tomorrow 투마로우
    yesterday 예스터데이
    music 뮤직
    song 쏭
    songs 쏭즈
    sing 씽
    singing 씽잉
    sings 씽즈
    sang 쌩
    sung 썽
    dance 댄스
    dancing 댄싱
    light 라잇
    lights 라이츠
    lighter 라이러
    lighting 라이링
    dark 다크
    star 스타
    stars 스타즈
    sky 스카이
    eyes 아이즈
    eye 아이
    smile 스마일
    kiss 키스
    hold 홀드
    holding 홀딩
    hand 핸드
    hands 핸즈
    soul 쏘울
    sound 싸운드
    sounds 싸운즈
    side 싸이드
    sides 싸이즈
    same 쎄임
    some 썸
    soon 쑨
    sad 쌔드
    safe 쎄이프
    save 쎄이브
    saving 쎄이빙
    sick 씩
    sit 씻
    sitting 씨링
    such 써치
    suck 썩
    super 쑤퍼
    season 씨즌
    seasons 씨즌즈
    secret 씨크릿
    secrets 씨크릿츠
    sex 쎅스
    sexy 쎅시
    send 쎈드
    sense 쎈스
    since 씬스
    simple 씸플
    single 씽글
    silver 씰버
    mind 마인드
    body 바디
    beautiful 뷰리풀
    beauty 뷰리
    crazy 크레이지
    lonely 론리
    happy 해피
    blue 블루
    red 레드
    black 블랙
    white 와잇
    gold 골드
    rain 레인
    sun 썬
    sunny 써니
    sunday 썬데이
    moon 문
    home 홈
    love 러브
    loved 러브드
    loving 러빙
    lover 러버
    loves 러브즈
    heart 하트
    hearts 하츠
    day 데이
    days 데이즈
    morning 모닝
    free 프리
    real 리얼
    true 트루
    right 라잇
    stop 스탑
    wait 웨잇
    waiting 웨이링
    stay 스테이
    leave 리브
    leaving 리빙
    gone 곤
    die 다이
    dying 다잉
    live 리브
    living 리빙
    alive 얼라이브
    cry 크라이
    crying 크라잉
    pain 페인
    fall 폴
    falling 폴링
    run 런
    running 러닝
    walk 워크
    walking 워킹
    rock 락
    roll 롤
    rolling 롤링
    beat 빝
    rhythm 리듬
    phone 폰
    call 콜
    calling 콜링
    voice 보이스
    name 네임
    face 페이스
    touch 터치
    friend 프렌드
    friends 프렌즈
    people 피플
    everything 에브리띵
    everyone 에브리원
    anything 애니띵
    anyone 애니원
    nothing 너씽
    something 썸씽
    someone 썸원
    somebody 썸바디
    nobody 노바디
    anybody 애니바디
    thing 띵
    things 띵즈
    money 머니
    power 파워
    party 파리
    dream 드림
    dreams 드림즈
    dreaming 드리밍
    sleep 슬립
    sleeping 슬리핑
    goodbye 굿바이
    hello 헬로
    sorry 쏘리
    please 플리즈
    thanks 땡스
    thank 땡크
    king 킹
    queen 퀸
    angel 에인절
    fire 파이어
    burn 번
    burning 버닝
    cold 콜드
    hot 핫
    cool 쿨
    water 워러
    tears 티어즈
    broken 브로큰
    high 하이
    low 로우
    up 업
    down 다운
    out 아웃
    over 오버
    under 언더
    again 어게인
    never 네버
    always 올웨이즈
    forever 포레버
    whatever 와레버
    whenever 웨네버
    wherever 웨어레버
    however 하우에버
    together 투게더
    alone 얼론
    only 온리
    just 저스트
    like 라잌
    likes 라잌스
    want 원트
    wanted 워니드
    wanting 원팅
    need 니드
    needed 니디드
    take 테잌
    takes 테잌스
    taking 테이킹
    make 메잌
    makes 메잌스
    making 메이킹
    wake 웨잌
    waking 웨이킹
    fake 페잌
    mistake 미스테잌
    heartbreak 하트브레잌
    give 기브
    giving 기빙
    let 렛
    letting 레링
    come 컴
    coming 커밍
    back 백
    now 나우
    here 히어
    there 데어
    where 웨어
    when 웬
    what 왓
    who 후
    why 와이
    how 하우
    this 디스
    that 댓
    these 디즈
    those 도즈
    with 위드
    without 위다웃
    within 위딘
    from 프럼
    your 유어
    youre 유어
    you're 유어
    im 아임
    i'm 아임
    its 잇츠
    it's 잇츠
    we're 위어
    they're 데어
    theyre 데어
    you've 유브
    we've 위브
    they've 데이브
    you'll 유을
    we'll 위을
    they'll 데일
    he's 히즈
    she's 쉬즈
    they 데이
    them 뎀
    their 데어
    theirs 데어즈
    me 미
    my 마이
    mine 마인
    we 위
    us 어스
    he 히
    him 힘
    his 히즈
    she 쉬
    her 허
    hers 허즈
    it 잇
    to 투
    of 어브
    and 앤드
    in 인
    on 온
    at 앳
    by 바이
    for 포
    is 이즈
    be 비
    been 빈
    being 비잉
    am 앰
    are 아
    was 워즈
    were 워
    but 벗
    if 이프
    or 오어
    not 낫
    can 캔
    will 윌
    all 올
    about 어바웃
    into 인투
    through 쓰루
    because 비커즈
    cause 커즈
    'cause 커즈
    cuz 커즈
    gonna 거너
    wanna 워너
    gotta 가러
    outta 아우러
    lemme 레미
    gimme 기미
    imma 아이머
    dunno 더노
    tryna 트라이너
    hey 헤이
    la 라
    na 나
    ooh 우
    whoa 워
    wow 와우
    baby 베이비
    babe 베이브
    darling 달링
    honey 허니
    sweet 스윝
    little 리를
    bottle 바를
    battle 배를
    settle 쎄를
    good 굿
    bad 배드
    new 뉴
    old 올드
    young 영
    long 롱
    way 웨이
    ways 웨이즈
    shine 샤인
    shining 샤이닝
    bright 브라잇
    sight 싸잇
    fight 파잇
    fighting 파이링
    tight 타잇
    flight 플라잇
    might 마잇
    late 레잇
    later 레이러
    hate 헤잇
    hating 헤이링
    fate 페잇
    state 스테잇
    date 데잇
    gate 게잇
    memory 메모리
    memories 메모리즈
    remember 리멤버
    forget 포겟
    miss 미스
    missing 미씽
    think 띵크
    thinking 띵킹
    say 쎄이
    says 쎄즈
    said 쎄드
    tell 텔
    telling 텔링
    talk 토크
    talking 토킹
    word 워드
    words 워즈
    story 스토리
    melody 멜로디
    move 무브
    moving 무빙
    shake 쉐잌
    shaking 쉐이킹
    turn 턴
    turning 터닝
    around 어라운드
    still 스틸
    maybe 메이비
    really 리얼리
    every 에브리
    everybody 에브리바디
    somewhere 썸웨어
    wonderful 원더풀
    pretty 프리리
    magic 매직
    heaven 헤븐
    hell 헬
    god 갓
    lord 로드
    night 나잇
    nights 나이츠
    you 유
    ya 야
    yo 요
    let's 레츠
    lets 레츠
    i'll 아일
    i'd 아이드
    i've 아이브
    play 플레이
    playing 플레잉
    game 게임
    ain't 에인트
    what's 왓츠
    that's 댓츠
    there's 데어즈
    here's 히어즈
    who's 후즈
    kinda 카인더
    bye 바이
    sugar 슈거
    heartbeat 하트빝
    fly 플라이
    flying 플라잉
    higher 하이어
    believe 빌리브
    believing 빌리빙
    hope 호프
    hopeless 호플리스
    place 플레이스
    firework 파이어웤
    worth 워쓰
    peach 피치
    peaches 피치즈
    georgia 조지아
    warm 웜
    church 처치
    worship 워쉽
    dog 도그
    lie 라이
    lies 라이즈
    stranger 스트레인저
    strangers 스트레인저즈
    exchange 익스체인지
    exchanging 익스체인징
    glance 글랜스
    glances 글랜시즈
    wonder 원더
    wondering 원더링
    chance 챈스
    chances 챈시즈
    change 체인지
    changing 체인징
    oughta 오러
    much 머치
    smooth 스무드
    criminal 크리미널
    automatic 오토매틱
    systematic 씨스테매틱
    hydromatic 하이드로매틱
    thought 쏘트
    caught 코트
    bought 보트
    brought 브로트
    fought 포트
    taught 토트
    enough 이너프
    tough 터프
    rough 러프
    laugh 래프
    ghost 고스트
    most 모스트
    lost 로스트
    both 보쓰
    truth 트루쓰
    youth 유쓰
    south 싸우쓰
    mouth 마우쓰
    earth 어쓰
    breath 브레쓰
    breathe 브리드
    breathing 브리딩
    blood 블러드
    double 더블
    trouble 트러블
    couple 커플
    country 컨트리
    front 프런트
    done 던
    none 넌
    son 썬
    won 원
    once 원스
    ocean 오션
    emotion 이모션
    vision 비전
    even 이븐
    ever 에버
    heavy 헤비
    ready 레디
    already 올레디
    head 헤드
    dead 데드
    instead 인스테드
    weather 웨더
    pleasure 플레저
    treasure 트레저
    break 브레잌
    breaking 브레이킹
    great 그레잇
    wear 웨어
    swear 스웨어
    hear 히어
    hearing 히어링
    near 니어
    dear 디어
    clear 클리어
    fear 피어
    year 이어
    years 이어즈
    early 얼리
    learn 런
    learning 러닝
    heard 허드
    search 써치
    searching 써칭
    women 위민
    human 휴먼
    moment 모먼트
    minute 미닛
    minutes 미닛츠
    hour 아워
    hours 아워즈
    flower 플라워
    flowers 플라워즈
    shower 샤워
    our 아워
    door 도어
    floor 플로어
    poor 푸어
    sure 슈어
    pure 퓨어
    desire 디자이어
    tired 타이어드
    quiet 콰이엇
    silence 싸일런스
    silent 싸일런트
    island 아일랜드
    sign 싸인
    fine 파인
    line 라인
    wine 와인
    divine 디바인
    forgive 포기브
    calm 캄
    half 해프
    would 우드
    could 쿠드
    should 슈드
    put 풋
    putting 푸링
    push 푸쉬
    pushing 푸슁
    wish 위쉬
    wishing 위슁
    fish 피쉬
    rush 러쉬
    crush 크러쉬
    crash 크래쉬
    flash 플래쉬
    wash 워쉬
    fresh 프레쉬
    pull 풀
    pulling 풀링
    full 풀
    stood 스투드
    foot 풋
    book 북
    look 룩
    looking 루킹
    took 툭
    shook 슉
    school 스쿨
    rule 룰
    rules 룰즈
    issue 이쓔
    view 뷰
    few 퓨
    knew 뉴
    flew 플루
    grew 그루
    threw 쓰루
    throw 쓰로
    throwing 쓰로잉
    champagne 샴페인
    machine 머신
    gasoline 개솔린
    other 아더
    another 어나더
    mother 마더
    brother 브라더
    father 파더
    sister 씨스터
    better 베러
    letter 레러
    matter 매러
    butter 버러
    bitter 비러
    glitter 글리러
    shatter 섀러
    bottom 바럼
    summer 써머
    winter 윈터
    spring 스프링
    autumn 오럼
    city 씨리
    pity 피리
    duty 듀리
    dirty 더리
    shorty 쇼리
    shawty 쇼리
    danger 데인저
    dangerous 데인저러스
    do 두
    does 더즈
    did 디드
    doing 두잉
    watch 와치
    watching 와칭
    catch 캐치
    catching 캐칭
    bring 브링
    set 쎗
    setting 쎄링
    alight 얼라잇
    fantasy 판타지
    reality 리얼리리
    got 갓
    get 겟
    getting 게링
    hit 힛
    hitting 히링
    cut 컷
    cutting 커링
    shut 셧
    shutting 셔링
    shit 쉣
    magnet 매그넷
    shape 쉐입
    type 타입
    keep 킵
    keeping 키핑
    deep 딥
    step 스텝
    drop 드랍
    dropping 드라핑
    top 탑
    pop 팝
    lot 랏
    shot 샷
    spot 스팟
    clock 클락
    block 블락
    lock 락
    knock 낙
    shock 샥
    pocket 파켓
    rocket 라켓
    problem 프라블럼
    promise 프라미스
    follow 팔로우
    tomorrow 투마로우
    dollar 달러
    doctor 닥터
    special 스페셜
    """
}
