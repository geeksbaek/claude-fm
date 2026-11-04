import Foundation

/// 일본어: 낱말마다 받은 로마자 읽기를 한글 음절로 옮긴다.
extension HangulReading {
    static func japanese(_ text: String) -> String {
        var prepared = text
        for (target, kana) in japaneseReadingReplacements {
            prepared = prepared.replacingOccurrences(of: target, with: kana)
        }
        var words: [[Syl]] = []
        var pendingSokuon = false
        var attachNextToPrefix = false
        let prefixKanji: Set<String> = ["未", "非", "不", "無", "超", "再", "新", "全", "反", "真", "最", "大", "小", "高", "低"]
        for token in japaneseTokens(prepared) {
            let raw = token.raw
            var latin = token.latin
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

    static let japaneseReadingReplacements: [(String, String)] = [
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
    static func shouldAttachJapaneseToken(raw: String, latin: String) -> Bool {
        guard !raw.isEmpty, raw.allSatisfy(isKana) else { return false }
        if attachedJapaneseTokens.contains(raw) || attachedJapaneseRomaji.contains(latin.lowercased()) {
            return true
        }
        return raw.count == 1
    }

    static let attachedJapaneseTokens: Set<String> = [
        "て", "で", "た", "だ", "ない", "たい", "たら", "たり", "てる", "でる", "てた", "でた", "てん", "でん", "てんだ", "でんだ",
        "れる", "られる", "せる", "させる", "れ", "せ", "られ", "させ", "ちゃう", "じゃう", "ちゃ", "じゃ",
        "よう", "ましょう", "ましょ", "だろう", "だろ", "でしょう", "でしょ",
        "から", "まで", "より", "だけ", "ばかり", "ほど", "くらい", "ぐらい", "なんて", "なんか",
        "って", "っぱなし", "いく", "くる", "おく", "みる",
    ]

    static let attachedJapaneseRomaji: Set<String> = [
        "te", "de", "ta", "da", "nai", "tai", "tara", "tari", "teru", "deru", "teta", "deta", "ten", "den", "tenda", "denda",
        "reru", "rareru", "seru", "saseru", "re", "se", "rare", "sase", "chau", "jau", "cha", "ja",
        "you", "mashou", "masho", "darou", "daro", "deshou", "desho",
        "kara", "made", "yori", "dake", "bakari", "hodo", "kurai", "gurai", "nante", "nanka",
        "iku", "kuru", "oku", "miru",
    ]

    /// 실제 노래 발음에 맞춰 カ·タ·チャ·ツ 행을 ㅋ·ㅌ·ㅊ·츠로 적고, 촉음은 ㅅ 받침으로 적는다.
    static func romajiSyllables(_ raw: String) -> (syllables: [Syl], leadingSokuon: Bool, trailingSokuon: Bool) {
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

    struct Syl {
        var cho: Int
        var jung: Int
        var jong: Int = 0
        var raw: String? = nil
        var text: String { raw ?? HangulReading.syllable(cho, jung, jong) }
    }

    static func parseRomaji(_ raw: String, into syllables: inout [Syl]) -> (leadingSokuon: Bool, trailingSokuon: Bool) {
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
    static func sokuon(_ chars: [Character], _ index: Int) -> Int? {
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

    static func isRomajiConsonant(_ char: Character) -> Bool {
        "kgstdnhbpmrjcfywz".contains(char)
    }

    static func collapseJapaneseLongVowels(_ text: String) -> String {
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

    static func mora(_ chars: [Character], _ index: Int) -> (Int, Int, Int)? {
        for length in [3, 2, 1] where index + length <= chars.count {
            let key = String(chars[index..<(index + length)])
            if let hit = moraMap[key] { return (hit.0, hit.1, length) }
        }
        return nil
    }

    /// カ·タ·チャ 행은 언제나 ㅋ·ㅌ·ㅊ, ツ 는 츠로 적는다.
    static let moraMap: [String: (Int, Int)] = {
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
}
