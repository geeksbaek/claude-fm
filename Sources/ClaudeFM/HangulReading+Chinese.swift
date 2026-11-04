import Foundation

/// 중국어: 병음을 한글 음절로 옮긴다.
extension HangulReading {
    static func chinese(_ text: String, orJapanese: Bool = true) -> String {
        let tokens = mandarinTokens(text)
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

    static func pinyinToken(_ raw: String) -> String {
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

    static func stripTones(_ text: String) -> String {
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

    static let pinyinInitials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]
    static let pinyinFinals: [String] = [
        "iang", "iong", "uang", "ueng", "ang", "eng", "ong", "iao", "ian", "ing", "uai", "uan",
        "ai", "ei", "ao", "ou", "ia", "ie", "iu", "in", "ua", "uo", "ue", "ui", "ve", "er",
        "an", "en", "a", "o", "e", "i", "u", "v",
    ].sorted { $0.count > $1.count }

    static func matchPinyin(_ chars: [Character], _ index: Int) -> (initial: String, final: String, length: Int)? {
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

    static func renderPinyin(initial: String, final: String) -> String {
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

    static func pinyinCho(_ initial: String, final: String) -> Int {
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

    static func pinyinSyllables(cho: Int, final: String, buzz: Bool) -> String {
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
}
