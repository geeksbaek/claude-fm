import Foundation

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
                } else if kind == .latin, chars[next].isWhitespace || chars[next] == "-" || chars[next] == "&",
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

    enum Kind { case hangul, japanese, han, latin, other }

    static func kind(of char: Character, hanIsJapanese: Bool) -> Kind {
        if isHangul(char) { return .hangul }
        if isKana(char) { return .japanese }
        if isHan(char) { return hanIsJapanese ? .japanese : .han }
        if isLatinLetter(char) || char == "'" { return .latin }
        return .other
    }

    /// 전각 영숫자·기호·아포스트로피만 반각으로 바꾸고, 가타카나는 전각 그대로 둔다.
    static func normalizeWidth(_ text: String) -> String {
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

    static func scalarValue(_ char: Character) -> UInt32? {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else { return nil }
        return scalar.value
    }

    static func isHangul(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value)
    }

    static func isKana(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x3040...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value) || (0xFF65...0xFF9F).contains(value)
    }

    /// 한자. 일본어의 々·〆·〇 도 한자와 함께 읽는다.
    static func isHan(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x3005...0x3007).contains(value)
    }

    static func isLatinLetter(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) || (0xC0...0x24F).contains(value)
    }

    static func isAsciiDigit(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x30...0x39).contains(value)
    }

    static let jaSpellOutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ja")
        formatter.numberStyle = .spellOut
        return formatter
    }()

    static let enSpellOutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter
    }()

    static let enOrdinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        return formatter
    }()

    /// 일본어·영어 가사에 들어 있는 숫자를 문맥에 맞는 발음용 글자로 풀어 적는다.
    static func expandNumbers(in raw: String, hanIsJapanese: Bool, preferJapanese: Bool) -> String {
        // 영어 줄에 따로 떨어진 & 는 and 로 읽는다 (Blood sweat & tears)
        let text = raw.contains(" & ") && raw.contains(where: isLatinLetter) ? raw.replacingOccurrences(of: " & ", with: " and ") : raw
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
            var grouped = false
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
                    grouped = true
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
            // 가나 없는 중국어 줄에서 한자 곁의 숫자는 중국어 숫자로 읽는다.
            let useChinese = useJapanese && !hanIsJapanese

            // 소수점 숫자 (예: 99.9, 3.14 — 단 1.2.3 같은 점 구분은 제외)
            if index + 1 < chars.count, chars[index] == ".", isAsciiDigit(chars[index + 1]) {
                var fracEnd = index + 1
                while fracEnd < chars.count, isAsciiDigit(chars[fracEnd]) { fracEnd += 1 }
                let isMultiDot = fracEnd < chars.count && chars[fracEnd] == "."
                if !isMultiDot {
                    let fracDigits = Array(chars[(index + 1)..<fracEnd])
                    index = fracEnd
                    if useChinese {
                        var zh = chineseNumberWord(digits, before: nil) + "点" + chineseDigits(String(fracDigits))
                        if index < chars.count, chars[index] == "%" {
                            zh = "百分之" + zh
                            index += 1
                        }
                        out += zh
                    } else if useJapanese {
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

            if useChinese {
                if index < chars.count, chars[index] == "%" {
                    out += "百分之" + chineseNumberWord(digits, before: nil)
                    index += 1
                } else {
                    out += chineseNumberWord(digits, before: index < chars.count ? chars[index] : nil, after: prevImmediate)
                }
            } else if useJapanese {
                var ja = japaneseNumberWord(digits)
                if index < chars.count, chars[index] == "%" {
                    ja += "パーセント"
                    index += 1
                }
                out += ja
            } else {
                // No.1, #1 은 넘버 원으로 읽는다
                var en = ""
                for sign in ["No. ", "No.", "no. ", "no.", "NO. ", "NO.", "#"] where out.hasSuffix(sign) {
                    let before = out.dropLast(sign.count)
                    guard before.last.map({ !isLatinLetter($0) }) ?? true else { continue }
                    out = String(before)
                    en = "number "
                    break
                }
                let percent = index < chars.count && chars[index] == "%"
                if en.isEmpty, !grouped, !percent, digits.count == 4, let value = Int(digits), let year = englishYearWord(value) {
                    en = year
                } else {
                    en += englishNumberWord(digits)
                }
                if percent {
                    en += " percent"
                    index += 1
                }
                appendEnglishPiece(en, to: &out)
                if !percent, let meridiem = englishMeridiem(chars, at: index) {
                    // 3 a.m., 10pm
                    out += " " + meridiem.reading
                    index = meridiem.end
                } else if index < chars.count, isLatinLetter(chars[index]) {
                    // 24K, 2gether 는 띄워 읽고, 90s 의 s 는 붙인다
                    let pluralS = (chars[index] == "s" || chars[index] == "S") && !(index + 1 < chars.count && isLatinLetter(chars[index + 1]))
                    if !pluralS { out.append(" ") }
                }
            }
        }
        return out
    }

    static func appendEnglishPiece(_ piece: String, to out: inout String) {
        if let last = out.last, isLatinLetter(last) {
            out.append(" ")
        }
        out += piece
    }

    static func japaneseNumberWord(_ digits: String) -> String {
        if digits.count > 1, digits.first == "0" {
            return digits.map(japaneseDigitWord).joined()
        }
        guard let value = Int(digits) else {
            return digits.map(japaneseDigitWord).joined()
        }
        if value == 0 { return "ゼロ" }
        return jaSpellOutFormatter.string(from: NSNumber(value: value)) ?? digits.map(japaneseDigitWord).joined()
    }

    static func japaneseDigitWord(_ char: Character) -> String {
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

    static func englishNumberWord(_ digits: String) -> String {
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

    /// 숫자 뒤 a.m., pm 은 에이엠, 피엠으로 읽는다.
    static func englishMeridiem(_ chars: [Character], at start: Int) -> (reading: String, end: Int)? {
        var k = start
        while k < chars.count, chars[k] == " " { k += 1 }
        guard k < chars.count else { return nil }
        let first = chars[k].lowercased()
        guard first == "a" || first == "p" else { return nil }
        var j = k + 1
        if j < chars.count, chars[j] == "." { j += 1 }
        guard j < chars.count, chars[j].lowercased() == "m" else { return nil }
        j += 1
        if j < chars.count, chars[j] == "." { j += 1 }
        if j < chars.count, isLatinLetter(chars[j]) { return nil }
        return (first == "a" ? "에이엠" : "피엠", j)
    }

    /// 네 자리 해는 두 자리씩 끊어 읽는다 (1999 -> nineteen ninety nine, 2024 -> twenty twenty four). 2000~2009 는 그대로.
    static func englishYearWord(_ value: Int) -> String? {
        guard (1100...2999).contains(value), !(2000...2009).contains(value), value % 1000 != 0 else { return nil }
        let head = englishNumberWord(String(value / 100))
        let low = value % 100
        if low == 0 { return head + " hundred" }
        if low < 10 { return head + " oh " + englishNumberWord(String(low)) }
        return head + " " + englishNumberWord(String(low))
    }

    static func englishOrdinalWord(_ value: Int) -> String {
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

    static func englishDigitWord(_ char: Character) -> String {
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

    /// 가나가 없는 한자 줄은 중국어로 읽고, 일본에서만 쓰는 글자(気·涙·桜·々 …)가 있을 때만 일본어로 읽는다.
    /// 짧은 한자 줄은 언어 인식이 자주 틀리고, 일본어 곡은 곡 전체의 가나로 이미 일본어로 읽는다.
    static func soundsJapanese(_ text: String) -> Bool {
        text.contains { japaneseOnlyKanji.contains($0) }
    }

    static func collapseSpaces(_ text: String) -> String {
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

    static func syllable(_ cho: Int, _ jung: Int, _ jong: Int = 0) -> String {
        let scalar = 0xAC00 + (cho * 21 + jung) * 28 + jong
        guard let unicode = UnicodeScalar(scalar) else { return "" }
        return String(unicode)
    }
}
