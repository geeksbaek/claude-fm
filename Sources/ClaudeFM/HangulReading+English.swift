import Foundation

/// 영어: 낱말과 이어 부르는 구절을 한글로 적는다.
extension HangulReading {
    enum LatinToken {
        case word(String)
        case sep(String)
    }

    static func latin(_ text: String) -> String {
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

    static func normalizeApostrophe(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    static func isSpaceOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }

    /// 원어민이 이어 부르는 두 단어 연음(`don't you` -> `돈츄`, `let it` -> `레릿`, `wake up` -> `웨이컵`, `don't stop` -> `돈 스탑`).
    static func linkedPair(w1: String, k1: String, w2: String, k2: String, sep: String) -> String? {
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

    struct ParticleLink {
        var flapR: String
        var velarK: String
        var labialP: String
    }

    static let vowelParticleTails: [String: ParticleLink] = [
        "it": ParticleLink(flapR: "릿", velarK: "킷", labialP: "핏"),
        "in": ParticleLink(flapR: "린", velarK: "킨", labialP: "핀"),
        "on": ParticleLink(flapR: "론", velarK: "콘", labialP: "폰"),
        "up": ParticleLink(flapR: "럽", velarK: "컵", labialP: "펍"),
        "out": ParticleLink(flapR: "라웃", velarK: "카웃", labialP: "파웃"),
        "at": ParticleLink(flapR: "랫", velarK: "캣", labialP: "팻"),
    ]

    static let droppedNtStem: [String: String] = [
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

    static func englishWord(_ raw: String) -> String {
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
    static func inflectedLexicon(_ key: String, bare: String) -> String? {
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

    static func appendPlural(_ spoken: String) -> String {
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

    static func attachIng(_ spoken: String) -> String {
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
    static func romajiIfJapaneseWord(_ word: String) -> String? {
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
    static let lexicon: [String: String] = {
        var map: [String: String] = [:]
        for line in lexiconTable.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { map[parts[0]] = parts[1] }
        }
        return map
    }()

    /// 원어민이 이어 부르는 구절 단위 연음 사전 (`don't you` -> `돈츄`, `want to` -> `워너`, `out of` -> `아우러브`).
    static let phraseLexicon: [String: String] = {
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

    static func speak(_ word: String) -> String {
        pack(atoms(of: word)).map(\.rendered).joined()
    }

    enum Consonant { case b, ch, d, f, g, h, j, k, l, m, n, ng, p, r, s, ss, sh, t, v, w, y, z }
    enum Vowel { case a, ae, eo, e, i, o, u, eu, yu, ay, ey, oy, aw }

    enum Atom {
        case c(Consonant)
        case v(Vowel)
    }

    struct Piece {
        var onset: [Consonant]
        var vowel: Vowel
        var coda: [Consonant]

        var rendered: String { HangulReading.render(self) }
    }

    static func atoms(of word: String) -> [Atom] {
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

    static func isFlapT(in raw: [Character], at index: Int) -> Bool {
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

    static func vowel(_ char: Character, at index: Int, in raw: [Character], long: Bool) -> Vowel {
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

    static func consonant(_ char: Character, next: Character?) -> Consonant {
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

    static func isVowelChar(_ char: Character) -> Bool {
        "aeiouy".contains(char)
    }

    static func isConsonantChar(_ char: Character) -> Bool {
        char.isLetter && !isVowelChar(char)
    }

    static func pack(_ atoms: [Atom]) -> [Piece] {
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

    static func render(_ piece: Piece) -> String {
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

    static func renderVowel(cho: Int, vowel: Vowel, coda: [Consonant], palatal: Bool, rounded: Bool) -> String {
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

    static func diphthong(cho: Int, first: Int, second: Int, coda: [Consonant]) -> String {
        syllable(cho, first) + codaSyllable(cho: 11, jung: second, coda: coda, diphthongTail: true)
    }

    static func codaSyllable(cho: Int, jung: Int, coda: [Consonant], diphthongTail: Bool) -> String {
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

    static func stopBatchim(_ consonant: Consonant) -> Int? {
        switch consonant {
        case .k, .g: return 1
        case .p, .b: return 17
        case .t: return 19
        default: return nil
        }
    }

    static func jung(_ vowel: Vowel) -> Int {
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

    static func glide(_ jung: Int, cho: Int, palatal: Bool, rounded: Bool) -> Int {
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

    static func cho(_ consonant: Consonant) -> Int {
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

    static func batchim(_ consonant: Consonant) -> Int? {
        switch consonant {
        case .n: return 4
        case .l: return 8
        case .m: return 16
        case .ng: return 21
        default: return nil
        }
    }
}
