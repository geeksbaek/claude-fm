import Foundation

/// 영어: 낱말과 이어 부르는 구절을 한글로 적는다.
extension HangulReading {
    enum LatinToken {
        case word(String)
        case sep(String)
    }

    // MARK: - 줄

    static func latin(_ text: String) -> String {
        let tokens = latinTokens(text)
        var out = ""
        var i = 0
        while i < tokens.count {
            guard case .word(let w1) = tokens[i] else {
                if case .sep(let sep) = tokens[i] { out += sep }
                i += 1
                continue
            }
            let next = followingWord(tokens, after: i)
            if let next, let third = followingWord(tokens, after: next.index) {
                let key = "\(normalizeApostrophe(w1)) \(normalizeApostrophe(next.text)) \(normalizeApostrophe(third.text))"
                if let hit = phraseLexicon[key] {
                    out += hit
                    i = third.index + 1
                    continue
                }
            }
            if let next, let linked = linkedPair(w1, next.text) {
                out += linked
                i = next.index + 1
                continue
            }
            out += wordInContext(w1, next: next?.text)
            i += 1
        }
        return out
    }

    /// 글자와 아포스트로피를 낱말로 묶는다. 글자 사이의 `-`, `&` 는 낱말 안에 둔다 (hip-hop, R&B).
    static func latinTokens(_ text: String) -> [LatinToken] {
        let chars = Array(text)
        func wordChar(_ k: Int) -> Bool {
            k >= 0 && k < chars.count && (isLatinLetter(chars[k]) || chars[k] == "'")
        }
        var tokens: [LatinToken] = []
        var current = ""
        var isWord = false
        for (k, char) in chars.enumerated() {
            let joiner = (char == "-" || char == "&") && wordChar(k - 1) && wordChar(k + 1)
            let charIsWord = joiner || wordChar(k)
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
        return tokens
    }

    static func followingWord(_ tokens: [LatinToken], after index: Int) -> (index: Int, text: String)? {
        guard index + 2 < tokens.count,
              case .sep(let sep) = tokens[index + 1], isSpaceOnly(sep),
              case .word(let word) = tokens[index + 2] else { return nil }
        return (index + 2, word)
    }

    static func normalizeApostrophe(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    static func isSpaceOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }

    /// 뒤 낱말에 따라 달라지는 읽기 (`the end` -> `디 엔드`, `don't stop` -> `돈 스탑`).
    static func wordInContext(_ word: String, next: String?) -> String {
        let key = normalizeApostrophe(word)
        if let next {
            if key == "the", startsWithVowelSound(next) { return "디" }
            if let stem = droppedNtStem[key] { return stem }
        }
        return englishWord(word)
    }

    /// 뒤 낱말이 모음 소리로 시작하는지 (`the` 를 `디` 로 읽을지).
    static func startsWithVowelSound(_ word: String) -> Bool {
        let reading = englishWord(word)
        guard let first = reading.first, let head = hangulParts(first), head.cho == 11 else { return false }
        let glides: Set<Int> = [2, 3, 6, 7, 9, 10, 12, 14, 15, 16, 17, 19]
        if glides.contains(head.jung) { return false }
        if acronymReading(word) != nil { return true }
        guard let letter = normalizeApostrophe(word).first(where: \.isLetter) else { return false }
        return "aeiouh".contains(letter)
    }

    // MARK: - 이어 부르기

    /// 원어민이 이어 부르는 두 단어 연음(`don't you` -> `돈츄`, `let it` -> `레릿`, `like a` -> `라이커`).
    static func linkedPair(_ w1: String, _ w2: String) -> String? {
        let k1 = normalizeApostrophe(w1)
        let k2 = normalizeApostrophe(w2)
        if let hit = phraseLexicon["\(k1) \(k2)"] { return hit }
        let bare1 = k1.replacingOccurrences(of: "'", with: "")
        let bare2 = k2.replacingOccurrences(of: "'", with: "")
        if bare1 != k1 || bare2 != k2, let hit = phraseLexicon["\(bare1) \(bare2)"] { return hit }
        if droppedNtStem[k1] != nil { return nil }
        if acronymReading(w1) != nil || acronymReading(w2) != nil { return nil }

        // -t/-d/-s/-z/-v + you, your (want you -> 원츄, close your -> 클로쥬어)
        let you = k2 == "u" ? "you" : k2
        if you == "you" || you == "your" || you == "yours" {
            guard !unlinkedBeforeYou.contains(k1) else { return nil }
            guard let base = phraseLexicon["\(k1) you"] ?? youLinked(englishWord(w1)) else { return nil }
            switch you {
            case "your": return base + "어"
            case "yours": return base + "어즈"
            default: return base
            }
        }

        // 자음으로 끝난 말 + a, an, of, it (like a -> 라이커, end of -> 엔더브, turn it -> 터닛).
        // up, out, on, in 같은 구동사는 구절 사전에서만 잇는다 (wake up -> 웨이컵).
        guard let tail = linkTails[k2], !unlinkedBeforeParticle.contains(k1) else { return nil }
        return particleLinked(englishWord(w1), tail: tail, particle: k2)
    }

    static let linkTails: [String: String] = ["it": "잇", "a": "어", "an": "언", "of": "어브"]

    /// 따로 읽는 편이 자연스러운 앞말.
    static let unlinkedBeforeParticle: Set<String> = [
        "it", "the", "a", "an", "to", "i", "or", "and", "so", "no", "out", "up", "this", "is",
    ]

    static let unlinkedBeforeYou: Set<String> = [
        "but", "not", "just", "at", "it", "and", "in", "on", "for", "to", "the", "a", "an", "i",
        "first", "last", "it's", "that's", "what's", "let's", "this", "us", "yes", "like", "or",
    ]

    /// 앞말 끝소리를 you 와 이어 읽는다 (원트 -> 원츄, 니드 -> 니쥬, 러브 -> 러뷰).
    static func youLinked(_ spoken: String) -> String? {
        guard let last = spoken.last, let parts = hangulParts(last) else { return nil }
        let prefix = String(spoken.dropLast())
        if parts.jong == 19 { return prefix + syllable(parts.cho, parts.jung) + "츄" }
        guard parts.jong == 0 else { return nil }
        // miss you, if you 처럼 스, 프 로 끝나는 말은 구절 사전에서만 잇는다
        switch (parts.cho, parts.jung) {
        case (16, 18), (14, 18), (14, 20): return prefix + "츄"
        case (3, 18), (12, 18), (12, 20): return prefix + "쥬"
        case (7, 18): return prefix + "뷰"
        case (9, 16): return prefix + "슈"
        default: return nil
        }
    }

    /// 앞말 끝 자음을 뒤 기능어 첫소리로 넘긴다.
    static func particleLinked(_ spoken: String, tail: String, particle: String) -> String? {
        let syllables = Array(spoken)
        guard let last = syllables.last, let end = hangulParts(last),
              let first = tail.first, let head = hangulParts(first), head.cho == 11 else { return nil }
        let rest = String(tail.dropFirst())
        let before = String(syllables.dropLast())
        let open = syllable(end.cho, end.jung)
        func link(_ lead: String, cho: Int, jung: Int? = nil) -> String {
            before + lead + syllable(cho, jung ?? head.jung, head.jong) + rest
        }
        switch end.jong {
        case 19: return link(open, cho: 5)            // -t: 굴려서 ㄹ (let it -> 레릿)
        case 1: return link(open, cho: 15)            // -k (make it -> 메이킷)
        case 17: return link(open, cho: 17)           // -p (keep it -> 키핏)
        case 8: return link(String(last), cho: 5)     // -l (feel it -> 필릿)
        case 4: return link(open, cho: 2)             // -n (turn it -> 터닛)
        case 16: return link(open, cho: 6)            // -m (come on -> 커몬)
        case 0: break
        default: return nil
        }
        let narrow = ["a", "an", "it", "of"].contains(particle)
        if end.jung == 18 {
            switch end.cho {
            case 16:
                // 모음 뒤 t 는 굴린다 (heart of -> 하러브), 자음 뒤는 그대로 (just a -> 저스터).
                if let previous = syllables.dropLast().last, let p = hangulParts(previous), p.jong == 0, p.jung != 18 {
                    return link("", cho: 5)
                }
                return link("", cho: 16)
            case 3, 15, 17, 7, 0: return link("", cho: end.cho)
            case 12: return narrow ? link("", cho: 12) : nil
            case 9, 10: return narrow ? link("", cho: 10) : nil
            case 14: return particle == "a" || particle == "an" ? link("", cho: 14) : nil
            default: return nil
            }
        }
        if end.jung == 20, end.cho == 14 || end.cho == 12 {
            return narrow ? link("", cho: end.cho) : nil
        }
        if end.jung == 16, end.cho == 9, narrow, let jung = shGlide[head.jung] {
            return link("", cho: 9, jung: jung)
        }
        return nil
    }

    static let shGlide: [Int: Int] = [0: 2, 4: 6, 8: 12, 20: 16]

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
        "doesn't": "더즌", "doesnt": "더즌",
        "ain't": "에인", "aint": "에인",
    ]

    // MARK: - 낱말

    static func englishWord(_ raw: String) -> String {
        if let spelled = acronymReading(raw) { return spelled }
        let key = normalizeApostrophe(raw)
        if let hit = lexicon[key] { return hit }
        if key.contains("-") || key.contains("&") { return joinedParts(raw) }
        // g 를 떨군 -in' (lovin' -> 러빈)
        if key.count > 4, key.hasSuffix("in'") {
            return droppingG(englishWord(String(key.dropLast()) + "g"))
        }
        let trimmed = key.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        if trimmed.isEmpty { return raw }
        if trimmed != key { return englishWord(trimmed) }
        let bare = key.replacingOccurrences(of: "'", with: "")
        if bare != key, let hit = lexicon[bare] { return hit }
        if let contracted = contraction(key) { return contracted }
        let letters = foldedLetters(bare)
        guard !letters.isEmpty else { return raw }
        if let hit = lexicon[letters] { return hit }
        if let collapsed = collapsedRepeats(letters) { return englishWord(collapsed) }
        if letters.count == 1 { return letterNames[letters.first!] ?? raw }
        if let known = knownReading(letters) { return known }
        if letters.hasPrefix("un"), letters.count >= 6, let rest = knownReading(String(letters.dropFirst(2))) {
            return "언" + rest
        }
        if let inflected = inflectedReading(letters, allowRules: true) { return inflected }
        if let romaji = romajiIfJapaneseWord(letters) { return romaji }
        let spoken = speak(letters)
        return spoken.isEmpty ? raw : spoken
    }

    /// 사전에 있거나 사전 낱말을 이어 붙인 말.
    static func knownReading(_ word: String) -> String? {
        if let hit = lexicon[word] { return hit }
        if let inflected = inflectedReading(word, allowRules: false) { return inflected }
        return compoundReading(word)
    }

    /// 악센트 글자는 기본 글자로 읽는다 (café -> cafe).
    static func foldedLetters(_ word: String) -> String {
        var out = ""
        for char in word where char.isLetter {
            if let base = accentBase[char] { out.append(base) } else { out.append(char) }
        }
        return out
    }

    static let accentBase: [Character: Character] = [
        "à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "ç": "c",
        "è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i",
        "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ù": "u", "ú": "u",
        "û": "u", "ü": "u", "ý": "y", "ÿ": "y",
    ]

    static let letterNames: [Character: String] = [
        "a": "에이", "b": "비", "c": "씨", "d": "디", "e": "이", "f": "에프", "g": "지",
        "h": "에이치", "i": "아이", "j": "제이", "k": "케이", "l": "엘", "m": "엠", "n": "엔",
        "o": "오", "p": "피", "q": "큐", "r": "알", "s": "에스", "t": "티", "u": "유",
        "v": "브이", "w": "더블유", "x": "엑스", "y": "와이", "z": "지",
    ]

    /// 대문자 약어는 글자 이름으로 읽는다 (BTS -> 비티에스). 모음 없는 대문자 낱말도 약어로 본다.
    static func acronymReading(_ raw: String) -> String? {
        guard raw.count >= 2, raw.count <= 6, raw.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return nil }
        if let hit = acronymLexicon[raw] { return hit }
        // 대문자로 외친 보통 낱말은 낱말로 읽는다 (IT, AM, SHHH)
        let lower = raw.lowercased()
        if lexicon[lower] != nil { return nil }
        if let collapsed = collapsedRepeats(lower), lexicon[collapsed] != nil { return nil }
        guard !raw.contains(where: { "AEIOUY".contains($0) }), !shoutedInterjections.contains(raw) else { return nil }
        return raw.lowercased().compactMap { letterNames[$0] }.joined()
    }

    static let acronymLexicon: [String: String] = [
        "OK": "오케이", "TV": "티비", "MTV": "엠티비", "NCT": "엔시티", "NYC": "엔와이씨", "OMG": "오엠지", "USA": "유에스에이", "UK": "유케이", "UFO": "유에프오",
        "VIP": "브이아이피", "DNA": "디엔에이", "ASAP": "에이셉", "CEO": "씨이오", "IQ": "아이큐",
        "IU": "아이유", "EDM": "이디엠", "OST": "오에스티", "ATM": "에이티엠", "EXO": "엑소",
        "AI": "에이아이", "MVP": "엠브이피", "OG": "오지", "EP": "이피", "LP": "엘피",
        "BTOB": "비투비", "IVE": "아이브", "ITZY": "있지", "TWICE": "트와이스", "ATEEZ": "에이티즈",
        "ABC": "에이비씨", "SOS": "에스오에스", "FBI": "에프비아이", "CIA": "씨아이에이", "BBC": "비비씨",
        "NBA": "엔비에이", "IOU": "아이오유", "AKA": "에이케이에이", "XYZ": "엑스와이지", "LOL": "엘오엘",
        "KO": "케이오", "USB": "유에스비", "ID": "아이디", "EQ": "이큐", "GPS": "지피에스",
    ]

    /// 모음이 없어도 낱말로 읽는 외침.
    static let shoutedInterjections: Set<String> = [
        "MM", "MMM", "HMM", "HM", "SH", "SHH", "PSST", "BRR", "GRR", "ZZZ", "TSK", "PFFT", "NTH",
    ]

    /// `hip-hop`, `R&B` 처럼 붙여 쓴 말은 조각마다 읽고 붙인다.
    static func joinedParts(_ raw: String) -> String {
        var out = ""
        var piece = ""
        func flush() {
            guard !piece.isEmpty else { return }
            out += englishWord(piece)
            piece = ""
        }
        for char in raw {
            if char == "-" {
                flush()
            } else if char == "&" {
                flush()
                out += "앤"
            } else {
                piece.append(char)
            }
        }
        flush()
        return out
    }

    /// 같은 글자를 길게 늘인 말은 줄여서 읽는다 (yeahhh -> yeah, sooo -> so).
    static func collapsedRepeats(_ word: String) -> String? {
        let chars = Array(word)
        var longRun = false
        var run = 1
        for k in 1..<max(chars.count, 1) where k < chars.count {
            run = chars[k] == chars[k - 1] ? run + 1 : 1
            if run >= 3 { longRun = true }
        }
        guard longRun else { return nil }
        func collapse(_ limit: Int) -> String {
            var out: [Character] = []
            var count = 0
            for char in chars {
                if let last = out.last, last == char {
                    count += 1
                    if count > limit { continue }
                } else {
                    count = 1
                }
                out.append(char)
            }
            return String(out)
        }
        let two = collapse(2)
        let one = collapse(1)
        if lexicon[two] != nil { return two }
        if lexicon[one] != nil { return one }
        return two
    }

    /// `-in'` 으로 줄인 말은 끝 ㅇ 받침을 ㄴ 으로 바꾼다 (러빙 -> 러빈).
    static func droppingG(_ spoken: String) -> String {
        guard let last = spoken.last, let parts = hangulParts(last), parts.jong == 21 else { return spoken }
        return String(spoken.dropLast()) + syllable(parts.cho, parts.jung, 4)
    }

    /// 축약형 (`you'll` -> `율`, `could've` -> `쿠더브`, `life's` -> `라이프스`).
    static func contraction(_ key: String) -> String? {
        guard let mark = key.lastIndex(of: "'"), mark != key.startIndex else { return nil }
        let stem = String(key[..<mark])
        let suffix = String(key[key.index(after: mark)...])
        guard !stem.isEmpty, stem.allSatisfy({ $0.isLetter || $0 == "'" }) else { return nil }
        switch suffix {
        case "s":
            return appendPlural(englishWord(stem), stem: stem)
        case "":
            // girls' 같은 복수 소유격
            return stem.hasSuffix("s") ? englishWord(stem) : nil
        case "ll":
            return withL(englishWord(stem))
        case "ve":
            return withVe(englishWord(stem))
        case "re":
            return attachVowel(englishWord(stem), "어", stemEndsWithR: false)
        case "d":
            let spoken = englishWord(stem)
            if let last = spoken.last, let parts = hangulParts(last), parts.jong == 19 {
                return attachVowel(spoken, "어드", stemEndsWithR: false)
            }
            return spoken + "드"
        default:
            if stem.hasSuffix("n"), suffix == "t" {
                return withNt(englishWord(String(stem.dropLast())))
            }
            return nil
        }
    }

    static func withL(_ spoken: String) -> String {
        guard let last = spoken.last, let parts = hangulParts(last) else { return spoken + "을" }
        let prefix = String(spoken.dropLast())
        switch parts.jong {
        case 0: return prefix + syllable(parts.cho, parts.jung, 8)
        case 19: return prefix + syllable(parts.cho, parts.jung) + "를"
        default: return spoken + "을"
        }
    }

    static func withVe(_ spoken: String) -> String {
        guard let last = spoken.last, let parts = hangulParts(last) else { return spoken + "브" }
        let prefix = String(spoken.dropLast())
        if parts.jong == 19 { return prefix + syllable(parts.cho, parts.jung) + "러브" }
        if parts.jong == 0, parts.jung == 18 { return prefix + syllable(parts.cho, 4) + "브" }
        return spoken + "브"
    }

    static func withNt(_ spoken: String) -> String {
        guard let last = spoken.last, let parts = hangulParts(last) else { return spoken + "트" }
        let prefix = String(spoken.dropLast())
        if parts.jong == 0 { return prefix + syllable(parts.cho, parts.jung, 4) + "트" }
        return spoken + "트"
    }

    // MARK: - 활용형

    /// 어간 읽기에 -s, -ed, -ing, -er, -ly 같은 꼬리를 붙인다. 규칙 어간은 생김새가 분명할 때만 쓴다.
    static func inflectedReading(_ word: String, allowRules: Bool) -> String? {
        let chars = Array(word)
        let n = chars.count
        guard n >= 4 else { return nil }
        func stem(_ cut: Int, plus extra: String = "") -> String { String(chars[0..<(n - cut)]) + extra }
        func reading(_ candidate: String) -> String? {
            if let hit = lexicon[candidate] { return hit }
            if candidate.count >= 6, let compound = compoundReading(candidate) { return compound }
            return nil
        }
        func ruleStem(_ candidate: String) -> String? {
            guard allowRules, plausibleStem(candidate) else { return nil }
            return inflectedReading(candidate, allowRules: true) ?? speak(candidate)
        }

        // -ies / -ied / -ier / -iest / -ily / -iness / -iful : y 로 끝나는 어간
        for (suffix, kind) in [("iness", "ness"), ("iest", "est"), ("ies", "s"), ("ied", "ed"), ("ier", "er"), ("ily", "ly"), ("iful", "ful")] {
            guard word.hasSuffix(suffix), n - suffix.count >= 2 else { continue }
            let base = stem(suffix.count, plus: "y")
            if kind == "s", let movie = reading(stem(1)) { return appendPlural(movie, stem: stem(1)) }
            guard let spoken = reading(base) ?? ruleStem(base) else { continue }
            // easy -> easier 이지어, happiest 해피스트: 끝 이 는 모음 그대로 둔다
            if kind == "er" { return spoken + "어" }
            if kind == "est" { return spoken + "스트" }
            return attachSuffix(spoken, kind: kind, stem: base)
        }

        if word.hasSuffix("ing"), n >= 5 {
            let base = stem(3)
            guard base.contains(where: isVowelChar) else { return nil }
            if base.hasSuffix("y") {
                // lying, dying 은 lie, die 에서 온다
                if let spoken = reading(stem(4, plus: "ie")) { return attachIng(spoken, stemEndsWithR: false) }
                if let spoken = reading(base) ?? ruleStem(base) { return attachIng(spoken, stemEndsWithR: false) }
            }
            for candidate in ingStems(base) {
                if let spoken = reading(candidate) {
                    return attachIng(spoken, stemEndsWithR: candidate.hasSuffix("r") || candidate.hasSuffix("re"))
                }
            }
            if let guess = ingStems(base).first(where: plausibleStem), let spoken = ruleStem(guess) {
                return attachIng(spoken, stemEndsWithR: guess.hasSuffix("r") || guess.hasSuffix("re"))
            }
            return nil
        }

        if word.hasSuffix("ed"), n >= 5, !word.hasSuffix("eed") || reading(stem(1)) != nil {
            let base = stem(2)
            guard base.contains(where: isVowelChar) else { return nil }
            for candidate in edStems(base) {
                if let spoken = reading(candidate) { return attachSuffix(spoken, kind: "ed", stem: candidate) }
            }
            if let guess = edStems(base).first(where: plausibleStem), let spoken = ruleStem(guess) {
                return attachSuffix(spoken, kind: "ed", stem: guess)
            }
            return nil
        }

        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is"), !word.hasSuffix("ous") {
            if let spoken = reading(stem(1)) { return appendPlural(spoken, stem: stem(1)) }
            let sibilantEs = ["ches", "shes", "sses", "xes", "zes"].contains { word.hasSuffix($0) }
            if sibilantEs, let spoken = reading(stem(2)) { return appendPlural(spoken, stem: stem(2)) }
            if word.hasSuffix("oes"), let spoken = reading(stem(2)) { return appendPlural(spoken, stem: stem(2)) }
            if allowRules, !word.hasSuffix("as"), !word.hasSuffix("os") {
                let base = sibilantEs ? stem(2) : stem(1)
                if let spoken = ruleStem(base) { return appendPlural(spoken, stem: base) }
            }
            return nil
        }

        for suffix in ["est", "er"] where word.hasSuffix(suffix) && n - suffix.count >= 3 {
            let base = stem(suffix.count)
            var candidates = [base, base + "e"]
            if let undoubled = undoubledStem(base) { candidates.insert(undoubled, at: 0) }
            for candidate in candidates {
                if let spoken = reading(candidate) {
                    if comparativeG.contains(candidate) {
                        return spoken + (suffix == "er" ? "거" : "기스트")
                    }
                    return attachSuffix(spoken, kind: suffix, stem: candidate)
                }
            }
            return nil
        }

        for suffix in ["ness", "less", "ful", "ment", "ly", "able", "y"] where word.hasSuffix(suffix) && n - suffix.count >= 3 {
            let base = stem(suffix.count)
            var candidates = [base]
            // truly <- true, judgment <- judge, simply <- simple, shiny <- shine, unforgettable <- forget
            if base.hasSuffix("u") || base.hasSuffix("dg") || suffix == "y" || suffix == "able" { candidates.append(base + "e") }
            if suffix == "able", let undoubled = undoubledStem(base) { candidates.insert(undoubled, at: 0) }
            if suffix == "ly" { candidates.append(stem(1) + "e") }
            if suffix == "y", let undoubled = undoubledStem(base) { candidates.insert(undoubled, at: 0) }
            for candidate in candidates where !(suffix == "y" && functionStems.contains(candidate)) {
                if let spoken = reading(candidate) { return attachSuffix(spoken, kind: suffix, stem: candidate) }
            }
            if suffix != "y", suffix != "able", n - suffix.count >= 4, let spoken = ruleStem(base) {
                return attachSuffix(spoken, kind: suffix, stem: base)
            }
            return nil
        }
        return nil
    }

    static let functionStems: Set<String> = ["coz", "cos", "cuz", "the", "and", "but", "can", "man", "men", "was", "has", "his", "any", "an", "as"]

    /// 비교급에서 g 소리가 살아나는 말 (longer -> 롱거).
    static let comparativeG: Set<String> = ["long", "strong", "young"]

    /// -ing 앞 어간 후보: 겹자음은 하나로, 끝 e 가 빠졌으면 되살린다.
    static func ingStems(_ base: String) -> [String] {
        var candidates: [String] = []
        if let undoubled = undoubledStem(base) { candidates.append(undoubled) }
        if needsSilentE(base) {
            candidates += [base + "e", base]
        } else {
            candidates += [base, base + "e"]
        }
        return candidates
    }

    static func edStems(_ base: String) -> [String] {
        guard base.count >= 2 else { return [] }
        var candidates: [String] = []
        if let undoubled = undoubledStem(base) { candidates.append(undoubled) }
        if needsSilentE(base) {
            candidates += [base + "e", base]
        } else {
            candidates += [base, base + "e"]
        }
        return candidates
    }

    static func undoubledStem(_ base: String) -> String? {
        let chars = Array(base)
        guard chars.count >= 3, let last = chars.last, chars[chars.count - 2] == last,
              "bdgmnprtz".contains(last) else { return nil }
        return String(chars.dropLast())
    }

    /// 어간이 끝 e 를 잃었는지 (rid -> ride, danc -> dance, lov -> love, amaz -> amaze).
    static func needsSilentE(_ base: String) -> Bool {
        let chars = Array(base)
        guard let last = chars.last else { return false }
        if "vcu".contains(last) { return true }
        if base.hasSuffix("dg") || base.hasSuffix("rg") { return true }
        if last == "s" || last == "z" {
            if chars.count >= 2, "lnrp".contains(chars[chars.count - 2]) { return true }
            if chars.count >= 3, isVowelChar(chars[chars.count - 2]), isVowelChar(chars[chars.count - 3]) { return true }
        }
        guard chars.count >= 2, isConsonantChar(last), !"wxyhj".contains(last) else { return false }
        let vowelIndex = chars.count - 2
        let vowel = chars[vowelIndex]
        guard isVowelChar(vowel) else { return false }
        if vowelIndex >= 1, isVowelChar(chars[vowelIndex - 1]) { return false }
        // 한 음절 어간 (hop -> hope, smil -> smile)
        if !chars[..<vowelIndex].contains(where: isVowelChar) { return true }
        // 여러 음절은 강세 있는 긴 끝음절만 (amaze, decide, escape). visit, open, offer 는 그대로.
        guard vowel != "e", vowel != "y" else { return false }
        let ending = String(chars[vowelIndex...])
        return !["it", "on", "op", "om", "ic", "ish"].contains(ending)
    }

    /// 규칙으로 읽어도 될 만큼 낱말다운 어간인지.
    static func plausibleStem(_ stem: String) -> Bool {
        let chars = Array(stem)
        guard chars.count >= 3, chars.contains(where: isVowelChar) else { return false }
        guard let last = chars.last else { return false }
        if last == "i" || last == "j" || last == "q" || last == "v" { return false }
        if chars.count >= 2 {
            let pair = String(chars[(chars.count - 2)...])
            let badEndings = ["cr", "br", "tr", "dr", "gr", "pr", "fr", "bl", "cl", "fl", "gl", "pl", "sl", "tl", "dl", "kl", "wr", "sw", "tw", "dw"]
            if badEndings.contains(pair) { return false }
            if chars.count >= 3, pair == "re", isConsonantChar(chars[chars.count - 3]) { return false }
        }
        return true
    }

    // MARK: - 겹친 낱말

    /// 사전 낱말 두 개를 이은 말 (heartbreak + er, sun + glasses).
    static func compoundReading(_ word: String) -> String? {
        let chars = Array(word)
        guard chars.count >= 5 else { return nil }
        var best: String?
        for cut in stride(from: chars.count - 2, through: 2, by: -1) {
            let left = String(chars[..<cut])
            let right = String(chars[cut...])
            guard left.count >= 3 || shortCompoundHeads.contains(left) else { continue }
            guard compoundTails.contains(right) || compoundTails.contains(String(right.dropLast())) && right.hasSuffix("s") else { continue }
            guard let leftReading = lexicon[left] else { continue }
            let rightReading = lexicon[right] ?? englishWord(right)
            best = leftReading + rightReading
            break
        }
        return best
    }

    static let shortCompoundHeads: Set<String> = ["up", "in", "on", "no", "my", "it", "be"]

    static let compoundTails: Set<String> = {
        let words = """
        light night time day days line side land man men woman boy girl friend heart break breaker beat broken ache
        sick star power shine fly room work word book face phone ship stick glass glasses where body thing how way more
        self selves bow ball fall fire life style ground dream mare walk shake cake bird fish dog house home play game
        song wood paper water proof back up out down over flower love kiss smile lips eye eyes gun shot storm rain snow
        sun moon sky killer maker lover dancer singer player mate wise ward king queen hood rise set town city bell box
        name mind stone cream drop ring party music rock pop wave wind field gate door wall road street park stop lock
        shop case bag coat suit hat tale world show ride trip port board boat car plane flight tear tears one
        floor step steps law away cover blood hero heroes
        """
        return Set(words.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
    }()

    // MARK: - 꼬리 붙이기

    struct HangulPieces {
        var cho: Int
        var jung: Int
        var jong: Int
    }

    static func hangulParts(_ char: Character) -> HangulPieces? {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        let offset = Int(scalar.value - 0xAC00)
        return HangulPieces(cho: offset / 588, jung: (offset / 28) % 21, jong: offset % 28)
    }

    static func attachSuffix(_ spoken: String, kind: String, stem: String) -> String {
        switch kind {
        case "s": return appendPlural(spoken, stem: stem)
        case "ed": return appendPast(spoken, stem: stem)
        case "er": return attachVowel(spoken, "어", stemEndsWithR: stem.hasSuffix("r"))
        case "est": return attachVowel(spoken, "이스트", stemEndsWithR: stem.hasSuffix("r"))
        case "y": return attachVowel(spoken, "이", stemEndsWithR: stem.hasSuffix("r"))
        case "able": return attachVowel(spoken, "어블", stemEndsWithR: stem.hasSuffix("r"))
        case "ly": return appendL(spoken, "리", vowelTakesL: true, stemEndsWithVowel: stem.hasSuffix("y"))
        case "less": return appendL(spoken, "리스", vowelTakesL: false, stemEndsWithVowel: false)
        case "ness": return spoken + "니스"
        case "ful": return spoken + "풀"
        case "ment": return spoken + "먼트"
        default: return spoken
        }
    }

    /// 복수·3인칭 -s: 무성음 뒤 스, 유성음 뒤 즈, 치찰음 뒤 이즈 (라잇 -> 라이츠, 키스 -> 키시즈, 링 -> 링즈).
    static func appendPlural(_ spoken: String, stem: String) -> String {
        guard let last = spoken.last, let parts = hangulParts(last) else { return spoken + "스" }
        let prefix = String(spoken.dropLast())
        switch parts.jong {
        case 19: return prefix + syllable(parts.cho, parts.jung) + (stem.hasSuffix("d") ? "즈" : "츠")
        case 1, 17: return spoken + "스"
        case 0: break
        default: return spoken + "즈"
        }
        switch (parts.cho, parts.jung) {
        case (16, 18): return prefix + "츠"
        case (3, 18): return prefix + "즈"
        case (9, 18), (10, 18): return prefix + syllable(parts.cho, 20) + "즈"
        case (12, 18): return prefix + "지즈"
        case (14, 18): return spoken
        case (15, 18), (17, 18): return spoken + "스"
        case (14, 20), (12, 20), (9, 16), (9, 20): return spoken + "즈"
        default: return spoken + "즈"
        }
    }

    /// 과거형 -ed: t/d 뒤 이드, 무성음(스, 크, 프, 치, 쉬, ㄱ·ㅂ 받침) 뒤 트, 나머지 드.
    static func appendPast(_ spoken: String, stem: String) -> String {
        let letters = Array(stem)
        guard let last = letters.last else { return spoken + "드" }
        let core = last == "e" && letters.count >= 2 ? letters[letters.count - 2] : last
        if core == "t" || core == "d" {
            return attachVowel(spoken, "이드", stemEndsWithR: false)
        }
        guard let end = spoken.last, let parts = hangulParts(end) else { return spoken + "드" }
        let voiceless = parts.jong == 1 || parts.jong == 17
            || (parts.jong == 0 && parts.jung == 18 && [9, 10, 15, 17].contains(parts.cho))
            || (parts.jong == 0 && ((parts.cho == 14 && parts.jung == 20) || (parts.cho == 9 && parts.jung == 16)))
        return spoken + (voiceless ? "트" : "드")
    }

    /// -ly / -less: 받침 없는 으 소리는 ㄹ 받침으로 받고, 모음 끝은 ㄹ 을 덧댄다 (러브 -> 러블리, 해피 -> 해필리).
    static func appendL(_ spoken: String, _ tail: String, vowelTakesL: Bool, stemEndsWithVowel: Bool) -> String {
        guard let last = spoken.last, let parts = hangulParts(last) else { return spoken + tail }
        let prefix = String(spoken.dropLast())
        let open = syllable(parts.cho, parts.jung)
        switch parts.jong {
        case 19: return prefix + open + "틀" + tail
        case 1: return prefix + open + "클" + tail
        case 17: return prefix + open + "플" + tail
        case 0: break
        default: return spoken + tail
        }
        if parts.jung == 18 {
            // 쓰(th)는 그대로 둔다 (breathless -> 브레쓰리스)
            return parts.cho == 10 ? spoken + tail : prefix + syllable(parts.cho, 18, 8) + tail
        }
        if !stemEndsWithVowel, parts.cho == 14 || parts.cho == 12 || parts.jung == 16 { return spoken + tail }
        return vowelTakesL ? prefix + syllable(parts.cho, parts.jung, 8) + tail : spoken + tail
    }

    static func attachIng(_ spoken: String, stemEndsWithR: Bool) -> String {
        attachVowel(spoken, "잉", stemEndsWithR: stemEndsWithR)
    }

    /// 모음으로 시작하는 꼬리(잉, 어, 이스트, 이드...)에 앞 자음을 넘겨 붙인다 (겟 -> 게링, 드림 -> 드리머, 댄스 -> 댄싱).
    static func attachVowel(_ spoken: String, _ tail: String, stemEndsWithR: Bool) -> String {
        guard let first = tail.first, let head = hangulParts(first),
              let last = spoken.last, let end = hangulParts(last) else { return spoken + tail }
        let rest = String(tail.dropFirst())
        let syllables = Array(spoken)
        let before = String(syllables.dropLast())
        func moved(_ lead: String, cho: Int, jung: Int? = nil) -> String {
            before + lead + syllable(cho, jung ?? head.jung, head.jong) + rest
        }
        let open = syllable(end.cho, end.jung)
        switch end.jong {
        case 19: return moved(open, cho: 5)
        case 1: return moved(open, cho: 15)
        case 17: return moved(open, cho: 17)
        case 8: return moved(String(last), cho: 5)
        case 4: return moved(open, cho: 2)
        case 16: return moved(open, cho: 6)
        case 0: break
        default: return spoken + tail
        }
        if end.jung == 18 {
            if end.cho == 16, let previous = syllables.dropLast().last, let p = hangulParts(previous), p.jong == 0, p.jung != 18 {
                return moved("", cho: 5)
            }
            if end.cho == 9, head.jung == 20, tail == "잉" { return moved("", cho: 9) }
            return moved("", cho: end.cho)
        }
        if end.cho == 14 || end.cho == 12, end.jung == 20 { return moved("", cho: end.cho) }
        if end.cho == 9, end.jung == 16 {
            return moved("", cho: 9, jung: shGlide[head.jung] ?? head.jung)
        }
        if stemEndsWithR, end.cho != 11 || end.jung == 4 {
            return spoken + syllable(5, head.jung, head.jong) + rest
        }
        // 이중모음 끝 이/우 는 꼬리에 녹인다 (플라이 -> 플라잉, 팔로우 -> 팔로잉, 로우 -> 로워)
        if end.cho == 11, syllables.count >= 2, let previous = hangulParts(syllables[syllables.count - 2]), previous.jong == 0 {
            if end.jung == 20, [0, 5, 8, 2, 9, 15].contains(previous.jung), head.jung == 20 {
                return before + tail
            }
            if end.jung == 13, previous.jung == 8 {
                if head.jung == 20 { return before + tail }
                if head.jung == 4 { return before + syllable(11, 14, head.jong) + rest }
            }
        }
        if end.jung == 20, head.jung == 20, tail.count > 1 {
            return spoken + rest
        }
        return spoken + tail
    }

    // MARK: - 일본어 로마자

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

    // MARK: - 사전

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

    // MARK: - 글자에서 소리로

    static func speak(_ word: String) -> String {
        var pieces = pack(atoms(of: word))
        // 아우 + 어 는 아워로 붙인다 (tower -> 타워, our -> 아워)
        for k in pieces.indices.dropLast()
        where pieces[k].vowel == .aw && pieces[k].coda.isEmpty && pieces[k + 1].onset.isEmpty && pieces[k + 1].vowel == .eo {
            pieces[k].vowel = .a
            pieces[k + 1].onset = [.w]
        }
        return pieces.map(\.rendered).joined()
    }

    enum Consonant { case b, ch, d, f, g, h, j, k, l, m, n, ng, p, r, s, ss, sh, t, v, w, y, z }

    /// 받침 규칙을 위해 길이와 r 빛깔을 나눠 둔다 (ii: see, oo: go, ow: 끝 -ow, uu: moon, ar/or/er: car, for, her).
    enum Vowel { case a, ae, eo, e, i, ii, o, oo, ow, u, uu, eu, yu, ay, ey, oy, aw, ar, or, er }

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

    static func isVowelChar(_ char: Character) -> Bool {
        "aeiouy".contains(char)
    }

    static func isConsonantChar(_ char: Character) -> Bool {
        char.isLetter && !isVowelChar(char)
    }

    static func isLong(_ vowel: Vowel) -> Bool {
        switch vowel {
        case .ii, .oo, .ow, .uu, .yu, .ay, .ey, .oy, .aw: return true
        default: return false
        }
    }

    static func isRhotic(_ vowel: Vowel) -> Bool {
        vowel == .ar || vowel == .or || vowel == .er
    }

    static func atoms(of word: String) -> [Atom] {
        var spelling = EnglishSpelling(word)
        return spelling.atoms()
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
                if !pieces.isEmpty, pieces[pieces.count - 1].coda.isEmpty, let head = onset.first {
                    let previous = pieces[pieces.count - 1].vowel
                    if onset == [.l], !isRhotic(previous) {
                        // 모음 사이의 l 은 앞 음절 받침 ㄹ 과 뒤 음절 초성 ㄹ 로 이어 읽는다 (feeling -> 필링).
                        pieces[pieces.count - 1].coda = [.l]
                    } else if onset.count >= 2 {
                        let next = onset[1]
                        if batchim(head) != nil {
                            pieces[pieces.count - 1].coda = [head]
                            onset.removeFirst()
                        } else if stopCoda(head, after: previous) != nil, !blocksStopCoda(head, before: next) {
                            // 짧은 모음 뒤 자음 앞 파열음은 받침으로 적는다 (doctor -> 닥터, picture -> 픽처).
                            pieces[pieces.count - 1].coda = [head]
                            onset.removeFirst()
                        }
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

    /// 파열음 받침이 될 수 있는지: 짧은 모음 뒤만 받침으로 적는다 (book -> 북, make -> 메이크, keep -> 킵, note -> 노트).
    static func stopCoda(_ consonant: Consonant, after vowel: Vowel) -> Int? {
        if isRhotic(vowel) { return nil }
        switch consonant {
        case .k:
            return isLong(vowel) ? nil : 1
        case .p, .b:
            return isLong(vowel) && vowel != .ii ? nil : 17
        case .t:
            switch vowel {
            case .oo, .ow, .uu, .yu: return nil
            default: return 19
            }
        default:
            return nil
        }
    }

    /// 짧은 모음 뒤 파열음이 받침이 되지 못하는 뒷소리 (apple -> 애플, Batman -> 배트맨, napkin -> 냅킨, hypnotic -> 힙노틱).
    static func blocksStopCoda(_ stop: Consonant, before next: Consonant) -> Bool {
        if [.l, .r, .w, .y].contains(next) { return true }
        return stop == .t && (next == .m || next == .n)
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
        var head = ""
        var choIndex = 11
        if rounded, let last = onset.last, ![.k, .g, .h].contains(last) {
            // w 는 k, g, h 뒤에서만 한 음절로 묶는다 (queen -> 퀸, sweet -> 스윗, twist -> 트위스트).
            head = onset.map { clusterSyllable($0, jong: 0) }.joined()
        } else {
            if let last = onset.last {
                choIndex = cho(last)
                if last == .sh { palatal = true }
            }
            let prefix = Array(onset.dropLast())
            let liquidCluster = onset.count >= 2 && onset.last == .l
            for (idx, consonant) in prefix.enumerated() {
                head += clusterSyllable(consonant, jong: liquidCluster && idx == prefix.count - 1 ? 8 : 0)
            }
        }
        let coda = piece.coda.filter { $0 != .r }
        return head + renderVowel(cho: choIndex, vowel: piece.vowel, coda: coda, palatal: palatal, rounded: rounded)
    }

    static func clusterSyllable(_ consonant: Consonant, jong: Int) -> String {
        switch consonant {
        case .sh: return syllable(9, 13, jong)
        case .ch: return syllable(14, 20, jong)
        case .j: return syllable(12, 20, jong)
        default: return syllable(cho(consonant), 18, jong)
        }
    }

    static func renderVowel(cho: Int, vowel: Vowel, coda: [Consonant], palatal: Bool, rounded: Bool) -> String {
        switch vowel {
        case .ay:
            return diphthong(cho: cho, first: rounded ? 9 : (palatal ? 2 : 0), second: 20, vowel: vowel, coda: coda)
        case .ey:
            let first = rounded || (palatal && cho == 9) ? 15 : (palatal ? 7 : 5)
            return diphthong(cho: cho, first: first, second: 20, vowel: vowel, coda: coda)
        case .oy:
            return diphthong(cho: cho, first: palatal ? 12 : 8, second: 20, vowel: vowel, coda: coda)
        case .aw:
            return diphthong(cho: cho, first: rounded ? 9 : (palatal ? 2 : 0), second: 13, vowel: vowel, coda: coda)
        case .ow:
            // 끝 -ow 는 오우로 적는다 (yellow -> 옐로우, known -> 노운)
            let jung = glide(8, cho: cho, palatal: palatal, rounded: rounded)
            return syllable(cho, jung) + (coda.isEmpty ? "우" : codaSyllable(cho: 11, jung: 13, vowel: .uu, coda: coda))
        default:
            var jung = glide(jung(vowel), cho: cho, palatal: palatal, rounded: rounded)
            if vowel == .yu, [12, 14].contains(cho) { jung = 13 }
            if vowel == .e, palatal, cho == 9 { jung = 15 }
            return codaSyllable(cho: cho, jung: jung, vowel: vowel, coda: coda)
        }
    }

    static func diphthong(cho: Int, first: Int, second: Int, vowel: Vowel, coda: [Consonant]) -> String {
        syllable(cho, first) + codaSyllable(cho: 11, jung: second, vowel: vowel, coda: coda)
    }

    static func codaSyllable(cho: Int, jung: Int, vowel: Vowel, coda: [Consonant]) -> String {
        var rest = coda
        var jong = 0
        if rest == [.t, .s] {
            return syllable(cho, jung, 0) + syllable(14, 18)
        }
        if let head = rest.first {
            if let nasalOrLiquid = batchim(head) {
                jong = nasalOrLiquid
                rest.removeFirst()
            } else if let stop = stopCoda(head, after: vowel),
                      rest.count == 1 || !(head == .t && rest[1] == .s) && !blocksStopCoda(head, before: rest[1]) {
                jong = stop
                rest.removeFirst()
            }
        }
        var text = syllable(cho, jung, jong)
        var index = 0
        while index < rest.count {
            let consonant = rest[index]
            let following = index + 1 < rest.count ? rest[index + 1] : nil
            if consonant == .t, following == .s {
                text += syllable(14, 18)
                index += 2
                continue
            }
            if consonant == .d, following == .z {
                text += syllable(12, 18)
                index += 2
                continue
            }
            switch consonant {
            case .sh: text += syllable(9, 16)
            case .ch: text += syllable(14, 20)
            case .j: text += syllable(12, 20)
            case .w, .y, .r: break
            case .l, .m, .n:
                // 으 소리 뒤 l, m, n 은 받침으로 (dazzle -> 대즐, realism -> 리얼리즘), ㄹ 뒤는 름 (film -> 필름)
                if let lastChar = text.last, let p = hangulParts(lastChar), let jong = batchim(consonant) {
                    if p.jong == 0, p.jung == 18 {
                        text = String(text.dropLast()) + syllable(p.cho, 18, jong)
                    } else if p.jong == 8, consonant != .l {
                        text += syllable(5, 18, jong)
                    } else {
                        text += syllable(self.cho(consonant), 18)
                    }
                } else {
                    text += syllable(self.cho(consonant), 18)
                }
            default: text += syllable(self.cho(consonant), 18)
            }
            index += 1
        }
        return text
    }

    static func jung(_ vowel: Vowel) -> Int {
        switch vowel {
        case .a, .ar: return 0
        case .ae: return 1
        case .eo, .er: return 4
        case .e: return 5
        case .o, .oo, .ow, .or: return 8
        case .u, .uu: return 13
        case .yu: return 17
        case .eu: return 18
        case .i, .ii: return 20
        case .ay, .ey, .oy, .aw: return 4
        }
    }

    static func glide(_ jung: Int, cho: Int, palatal: Bool, rounded: Bool) -> Int {
        if rounded {
            switch jung {
            case 0: return 9
            case 1: return 10
            case 4, 8: return 14
            case 5: return 15
            case 20: return 16
            case 18: return 13
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

// MARK: - 철자 읽기

extension HangulReading {
    /// 철자를 소리 단위(자음·모음)로 나눈다. 받침 규칙에 쓰도록 모음 길이와 r 빛깔을 함께 적는다.
    struct EnglishSpelling {
        let raw: [Character]
        let n: Int
        private var silent = Set<Int>()
        private var long = Set<Int>()
        private var out: [Atom] = []
        private var i = 0

        init(_ word: String) {
            raw = Array(word)
            n = raw.count
        }

        // MARK: 글자 살피기

        private func ch(_ k: Int) -> Character? { k >= 0 && k < n ? raw[k] : nil }

        private func isV(_ k: Int) -> Bool {
            guard let char = ch(k) else { return false }
            if char == "y", let next = ch(k + 1), "aeiou".contains(next), !(next == "e" && k + 2 == n && k > 0) {
                return false
            }
            return HangulReading.isVowelChar(char)
        }

        private func isC(_ k: Int) -> Bool { ch(k) != nil && !isV(k) && ch(k)!.isLetter }

        private func has(_ text: String, at k: Int) -> Bool {
            guard k >= 0 else { return false }
            var index = k
            for char in text {
                guard index < n, raw[index] == char else { return false }
                index += 1
            }
            return true
        }

        private func rest(from k: Int) -> String { k < n ? String(raw[k...]) : "" }

        /// k 앞에 모음 글자가 있는지 (여러 음절 낱말인지).
        private func vowelBefore(_ k: Int) -> Bool {
            var index = 0
            while index < min(k, n) {
                let silentU = raw[index] == "u" && index > 0 && (raw[index - 1] == "q" || raw[index - 1] == "g") && isV(index + 1)
                if isV(index), !silentU { return true }
                index += 1
            }
            return false
        }

        /// 겹모음이 아닌 홑모음 글자인지.
        private func isSingleVowel(_ k: Int) -> Bool {
            guard isV(k) else { return false }
            if raw[k] == "y", isV(k - 1) { return false }
            if isV(k - 1), !(raw[k - 1] == "u" && (ch(k - 2) == "q" || ch(k - 2) == "g")) { return false }
            if isV(k + 1) { return false }
            return true
        }

        private mutating func emit(_ atoms: [Atom], _ consume: Int) {
            out += atoms
            i += consume
        }

        // MARK: 읽기

        mutating func atoms() -> [Atom] {
            markLongVowels()
            while i < n {
                if silent.contains(i) {
                    i += 1
                    continue
                }
                if scanEnding() { continue }
                if isV(i) {
                    if scanRhotic() { continue }
                    if scanVowelGroup() { continue }
                    scanVowel()
                    continue
                }
                scanConsonant()
            }
            return out
        }

        /// 끝 e 앞 모음은 길게 (make, hope), 끝 e 는 소리 내지 않는다.
        private mutating func markLongVowels() {
            for k in 0..<n where isSingleVowel(k) {
                guard k + 2 < n, isC(k + 1), !"xwyr".contains(raw[k + 1]), raw[k + 2] == "e" else { continue }
                let after = rest(from: k + 3)
                let c = raw[k + 1]
                let multi = vowelBefore(k)
                // 여러 음절의 -age 는 짧다 (message, savage)
                if multi, c == "g", raw[k] == "a", after.isEmpty || after == "s" || after == "d" { continue }
                // -tive, -sive 는 짧다 (active, massive)
                if raw[k] == "i", c == "v", multi, let before = ch(k - 1), "tscp".contains(before) { continue }
                // 여러 음절의 -ice 는 짧다 (office, notice)
                if raw[k] == "i", c == "c", multi, after.isEmpty || after == "s" { continue }
                let quietE: Bool
                switch after {
                case "", "ly", "ness", "less", "ful", "fully", "ment", "ments":
                    quietE = true
                case "s":
                    quietE = !"sczg".contains(c)
                case "d":
                    quietE = c != "t" && c != "d"
                case "r", "rs", "st", "y":
                    quietE = false
                case "n", "ns":
                    guard raw[k] == "a" || raw[k] == "o" else { continue }
                    quietE = false
                default:
                    continue
                }
                long.insert(k)
                if quietE { silent.insert(k + 2) }
            }
            for k in 0..<n where isSingleVowel(k) {
                let after = rest(from: k + 1)
                // favor, flavor, major, savior, survivor
                if k + 1 < n, isC(k + 1), !"xwyr".contains(raw[k + 1]), ["or", "ors", "ior", "iors"].contains(rest(from: k + 2)) {
                    long.insert(k)
                }
                // change, strange, danger, taste, waste
                if raw[k] == "a", ["nge", "nges", "nged", "nger", "ngers", "ste", "stes", "sted", "steful"].contains(after) {
                    long.insert(k)
                    if ["nge", "nges", "nged", "ste", "stes"].contains(after) { silent.insert(k + 3) }
                }
                // table, noble, bible, title, cycle
                if k + 3 < n, "bdfgkptc".contains(raw[k + 1]), ["le", "les", "led"].contains(rest(from: k + 2)), !vowelBefore(k) {
                    long.insert(k)
                }
                // lady, tiny, holy: 두 음절 C+y
                if k + 2 == n - 1, isC(k + 1), !"rvwxy".contains(raw[k + 1]), raw[k + 2] == "y", !vowelBefore(k), raw[k] != "y" {
                    long.insert(k)
                }
            }
        }

        // MARK: 낱말 끝·접미사

        private mutating func scanEnding() -> Bool {
            let tail = rest(from: i)
            let multi = vowelBefore(i)
            let previousVowel = isV(i - 1)
            if has("ssion", at: i) {
                emit([.c(.sh), .v(.eo), .c(.n)], 5)
                return true
            }
            if has("shion", at: i) {
                emit([.c(.sh), .v(.eo), .c(.n)], 5)
                return true
            }
            if has("tion", at: i) || has("cion", at: i) {
                emit([raw[i] == "t" && ch(i - 1) == "s" ? .c(.ch) : .c(.sh), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("xion", at: i) {
                emit([.c(.k), .c(.sh), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("sion", at: i), i > 0 {
                emit([previousVowel || ch(i - 1) == "r" ? .c(.j) : .c(.sh), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("tian", at: i) || has("cian", at: i), multi {
                emit([ch(i - 1) == "s" ? .c(.ch) : .c(.sh), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("cean", at: i), multi {
                emit([.c(.sh), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("tial", at: i) || has("cial", at: i), multi {
                emit([.c(.sh), .v(.eo), .c(.l)], 4)
                return true
            }
            if has("tious", at: i) || has("cious", at: i), multi {
                emit([.c(.sh), .v(.eo), .c(.s)], 5)
                return true
            }
            if has("tient", at: i) || has("cient", at: i), multi {
                emit([.c(.sh), .v(.eo), .c(.n), .c(.t)], 5)
                return true
            }
            if has("tience", at: i) || has("cience", at: i), multi {
                emit([.c(.sh), .v(.eo), .c(.n), .c(.s)], 6)
                return true
            }
            if has("geous", at: i) || has("gious", at: i) {
                emit([.c(.j), .v(.eo), .c(.s)], 5)
                return true
            }
            if has("gion", at: i) || has("geon", at: i), multi {
                emit([.c(.j), .v(.eo), .c(.n)], 4)
                return true
            }
            if has("ture", at: i), multi {
                emit([.c(.ch), .v(.eo)], 4)
                return true
            }
            if has("tural", at: i), multi {
                emit([.c(.ch), .v(.eo), .c(.r), .v(.eo), .c(.l)], 5)
                return true
            }
            if has("tury", at: i), multi {
                emit([.c(.ch), .v(.u), .c(.r), .v(.i)], 4)
                return true
            }
            if has("ssure", at: i) {
                emit([.c(.sh), .v(.eo)], 5)
                return true
            }
            if has("sure", at: i), multi {
                emit([ch(i - 1) == "n" ? .c(.sh) : .c(.j), .v(.eo)], 4)
                return true
            }
            if has("sual", at: i) || has("zual", at: i), multi {
                emit([previousVowel ? .c(.j) : .c(.sh), .v(.u), .v(.eo), .c(.l)], 4)
                return true
            }
            if has("tual", at: i), multi {
                emit([.c(.ch), .v(.u), .v(.eo), .c(.l)], 4)
                return true
            }
            if has("dual", at: i), multi {
                emit([.c(.j), .v(.u), .v(.eo), .c(.l)], 4)
                return true
            }
            if has("ique", at: i), i + 4 == n || (i + 5 == n && raw[n - 1] == "s") {
                emit([.v(.ii), .c(.k)], n - i)
                return true
            }
            if (tail == "gue" || tail == "gues") && multi {
                emit([.c(.g)], n - i)
                return true
            }
            if (tail == "que" || tail == "ques") && multi {
                emit([.c(.k)], n - i)
                return true
            }
            // castle, listen, often: t 를 읽지 않는다
            if has("stle", at: i), i + 4 == n || (i + 5 == n && "sd".contains(raw[n - 1])) {
                emit([.c(.s), .v(.eu), .c(.l)], 4)
                return true
            }
            if has("sten", at: i) || has("ften", at: i), multi, i + 4 == n || (i + 5 == n && raw[n - 1] == "s") {
                emit([raw[i] == "s" ? .c(.s) : .c(.f), .v(.eu), .c(.n)], 4)
                return true
            }
            // climb, bomb, autumn
            if has("mb", at: i) || has("mn", at: i), previousVowel,
               i + 2 == n || ["s", "ed", "ing"].contains(rest(from: i + 2)) {
                emit([.c(.m)], 2)
                return true
            }
            if has("ious", at: i) || has("eous", at: i), multi {
                emit([.v(.i), .v(.eo), .c(.s)], 4)
                return true
            }
            if has("ous", at: i), multi, ["", "ly", "ness"].contains(rest(from: i + 3)) {
                emit([.v(.eo), .c(.s)], 3)
                return true
            }
            // -le: little, simple, people
            if raw[i] == "l", ch(i + 1) == "e", isC(i - 1), ch(i - 1) != "l",
               i + 2 == n || ["s", "d", "r", "rs"].contains(rest(from: i + 2)) {
                switch rest(from: i + 2) {
                case "s": emit([.v(.eu), .c(.l), .c(.z)], n - i)
                case "d": emit([.v(.eu), .c(.l), .c(.d)], n - i)
                case "r", "rs": emit([.v(.eu), .c(.l), .c(.r), .v(.eo)] + (tail.hasSuffix("s") ? [.c(.z)] : []), n - i)
                default: emit([.v(.eu), .c(.l)], n - i)
                }
                return true
            }
            return false
        }

        // MARK: 모음 + r

        private func endish(_ k: Int) -> Bool {
            let after = rest(from: k)
            return after.isEmpty || ["s", "d", "ly", "ness", "less", "ful", "ment"].contains(after)
        }

        private mutating func scanRhotic() -> Bool {
            let v = raw[i]
            let multi = vowelBefore(i)
            if has("ear", at: i) {
                let after = rest(from: i + 3)
                if after.isEmpty || ["s", "ed", "ing", "ly", "ful", "fully"].contains(after) {
                    emit([.v(.ii), .v(.eo)], 3)
                } else if isV(i + 3) {
                    emit([.v(.ii), .v(.eo), .c(.r)], 3)
                } else if ch(i + 3) == "t" {
                    emit([.v(.ar)], 3)
                } else {
                    emit([.v(.er)], 3)
                }
                return true
            }
            if has("eer", at: i) || (has("ier", at: i) && (endish(i + 3) || isC(i + 3))) {
                emit([.v(.ii), .v(.eo)] + (isV(i + 3) ? [.c(.r)] : []), 3)
                return true
            }
            if has("air", at: i) || has("eir", at: i) {
                emit([.v(.e), .v(.eo)] + (isV(i + 3) && !(has("aire", at: i) && i + 4 == n) ? [.c(.r)] : []), has("aire", at: i) && i + 4 == n ? 4 : 3)
                return true
            }
            if has("oor", at: i) || (has("oar", at: i) && (endish(i + 3) || isV(i + 3))) {
                emit([.v(.o), .v(.eo)] + (isV(i + 3) ? [.c(.r)] : []), 3)
                return true
            }
            if has("oar", at: i) {
                emit([.v(.or)], 3)
                return true
            }
            if (has("iar", at: i) || has("ior", at: i)), endish(i + 3) {
                emit([vowelBefore(i) ? .v(.i) : .v(.ay), .v(.eo)], 3)
                return true
            }
            if has("our", at: i) {
                let after = rest(from: i + 3)
                if after.isEmpty || ["s", "ed", "ly"].contains(after) {
                    emit(multi ? [.v(.eo)] : [.v(.aw), .v(.eo)], 3)
                } else if has("ourn", at: i) {
                    emit([.v(.er)], 3)
                } else if isV(i + 3) {
                    emit([.v(.eo), .c(.r)], 3)
                } else {
                    emit([.v(.or)], 3)
                }
                return true
            }
            guard ch(i + 1) == "r", isSingleVowel(i) else { return false }
            let afterR = i + 2
            // 모음 + r + e 끝 (care, here, fire, more, pure)
            if ch(afterR) == "e", endish(afterR + 1) {
                switch v {
                case "a": emit([.v(.e), .v(.eo)], 3)
                case "e": emit([.v(.ii), .v(.eo)], 3)
                case "i", "y": emit([.v(.ay), .v(.eo)], 3)
                case "o": emit([.v(.o), .v(.eo)], 3)
                default:
                    if let previous = ch(i - 1), "rljh".contains(previous) || (previous == "s" && ch(i - 2) != "s") {
                        emit([.v(.u), .v(.eo)], 3)
                    } else {
                        emit([.v(.yu), .v(.eo)], 3)
                    }
                }
                return true
            }
            // 겹 r: 짧은 모음 + r (carry, mirror, hurry)
            if ch(afterR) == "r" {
                switch v {
                case "a": emit([i == 0 && unstressedPrefixA() ? .v(.eo) : .v(.ae)], 1)
                case "e": emit([.v(.e)], 1)
                case "i", "y": emit([.v(.i)], 1)
                case "o": emit([.v(.o)], 1)
                default: emit([.v(.eo)], 1)
                }
                return true
            }
            // r + 모음이면 r 은 다음 음절 첫소리
            if isV(afterR) { return false }
            let previous = ch(i - 1)
            let wBefore = previous == "w" || (previous == "u" && ch(i - 2) == "q")
            let endsHere = afterR == n || rest(from: afterR) == "s"
            switch v {
            case "a":
                if wBefore {
                    emit([.v(.or)], 2)
                } else if multi && endsHere {
                    emit([.v(.eo)], 2)
                } else if multi, ["d", "ds"].contains(rest(from: afterR)), let p = previous, HangulReading.isConsonantChar(p) {
                    emit([.v(.eo)], 2)
                } else {
                    emit([.v(.ar)], 2)
                }
            case "o":
                if previous == "w", !endsHere, ch(afterR) != "n", !has("wore", at: i - 1) {
                    emit([.v(.er)], 2)
                } else if multi && endsHere {
                    emit([.v(.eo)], 2)
                } else if multi, has("ford", at: i - 1), afterR + 1 == n {
                    emit([.v(.eo)], 2)
                } else {
                    emit([.v(.or)], 2)
                }
            case "e":
                emit([multi && endsHere ? .v(.eo) : .v(.er)], 2)
            default:
                emit([.v(.er)], 2)
            }
            return true
        }

        // MARK: 겹모음

        private mutating func scanVowelGroup() -> Bool {
            let multi = vowelBefore(i)
            if has("ought", at: i) || has("aught", at: i) {
                emit([.v(.o), .c(.t)], 5)
                return true
            }
            if has("ough", at: i) {
                emit(i + 4 == n ? [.v(.eo), .c(.f)] : [.v(.aw)], 4)
                return true
            }
            if has("augh", at: i) {
                emit([.v(.ae), .c(.f)], 4)
                return true
            }
            if has("eigh", at: i) {
                if has("eight", at: i) { emit([.v(.ey), .c(.t)], 5) } else { emit([.v(.ey)], 4) }
                return true
            }
            if has("igh", at: i) {
                if has("ight", at: i) { emit([.v(.ay), .c(.t)], 4) } else { emit([.v(.ay)], 3) }
                return true
            }
            if has("eye", at: i) || (has("aye", at: i) && (i + 3 == n || rest(from: i + 3) == "s")) {
                emit([.v(.ay)], 3)
                return true
            }
            if has("eau", at: i) {
                emit([.v(.oo)], 3)
                return true
            }
            guard i + 1 < n else { return false }
            let pair = String(raw[i...(i + 1)])
            let after = rest(from: i + 2)
            switch pair {
            case "ee":
                emit([.v(.ii)], 2)
            case "ea":
                if eaIsShort(at: i) {
                    emit([.v(.e)], 2)
                } else if after.isEmpty, multi {
                    emit([.v(.ii), .v(.a)], 2)
                } else {
                    emit([.v(.ii)], 2)
                }
            case "ei":
                emit([ch(i - 1) == "c" ? .v(.ii) : .v(.ey)], 2)
            case "ey":
                if after.isEmpty || after == "s" {
                    emit([multi ? .v(.i) : .v(.ey)] + (after == "s" ? [.c(.z)] : []), n - i)
                } else {
                    emit([.v(.ey)], 2)
                }
            case "ie":
                if after.isEmpty {
                    emit([multi ? .v(.i) : .v(.ay)], 2)
                } else if after == "s" || after == "d" {
                    emit([iedIsLong(at: i) ? .v(.ay) : .v(.i), after == "s" ? .c(.z) : .c(.d)], n - i)
                } else if !multi, ["t", "ts", "nt", "nts", "nce", "nces", "ty"].contains(after) {
                    emit([.v(.ay), .v(.eo)], 2)
                } else if multi, isV(i + 2) || ["t", "nt", "nce", "nts", "nces", "l", "ls"].contains(after) {
                    emit([.v(.i), .v(.eo)], 2)
                } else {
                    emit([.v(.ii)], 2)
                }
            case "oa":
                emit(after.isEmpty ? [.v(.oo), .v(.a)] : [.v(.oo)], 2)
            case "oe":
                emit(after.isEmpty || after == "s" ? [.v(.oo)] : [.v(.oo), .v(.e)], 2)
            case "oi", "oy":
                emit([.v(.oy)], 2)
            case "oo":
                let short = has("ook", at: i) || has("ood", at: i) || (has("oot", at: i) && i + 3 == n && ch(i - 1) == "f")
                emit([short ? .v(.u) : .v(.uu)], 2)
            case "ou":
                if has("ould", at: i), ["", "n't", "nt", "'ve"].contains(rest(from: i + 4)) {
                    emit([.v(.u), .c(.d)], 4)
                } else if has("oulder", at: i) {
                    emit([.v(.oo), .c(.l)], 3)
                } else if has("ouble", at: i) || has("ouple", at: i) || has("ountr", at: i) || has("oung", at: i) || has("ousin", at: i) {
                    emit([.v(.eo)], 2)
                } else if (has("oup", at: i) && i + 3 == n) || has("oute", at: i) || has("outine", at: i) {
                    emit([.v(.uu)], 2)
                } else {
                    emit([.v(.aw)], 2)
                }
            case "ow":
                if let next = ch(i + 2), "aiou".contains(next) { return false }
                emit([owSound(at: i)], 2)
            case "au", "aw":
                if pair == "aw", let next = ch(i + 2), "aeou".contains(next) { return false }
                emit([.v(.o)], 2)
            case "ai", "ay":
                emit([.v(.ey)], 2)
            case "ue":
                let vowel = uSound(at: i)
                if after.isEmpty {
                    emit([vowel], 2)
                } else if after == "s" || after == "d" {
                    emit([vowel, after == "s" ? .c(.z) : .c(.d)], n - i)
                } else {
                    emit([vowel, .v(.eo)], 2)
                }
            case "ui":
                if ch(i - 1) == "q" || ch(i - 1) == "g" { return false }
                if has("uild", at: i) || has("uilt", at: i) {
                    emit([.v(.i)], 2)
                } else if (has("uit", at: i) && i + 3 == n) || has("uice", at: i) || has("uise", at: i) {
                    emit([.v(.uu)], 2)
                } else {
                    emit([uSound(at: i), .v(.i)], 2)
                }
            case "uy":
                emit([.v(.ay)], 2)
            case "eu", "ew":
                if pair == "ew", i == 1, raw[0] == "r", isV(i + 2) { return false }
                emit([uSound(at: i)], 2)
            default:
                return false
            }
            return true
        }

        /// head, ready, heavy, death, weather, pleasure 처럼 ea 를 짧게 읽는 자리.
        private func eaIsShort(at k: Int) -> Bool {
            let after = rest(from: k + 2)
            let shortStarts = ["ther", "lth", "sure", "sant", "lous", "pon", "lm", "nt", "vy", "ven", "dy", "dily"]
            if shortStarts.contains(where: { after.hasPrefix($0) }) { return true }
            if after == "th" || after == "ths" { return true }
            if after.hasPrefix("d") {
                let afterD = String(after.dropFirst())
                return ["", "s", "y", "ing", "er", "ed", "ly", "ily", "iness"].contains(afterD)
            }
            return false
        }

        /// -ied, -ies 가 아이로 나는지 (cried, flies, satisfied) 이로 나는지 (ladies, married).
        private func iedIsLong(at k: Int) -> Bool {
            let stem = String(raw[..<k])
            if !stem.contains(where: HangulReading.isVowelChar) { return true }
            return ["f", "pl", "fl", "cr", "tr", "den", "pr", "sp"].contains(where: stem.hasSuffix)
        }

        /// 끝 -ow 는 오우, 나머지는 아우 (yellow, glow / down, power).
        private func owSound(at k: Int) -> Atom {
            let after = rest(from: k + 2)
            let before = String(raw[..<k])
            if ["n", "ns", "ned", "ner", "ners", "ning"].contains(after) {
                let longOwn = ["", "kn", "sh", "gr", "thr", "bl", "fl", "s", "m", "unkn", "overbl", "overthr", "outgr"]
                return longOwn.contains(before) ? .v(.ow) : .v(.aw)
            }
            if after.isEmpty || ["s", "ed", "ing", "ly", "y"].contains(after) {
                return .v(.ow)
            }
            return .v(.aw)
        }

        /// u 계열 긴 모음: r, l, j, ch, sh 뒤는 우, 나머지는 유.
        private func uSound(at k: Int) -> Atom {
            if ch(k - 1) == "l", isV(k - 2) { return .v(.yu) }
            if let previous = ch(k - 1), "rljy".contains(previous) { return .v(.uu) }
            if has("ch", at: k - 2) || has("sh", at: k - 2) { return .v(.uu) }
            return .v(.yu)
        }

        // MARK: 홑모음

        private mutating func scanVowel() {
            let v = raw[i]
            let multi = vowelBefore(i)
            let isLast = i == n - 1
            if long.contains(i) {
                switch v {
                case "a": emit([.v(.ey)], 1)
                case "e": emit([.v(.ii)], 1)
                case "i", "y": emit([.v(.ay)], 1)
                case "o": emit([.v(.oo)], 1)
                default: emit([uSound(at: i)], 1)
                }
                return
            }
            switch v {
            case "a": scanA(multi: multi, isLast: isLast)
            case "e": scanE(multi: multi, isLast: isLast)
            case "i": scanI(multi: multi, isLast: isLast)
            case "o": scanO(multi: multi, isLast: isLast)
            case "u": scanU(isLast: isLast)
            default: scanY(multi: multi, isLast: isLast)
            }
        }

        /// 자음 하나 다음 모음이 오는 열린 음절인지.
        private func openSyllable(after k: Int) -> Bool {
            guard k + 2 < n, isC(k + 1) else { return false }
            if has("th", at: k + 1) || has("sh", at: k + 1) || has("ch", at: k + 1) || has("ph", at: k + 1) {
                return isV(k + 3) && !(ch(k + 3) == "e" && k + 4 == n)
            }
            if raw[k + 1] == "x" { return false }
            return isV(k + 2) && !(raw[k + 2] == "e" && k + 3 == n)
        }

        private mutating func scanA(multi: Bool, isLast: Bool) {
            let after = rest(from: i + 1)
            let next = ch(i + 1)
            if isLast {
                emit([.v(.a)], 1)
                return
            }
            if after == "h", multi {
                emit([.v(.a)], 2)
                return
            }
            // -ation, -asion, -acious, -atient
            if let c = next, "tsc".contains(c), ["ion", "ions", "ious", "ient", "ience", "ial"].contains(rest(from: i + 2)) {
                emit([.v(.ey)], 1)
                return
            }
            if has("all", at: i), i + 3 == n || isC(i + 3) || ["en", "er", "est", "ing"].contains(rest(from: i + 3)) {
                emit([.v(.o), .c(.l)], 3)
                return
            }
            if has("alk", at: i) {
                emit([.v(.o), .c(.k)], 3)
                return
            }
            if has("alm", at: i), i + 3 == n || rest(from: i + 3) == "s" {
                emit([.v(.a), .c(.m)], 3)
                return
            }
            if has("alf", at: i), i + 3 == n || rest(from: i + 3) == "s" {
                emit([.v(.ae), .c(.f)], 3)
                return
            }
            if next == "l", let c = ch(i + 2), "tdswzm".contains(c) {
                emit([.v(.o)], 1)
                return
            }
            let previous = ch(i - 1)
            if previous == "w" || (previous == "u" && ch(i - 2) == "q") {
                emit([.v(.a)], 1)
                return
            }
            // 모음 뒤 a (piano, Asia, trial, diary)
            if i > 0, isV(i - 1) {
                let weak = ["l", "ls", "n", "ns", "nt", "nts", "nce", "nces"].contains(after) || (next == "r" && isV(i + 2))
                emit(weak ? [.v(.eo)] : [.v(.a)], 1)
                return
            }
            // -a 로 끝나는 말의 a 는 아 (banana, camera, America)
            if n >= 4, raw[n - 1] == "a" || has("ah", at: n - 2), !(i > 0 && isV(i - 1)) {
                emit([.v(.a)], 1)
                return
            }
            // 말머리 약한 a- (about, again, amazing, attention)
            if i == 0, unstressedPrefixA() {
                emit([.v(.eo)], 1)
                return
            }
            // 둘째 음절 뒤 a + r + 모음은 약하다 (January, library)
            if multi, next == "r", isV(i + 2) {
                emit([.v(.eo)], 1)
                return
            }
            // 여러 음절 낱말 끝의 약한 a (animal, woman, distance)
            if multi, ["l", "ls", "n", "ns", "m", "ms", "nt", "nts", "nce", "nces", "ncy"].contains(after) {
                emit([.v(.eo)], 1)
                return
            }
            if multi, ["ge", "ges", "ged"].contains(after) {
                emit([.v(.i)], 1)
                return
            }
            if multi, ["ble", "bles", "bly"].contains(after) {
                emit([.v(.eo)], 1)
                return
            }
            emit([.v(.ae)], 1)
        }

        private func unstressedPrefixA() -> Bool {
            guard n >= 5 else { return false }
            var k = 1
            let onsets = ["squ", "bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "pl", "pr", "tr", "sl", "sm", "sn", "sp", "st", "sk", "sw", "sh", "ch", "th", "ph", "wh", "qu"]
            if has("ad", at: 0), isC(2), raw[2] != "d", raw[2] != "r" {
                return true
            }
            if let cluster = onsets.first(where: { has($0, at: 1) }) {
                k += cluster.count
            } else if isC(1), raw[1] != "x" {
                k += 1
                if ch(2) == raw[1] {
                    k += 1
                    if let liquid = ch(k), liquid == "l" || liquid == "r" { k += 1 }
                }
            } else {
                return false
            }
            guard k < n, isV(k) else { return false }
            let remainder = rest(from: k)
            let weak: Set<String> = [
                "le", "les", "y", "ey", "ie", "ow", "ows", "er", "ers", "et", "el", "en", "ic", "ics", "ish", "um",
                "on", "om", "it", "id", "am", "ad", "ab", "ex", "es", "us", "a", "o", "is", "al", "an", "ar",
                "ent", "ence", "ice", "ies", "ia", "ian",
            ]
            return remainder.count >= 3 && !weak.contains(remainder)
        }

        private mutating func scanE(multi: Bool, isLast: Bool) {
            let after = rest(from: i + 1)
            let next = ch(i + 1)
            let previous = ch(i - 1) ?? " "
            if isLast {
                if multi { i += 1 } else { emit([.v(.ii)], 1) }
                return
            }
            // -ed: t/d 뒤 이드, 무성음 뒤 트, 나머지 드
            if after == "d", multi {
                let consonantR = previous == "r" && (ch(i - 2).map(HangulReading.isConsonantChar) ?? false)
                if previous == "t" || previous == "d" || consonantR {
                    emit([.v(.i), .c(.d)], 2)
                } else if "pkfxc".contains(previous) || (previous == "s" && !isV(i - 2)) || has("sh", at: i - 2) || has("ch", at: i - 2) || has("gh", at: i - 2) {
                    emit([.c(.t)], 2)
                } else {
                    emit([.c(.d)], 2)
                }
                return
            }
            // -es: 치찰음 뒤 이즈
            if after == "s", multi {
                let sibilant = "szxcg".contains(previous) || has("ch", at: i - 2) || has("sh", at: i - 2)
                if sibilant {
                    emit([.v(.i), .c(.z)], 2)
                } else {
                    i += 1
                }
                return
            }
            // -en 끝 (hidden, broken, children)
            if after == "n" || after == "ns", multi, HangulReading.isConsonantChar(previous) {
                if previous == "r" {
                    emit([.v(.eo)], 1)
                } else if previous == "w" {
                    emit([.v(.e)], 1)
                } else if has("ch", at: i - 2) || previous == "g" || previous == "j" {
                    emit([.v(.i)], 1)
                } else {
                    emit([.v(.eu)], 1)
                }
                return
            }
            // -el 끝
            if after == "l" || after == "ls", multi, HangulReading.isConsonantChar(previous) {
                if "vbpcsz".contains(previous) {
                    emit([.v(.eu)], 1)
                } else if "tdkl".contains(previous) || has("ch", at: i - 2) {
                    emit([.v(.e)], 1)
                } else {
                    emit([.v(.eo)], 1)
                }
                return
            }
            if multi, ["ness", "less", "st", "sts"].contains(after) {
                emit([.v(.i)], 1)
                return
            }
            if multi, ["nt", "nts", "nce", "nces", "ncy", "ntly"].contains(after) {
                emit([.v(.eo)], 1)
                return
            }
            // 모음 앞 e (video, Romeo)
            if let c = next, "aoiu".contains(c) {
                emit([.v(.ii)], 1)
                return
            }
            // ex- (explain -> 익스플레인, exact -> 이그잭트)
            if i == 0, next == "x", n >= 5 {
                emit([.v(.i)], 1)
                return
            }
            // 둘째 음절 뒤 er + 모음은 약하다 (generation, mystery, different)
            if multi, next == "r", isV(i + 2) {
                emit([.v(.eo)], 1)
                return
            }
            // be-, de-, re-, pre- (believe, remember, prepare, relax)
            if !multi, n >= 5, let c = next, HangulReading.isConsonantChar(c), c != "x",
               (i == 1 && "bdr".contains(raw[0])) || (i == 2 && has("pr", at: 0)) {
                let clusters = ["bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "pl", "pr", "tr", "sp", "st", "str", "scr", "spl", "sw", "ch", "sh", "th", "ph", "wh", "qu"]
                let single = isV(i + 2) && !(raw[i + 2] == "e" && i + 3 == n)
                if single || clusters.contains(where: { has($0, at: i + 1) && isV(i + 1 + $0.count) }) {
                    emit([.v(.ii)], 1)
                    return
                }
            }
            // 말머리 e- (event, emotion, erase)
            if i == 0, let c = next, HangulReading.isConsonantChar(c), c != "x", c != "r", isV(2), n >= 5 {
                var k = 2
                while k < n, isV(k) { k += 1 }
                if long.contains(2) || (k + 1 < n && isC(k) && isC(k + 1)) {
                    emit([.v(.ii)], 1)
                    return
                }
            }
            emit([.v(.e)], 1)
        }

        private mutating func scanI(multi: Bool, isLast: Bool) {
            if isLast {
                emit([multi ? .v(.i) : .v(.ay)], 1)
                return
            }
            let after = rest(from: i + 1)
            if ["gn", "gns", "gned", "gner"].contains(after) {
                emit([.v(.ay), .c(.n)], 3)
                return
            }
            if ["nd", "nds", "nder", "nders", "nding", "ld", "lds", "lder"].contains(after) {
                emit([.v(.ay)], 1)
                return
            }
            // 첫 음절 모음 앞 i (lion, riot, science, quiet)
            if let c = ch(i + 1), "aeou".contains(c), !multi {
                emit([.v(.ay)], 1)
                return
            }
            emit([.v(.i)], 1)
        }

        private mutating func scanO(multi: Bool, isLast: Bool) {
            let after = rest(from: i + 1)
            if isLast {
                emit([.v(.oo)], 1)
                return
            }
            let longEndings: Set<String> = ["ld", "lds", "lder", "lden", "lding", "ldly", "lt", "lts", "ll", "lls", "lled", "lling", "ller", "llers"]
            if longEndings.contains(after) {
                emit([.v(.oo)], 1)
                return
            }
            let openO: Set<String> = ["ng", "ngs", "ff", "ffs", "ft", "ss", "st", "sts", "th", "ths", "g", "gs"]
            if openO.contains(after) || after.hasPrefix("ng") || after.hasPrefix("ff") || after.hasPrefix("ft") {
                emit([.v(.o)], 1)
                return
            }
            if openSyllable(after: i) {
                emit([.v(.oo)], 1)
                return
            }
            if multi, ["m", "ms", "t", "ts"].contains(after) {
                emit([.v(.eo)], 1)
                return
            }
            if multi, ["n", "ns"].contains(after) {
                let previous = ch(i - 1) ?? " "
                emit(["t", "s", "z"].contains(previous) ? [.v(.eu)] : [.v(.eo)], 1)
                return
            }
            emit([.v(.a)], 1)
        }

        private mutating func scanU(isLast: Bool) {
            let next = ch(i + 1)
            if isLast {
                emit([uSound(at: i)], 1)
                return
            }
            let previous = ch(i - 1)
            // pull, push, put, bullet
            if let p = previous, "pbf".contains(p), has("ll", at: i + 1) || has("sh", at: i + 1) || (p == "p" && next == "t") || has("dd", at: i + 1) {
                emit([.v(.u)], 1)
                return
            }
            // un- (until, unless) / uni- (union, unique)
            if i == 0, next == "n" {
                emit([ch(2) == "i" ? .v(.yu) : .v(.eo)], 1)
                return
            }
            if openSyllable(after: i) {
                emit([uSound(at: i)], 1)
                return
            }
            if let c = next, "aeio".contains(c) {
                emit([uSound(at: i)], 1)
                return
            }
            emit([.v(.eo)], 1)
        }

        private mutating func scanY(multi: Bool, isLast: Bool) {
            if isLast {
                let verbY = has("fy", at: i - 1) || has("ply", at: i - 2) || has("eny", at: i - 2) || has("ly", at: i - 1) && ch(i - 2) == "f"
                emit([multi && !verbY ? .v(.i) : .v(.ay)], 1)
                return
            }
            if !multi, openSyllable(after: i), !has("ic", at: i + 2), !has("ical", at: i + 2) {
                emit([.v(.ay)], 1)
                return
            }
            emit([.v(.i)], 1)
        }

        // MARK: 자음

        private mutating func scanConsonant() {
            let c = raw[i]
            let next = ch(i + 1)
            let previous = ch(i - 1)
            // 말머리 묵음 (know, write, psycho, gnaw, honest)
            if i == 0, let second = next {
                if ((c == "k" || c == "g") && second == "n") || (c == "w" && second == "r") || (c == "p" && (second == "s" || second == "n")) {
                    i += 1
                    return
                }
                if c == "h", has("hour", at: 0) || has("honest", at: 0) || has("honor", at: 0) || has("heir", at: 0) {
                    i += 1
                    return
                }
            }
            // con-, com- (connection -> 커넥션, control -> 컨트롤)
            if i == 0, has("con", at: 0) || has("com", at: 0), isC(3), n >= 6 {
                emit([.c(.k), .v(.eo)], 2)
                return
            }
            switch c {
            case "c":
                if has("ch", at: i) {
                    emit([has("chr", at: i) || has("chl", at: i) ? .c(.k) : .c(.ch)], 2)
                } else if has("ck", at: i) || has("cq", at: i) {
                    emit([.c(.k)], 2)
                } else if has("cc", at: i) {
                    if let after = ch(i + 2), "eiy".contains(after) {
                        emit([.c(.k), .c(.s)], 2)
                    } else {
                        emit([.c(.k)], 2)
                    }
                } else if let second = next, "eiy".contains(second) {
                    emit([.c(initialS(at: i))], 1)
                } else {
                    emit([.c(.k)], 1)
                }
            case "s":
                if has("sch", at: i) {
                    emit([.c(.s), .c(.k)], 3)
                } else if has("sh", at: i) {
                    emit([.c(.sh)], 2)
                } else if has("sc", at: i), let after = ch(i + 2), "eiy".contains(after) {
                    emit([.c(initialS(at: i))], 2)
                } else if has("ss", at: i) {
                    emit([.c(.s)], 2)
                } else if i == 0 {
                    emit([.c(initialS(at: i))], 1)
                } else if (has("ouse", at: i - 2) || has("oose", at: i - 2)), i + 2 == n {
                    emit([.c(.s)], 1)
                } else if silent.contains(i + 1) {
                    // 끝 -se 는 z (rise, wise), -ase 와 낱말 안은 s (base, basement, useful)
                    emit([i + 2 == n && previous != "a" ? .c(.z) : .c(.s)], 1)
                } else if let p = previous, HangulReading.isVowelChar(p), let second = next, HangulReading.isVowelChar(second) {
                    // 모음 사이 s 는 z (music, easy, reason)
                    emit([.c(.z)], 1)
                } else if i == n - 1, let p = previous {
                    // 끝 -s: 유성음 뒤는 z
                    let voiced = HangulReading.isVowelChar(p) || "bdglmnrvwz".contains(p)
                    let quiet = has("us", at: i - 1) || has("is", at: i - 1) || has("as", at: i - 1) || has("ths", at: i - 2) || has("phs", at: i - 2) || has("ghs", at: i - 2)
                    emit([voiced && !quiet ? .c(.z) : .c(.s)], 1)
                } else if next == "m", i + 2 == n {
                    emit([.c(.z)], 1)
                } else {
                    emit([.c(.s)], 1)
                }
            case "t":
                if has("tch", at: i) {
                    emit([.c(.ch)], 3)
                } else if has("th", at: i) {
                    let after = rest(from: i + 2)
                    let voiced = (has("ther", at: i) && i > 0) || ["e", "es", "ed"].contains(after) || (has("thing", at: i) && i > 0 && raw[i - 1] == "e")
                    emit([voiced ? .c(.d) : .c(.ss)], 2)
                } else if i > 0, next == "u", isV(i + 2), vowelBefore(i) {
                    // situation -> 씨추에이션, statue -> 스태추
                    emit([.c(.ch), .v(.uu)], 2)
                } else if i > 0, isFlapT(at: i) {
                    emit([.c(.r)], has("tt", at: i) ? 2 : 1)
                } else {
                    emit([.c(.t)], has("tt", at: i) ? 2 : 1)
                }
            case "p":
                emit([has("ph", at: i) ? .c(.f) : .c(.p)], has("ph", at: i) || has("pp", at: i) ? 2 : 1)
            case "w":
                if has("wh", at: i) {
                    emit([has("who", at: i) ? .c(.h) : .c(.w)], 2)
                } else {
                    emit([.c(.w)], 1)
                }
            case "g":
                if has("gh", at: i) {
                    if i == 0 { emit([.c(.g)], 2) } else { i += 2 }
                } else if has("gn", at: i), i + 2 == n || ["s", "ed", "ing", "er"].contains(rest(from: i + 2)) {
                    i += 1
                } else if has("gu", at: i), let after = ch(i + 2), "aeiy".contains(after) {
                    emit([.c(.g)], 2)
                } else if has("gg", at: i) {
                    emit([.c(.g)], 2)
                } else if let second = next, "eiy".contains(second), softG(at: i) {
                    emit([.c(.j)], 1)
                } else {
                    emit([.c(.g)], 1)
                }
            case "n":
                if has("ng", at: i) {
                    let after = rest(from: i + 2)
                    if let liquid = ch(i + 2), liquid == "l" || liquid == "r" {
                        // single -> 씽글, hungry -> 헝그리
                        emit([.c(.ng), .c(.g)], 2)
                    } else if after.isEmpty || !isV(i + 2) || ["ing", "ings"].contains(after) {
                        emit([.c(.ng)], 2)
                    } else if let soft = ch(i + 2), "eiy".contains(soft), softG(at: i + 1) {
                        emit([.c(.n), .c(.j)], 2)
                    } else {
                        emit([.c(.ng), .c(.g)], 2)
                    }
                } else if has("nk", at: i) || (has("nc", at: i) && !has("nch", at: i) && !(ch(i + 2).map { "eiy".contains($0) } ?? false)) {
                    emit([.c(.ng)], 1)
                } else {
                    emit([.c(.n)], has("nn", at: i) ? 2 : 1)
                }
            case "x":
                if let after = ch(i + 2), ch(i + 1) == "c", "eiy".contains(after) {
                    emit([.c(.k), .c(.s)], 2)
                } else if i == 0 {
                    emit([.c(.z)], 1)
                } else if i == 1, raw[0] == "e", isV(2) || ch(2) == "h" {
                    emit([.c(.g), .c(.z)], 1)
                } else {
                    emit([.c(.k), .c(.s)], 1)
                }
            case "q":
                emit(has("qu", at: i) ? [.c(.k), .c(.w)] : [.c(.k)], has("qu", at: i) ? 2 : 1)
            case "d":
                if has("dge", at: i) {
                    emit([.c(.j)], 3)
                } else if has("dg", at: i) || has("dj", at: i) {
                    emit([.c(.j)], 2)
                } else {
                    emit([.c(.d)], has("dd", at: i) ? 2 : 1)
                }
            case "h":
                if i > 0, !isV(i + 1) {
                    i += 1
                } else {
                    emit([.c(.h)], 1)
                }
            case "l":
                emit([.c(.l)], has("ll", at: i) ? 2 : 1)
            case "y":
                emit([.c(.y)], 1)
            case "b":
                if has("bt", at: i), i > 0 {
                    i += 1
                } else {
                    emit([.c(.b)], has("bb", at: i) ? 2 : 1)
                }
            case "r":
                emit([.c(.r)], has("rh", at: i) || has("rr", at: i) ? 2 : 1)
            default:
                emit([.c(HangulReading.letterConsonant(c))], next == c ? 2 : 1)
            }
        }

        /// 말머리 s + 모음은 된소리 ㅆ 으로 적는다 (so -> 쏘, sing -> 씽). su + 열린 음절은 슈 (super).
        private func initialS(at k: Int) -> Consonant {
            guard k == 0 else { return .s }
            let softC = has("sc", at: k) && (ch(k + 2).map { "eiy".contains($0) } ?? false)
            let vowelIndex = softC ? k + 2 : k + 1
            guard isV(vowelIndex) else { return .s }
            if ch(vowelIndex) == "u", openSyllable(after: vowelIndex) { return .s }
            return .ss
        }

        /// g + e/i/y 를 ㅈ 으로 읽을지 (gentle, giant / get, give, finger).
        private func softG(at k: Int) -> Bool {
            let after = rest(from: k + 1)
            let hardStarts = ["et", "ive", "ift", "ig", "irl", "ear", "eek", "ild", "ills", "iggle", "eese", "ue"]
            if k == 0, hardStarts.contains(where: { after.hasPrefix($0) }) { return false }
            if k > 0, raw[k - 1] == "n", after.hasPrefix("er") {
                // finger, hunger 는 g 를 살리고 danger, passenger 는 ㅈ
                return long.contains(k - 2) || ch(k - 2) == "e"
            }
            return true
        }

        /// 모음(또는 모음+r) 뒤의 t/tt 가 약한 모음 어미 앞에 오면 굴린다 (water -> 워러, little -> 리를, party -> 파리).
        private func isFlapT(at k: Int) -> Bool {
            let previous = raw[k - 1]
            let afterVowelOrR = HangulReading.isVowelChar(previous) || (previous == "r" && k >= 2 && HangulReading.isVowelChar(raw[k - 2]))
            guard afterVowelOrR else { return false }
            let afterT = (k + 1 < n && raw[k + 1] == "t") ? k + 2 : k + 1
            guard afterT < n else { return false }
            let tail = rest(from: afterT)
            let flapTails: Set<String> = [
                "er", "ers", "ered", "ering", "le", "les", "led", "y", "ies", "ied", "ier", "iest", "ily",
                "ing", "ings", "ed", "om", "oms", "iful", "ifully", "able", "ie",
            ]
            return flapTails.contains(tail)
        }
    }

    static func letterConsonant(_ char: Character) -> Consonant {
        switch char {
        case "b": return .b
        case "d": return .d
        case "f": return .f
        case "j": return .j
        case "k": return .k
        case "m": return .m
        case "v": return .v
        case "z": return .z
        default: return .s
        }
    }
}
