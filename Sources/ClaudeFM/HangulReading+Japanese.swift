import Foundation

/// 일본어: 낱말마다 받은 로마자 읽기를 한글 음절로 옮긴다.
/// 낱말 나누기와 로마자는 운영체제가 주고, 여기서는 가사에 맞게 읽기를 고친 뒤 붙여 부르는 말끼리 묶는다.
extension HangulReading {
    /// 가사 읽기에 쓰는 일본어 낱말. 숫자와 조수사를 하나로 묶은 낱말은 `number` 다.
    struct JapaneseWord {
        var raw: String
        var latin: String
        var number = false
    }

    static func japanese(_ text: String) -> String {
        var prepared = text
        for (target, kana) in japaneseReadingReplacements {
            prepared = prepared.replacingOccurrences(of: target, with: kana)
        }
        let tokens = lyricJapaneseWords(japaneseTokens(prepared))
        var words: [[Syl]] = []
        var pendingSokuon = false
        for index in tokens.indices {
            let token = tokens[index]
            let reading = romajiSyllables(token.latin, keepFinalU: endsWithVerbU(token.raw))
            if reading.syllables.isEmpty, !reading.trailingSokuon {
                // 일본어로 못 읽는 한자(爱你처럼 중국어만 있는 글자)는 중국어 발음으로 남긴다.
                if token.raw.contains(where: isHan) {
                    let fallback = chinese(token.raw, orJapanese: false)
                    if !fallback.isEmpty {
                        words.append([Syl(cho: 11, jung: 0, raw: fallback)])
                    }
                }
                pendingSokuon = false
                continue
            }
            if (reading.leadingSokuon || pendingSokuon), let lastWord = words.indices.last,
               let lastSyl = words[lastWord].indices.last {
                words[lastWord][lastSyl].jong = 19
                words[lastWord].append(contentsOf: reading.syllables)
            } else if index > 0, attachesJapanese(tokens, at: index), let lastWord = words.indices.last {
                // 따로 떨어진 ん 은 앞 음절의 받침으로 붙인다.
                if let first = reading.syllables.first, first.cho == 11, first.jung == 18, first.jong != 0,
                   let lastSyl = words[lastWord].indices.last, words[lastWord][lastSyl].jong == 0 {
                    words[lastWord][lastSyl].jong = first.jong
                    words[lastWord].append(contentsOf: reading.syllables.dropFirst())
                } else {
                    words[lastWord].append(contentsOf: reading.syllables)
                }
            } else if !reading.syllables.isEmpty {
                words.append(reading.syllables)
            }
            if reading.trailingSokuon, let lastWord = words.indices.last,
               let lastSyl = words[lastWord].indices.last {
                words[lastWord][lastSyl].jong = 19
            }
            pendingSokuon = reading.trailingSokuon
        }
        let pieces = words.map { $0.map(\.text).joined() }.filter { !$0.isEmpty }
        if pieces.isEmpty, text.contains(where: isHan) {
            return chinese(text, orJapanese: false)
        }
        return pieces.joined(separator: " ")
    }

    static let japaneseReadingReplacements: [(String, String)] = [
        ("何時だって", "いつだって"), ("何時でも", "いつでも"), ("何時か", "いつか"), ("何時も", "いつも"),
    ]

    /// 중국어에서는 쓰지 않고 일본에서만 쓰는 한자(신자체·국자)와 반복 부호. 가나 없는 줄을 일본어로 읽는 근거다.
    static let japaneseOnlyKanji: Set<Character> = Set(
        "々〆気涙桜歳楽様悪変戦駅実続絵緑縁経帰覚観関髪発歩毎顔険頼駆転軽辺遅郷酔読売黒広図対単円歯竜両仏伝児団囲圧壊専巣巻"
            + "帯応恵悩戻拝挙撃晩栄検権歓歴渋満焼獣畳県砕粋糸総聴脳臓蔵薬蛍訳証譲豊賛鉄銭録闘隠雑霊顕騒験鶏黙齢弾浜沢剣込働畑峠"
            + "辻匂枠雫凪呟掴拡抜塩揺姫継艶偽謡縄鋭隣醸斉剤労勧奨嬢寛従徳徴舗渓稲穂穏窓駄咲氷処拠捜摂斎暦桟殻浄犠猟粛縦聡荘覇覧"
            + "鉱鋳錬陥髄麺亀乗亜仮価倹剰勲収営塁壌庁廃弐懐戯払択挿掲暁曽渇滝痩繊脇舎薫説逓釈閲鞄頬"
    )

    // MARK: - 낱말 고치기

    /// 운영체제가 준 낱말을 가사 읽기에 맞게 고친다.
    /// 떨어진 작은 가나를 잇고, 묶어 읽는 말과 조사·문맥에 따른 한자 읽기를 고치고, 숫자와 조수사를 한 낱말로 읽는다.
    static func lyricJapaneseWords(_ source: [Token]) -> [JapaneseWord] {
        var words: [JapaneseWord] = []
        for token in source {
            let latin = token.latin.lowercased()
                .replacingOccurrences(of: "ゕ", with: "ka")
                .replacingOccurrences(of: "ゖ", with: "ka")
            if latin.hasPrefix("~"), !latin.hasPrefix("~tsu"), let last = words.indices.last {
                words[last].raw += token.raw
                words[last].latin += latin
                continue
            }
            words.append(JapaneseWord(raw: token.raw, latin: latin))
        }
        words = joinJapanesePhrases(words)
        for index in words.indices {
            words[index].latin = japaneseLyricReading(words, at: index)
        }
        return mergeJapaneseNumbers(words)
    }

    /// 여러 낱말로 나뉘어 나오거나 다르게 읽히는 말을 한 낱말로 묶어 가사에서 부르는 대로 읽는다.
    static let japanesePhraseReadings: [String: String] = [
        "三日月": "mikazuki", "一番星": "ichibanboshi", "七夕": "tanabata", "富士山": "fujisan", "万が一": "mangaichi",
        "お母さん": "okaasan", "お父さん": "otousan", "お兄ちゃん": "oniichan", "お兄さん": "oniisan",
        "お姉ちゃん": "oneechan", "お姉さん": "oneesan", "おばあちゃん": "obaachan", "おじいちゃん": "ojiichan",
        "母さん": "kaasan", "父さん": "tousan", "兄さん": "niisan", "姉さん": "neesan",
        "かっこいい": "kakkoii", "こんにちは": "konnichiwa", "こんばんは": "konbanwa", "何もかも": "nanimokamo",
        "今朝": "kesa", "今宵": "koyoi", "一昨日": "ototoi", "明後日": "asatte", "眼鏡": "megane", "浴衣": "yukata",
        "一人一人": "hitorihitori", "一人ひとり": "hitorihitori", "一日中": "ichinichijuu", "世界中": "sekaijuu",
        "日本中": "nihonjuu", "一晩中": "hitobanjuu", "一年中": "ichinenjuu", "体中": "karadajuu",
        "誕生日": "tanjoubi", "日本一": "nihon'ichi", "世界一": "sekaiichi", "一期一会": "ichigoichie",
        "春夏秋冬": "shunkashuutou", "喜怒哀楽": "kidoairaku", "花鳥風月": "kachoufuugetsu", "蜃気楼": "shinkirou",
        "金木犀": "kinmokusei", "千本桜": "senbonzakura", "雪景色": "yukigeshiki",
        "いつの間にか": "itsunomanika", "いつの間に": "itsunomani",
        "月曜日": "getsuyoubi", "火曜日": "kayoubi", "水曜日": "suiyoubi", "木曜日": "mokuyoubi",
        "金曜日": "kin'youbi", "土曜日": "doyoubi", "日曜日": "nichiyoubi",
    ]

    static func joinJapanesePhrases(_ words: [JapaneseWord]) -> [JapaneseWord] {
        var out: [JapaneseWord] = []
        var index = 0
        while index < words.count {
            var matched = false
            for end in stride(from: min(words.count, index + 5), to: index + 1, by: -1) {
                let raw = words[index..<end].map(\.raw).joined()
                if let latin = japanesePhraseReadings[raw] {
                    out.append(JapaneseWord(raw: raw, latin: latin))
                    index = end
                    matched = true
                    break
                }
            }
            if !matched, let latin = japanesePhraseReadings[words[index].raw] {
                out.append(JapaneseWord(raw: words[index].raw, latin: latin))
                index += 1
                matched = true
            }
            if !matched {
                out.append(words[index])
                index += 1
            }
        }
        return out
    }

    /// 조사 は·へ·を, 가사에서 흔히 다르게 읽는 한자(私·明日·何)를 고친다.
    static func japaneseLyricReading(_ words: [JapaneseWord], at index: Int) -> String {
        let word = words[index]
        let next = index + 1 < words.count ? words[index + 1].raw : nil
        switch (word.raw, word.latin) {
        case ("は", "ha"): return "wa"
        case ("へ", "he"): return "e"
        case ("を", _), ("ヲ", _): return "o"
        case ("ゐ", _), ("ヰ", _): return "i"
        case ("ゑ", _), ("ヱ", _): return "e"
        case ("私", "watakushi"): return "watashi"
        case ("明日", "asu"), ("明日", "myounichi"): return "ashita"
        case (_, _) where word.raw.count == 1 && japaneseKunReadings[word.raw]?.on.contains(word.latin) == true:
            return japaneseKunReadings[word.raw]!.kun
        case ("何", "nan"):
            // 何も·何を·何が·何か 는 なに, 何で·何の·何だ·何度 는 なん.
            if next == nil || ["を", "が", "も", "か", "に", "より", "かも", "も"].contains(next!) { return "nani" }
            return "nan"
        default: return word.latin
        }
    }

    /// 홀로 선 한 글자 낱말을 음으로 읽었을 때(風 fuu) 가사에서 부르는 훈으로 고친다.
    static let japaneseKunReadings: [String: (on: Set<String>, kun: String)] = [
        "風": (["fuu", "fu"], "kaze"), "空": (["kuu"], "sora"), "夢": (["mu"], "yume"), "心": (["shin"], "kokoro"),
        "花": (["ka"], "hana"), "雨": (["u"], "ame"), "涙": (["rui"], "namida"), "声": (["sei", "shou"], "koe"),
        "夜": (["ya"], "yoru"), "星": (["sei", "shou"], "hoshi"), "海": (["kai"], "umi"), "光": (["kou"], "hikari"),
        "道": (["dou"], "michi"), "手": (["shu"], "te"), "胸": (["kyou"], "mune"), "音": (["on", "in"], "oto"),
        "恋": (["ren"], "koi"), "命": (["mei"], "inochi"), "春": (["shun"], "haru"), "夏": (["ka", "ge"], "natsu"),
        "秋": (["shuu"], "aki"), "冬": (["tou"], "fuyu"), "雪": (["setsu"], "yuki"), "桜": (["ou"], "sakura"),
        "鳥": (["chou"], "tori"), "瞳": (["dou"], "hitomi"), "翼": (["yoku"], "tsubasa"), "傷": (["shou"], "kizu"),
        "時": (["ji"], "toki"), "人": (["jin", "nin"], "hito"),
    ]

    /// 앞 낱말이 동사 て 꼴의 で 인지(飛んで·泳いで). 명사 뒤 で 는 조사다.
    static func isJapaneseTeForm(_ words: [JapaneseWord], at index: Int) -> Bool {
        guard index >= 0, words[index].raw == "て" || words[index].raw == "で" else { return false }
        guard words[index].raw == "で" else { return true }
        guard index > 0, let last = words[index - 1].raw.last else { return false }
        return last == "ん" || last == "い"
    }

    // MARK: - 붙여 부르기

    /// 앞말에 붙여 부르는지. 조사·어미·보조 용언·접미사는 붙이고, 조사 뒤에 오는 동사는 새 낱말로 띄운다.
    static func attachesJapanese(_ words: [JapaneseWord], at index: Int) -> Bool {
        let word = words[index]
        let previous = words[index - 1]
        if japanesePrefixes.contains(previous.raw) { return true }
        if word.raw == "お" || word.raw == "ご" { return false }
        if word.number { return false }
        if previous.number, japaneseNumberSuffixes.contains(word.raw) { return true }
        if japaneseSuffixes.contains(word.raw) { return true }
        if word.raw == "中", word.latin == "juu" || word.latin == "chuu" { return true }
        if word.raw == "君", word.latin == "kun" { return true }
        // バイバイ 처럼 되풀이한 가타카나
        if word.raw == previous.raw, word.raw.allSatisfy({ isKana($0) && !isHiragana($0) }) { return true }
        guard word.raw.allSatisfy(isKana) else {
            // 地平線·放課後 처럼 한자어 뒤에 따로 떨어진 한 글자 한자는 앞말에 붙인다(뒤에 어미가 오면 동사라 띄운다).
            if word.raw.count == 1, !previous.number, !previous.raw.isEmpty,
               previous.raw.allSatisfy({ isHan($0) || (isKana($0) && !isHiragana($0)) }) {
                let next = index + 1 < words.count ? words[index + 1].raw : nil
                if next == nil || next!.contains(where: isHan) || ["の", "が", "を", "に", "は", "へ", "と", "も", "で", "や"].contains(next!) {
                    return true
                }
            }
            // 走り出す·探し続ける 처럼 동사 연용형 뒤의 뒷동사
            return isJapaneseVerbStem(previous) && japaneseCompoundTails.contains { word.raw.hasPrefix($0) }
        }
        let core = word.raw.count > 1 && word.raw.hasSuffix("っ") ? String(word.raw.dropLast()) : word.raw
        if japaneseBlockingParticles.contains(previous.raw), japaneseVerbHeads.contains(core) { return false }
        if previous.raw == "じゃ" || previous.raw == "では", ["い", "し", "き", "み", "いる", "いく", "くる"].contains(core) { return false }
        if attachedJapaneseTokens.contains(core) { return true }
        if core.hasPrefix("ちゃ") || core.hasPrefix("じゃ") { return true }
        if isJapaneseTeForm(words, at: index - 1), japaneseTeAuxiliaries.contains(core) { return true }
        if previous.raw == "で", ["い", "し", "き", "み"].contains(core) { return false }
        if core == "そう", isJapaneseVerbStem(previous) { return true }
        // どうしよう·どうすれば 는 한 말로 부른다
        if previous.raw == "どう", let first = core.first, "しすさせ".contains(first) { return true }
        return word.raw.count == 1 || ["て", "で", "た", "だ"].contains(core)
    }

    static func isHiragana(_ char: Character) -> Bool {
        guard let value = scalarValue(char) else { return false }
        return (0x3040...0x309F).contains(value)
    }

    /// 조사·어미·조동사처럼 언제나 앞말에 붙는 가나 조각. 끝의 っ 는 떼고 견준다.
    static let attachedJapaneseTokens: Set<String> = [
        "から", "まで", "より", "だけ", "しか", "ばかり", "ほど", "くらい", "ぐらい", "など", "なんて", "なんか",
        "って", "ってば", "っけ", "けど", "けれど", "けれども", "のに", "ので", "なら", "ながら", "つつ", "かな", "かしら",
        "かも", "じゃん", "じゃ", "こそ", "さえ", "すら", "ずつ", "でも", "とか", "もん", "ねえ",
        "たい", "たく", "たか", "たけれ", "たきゃ", "たら", "たり", "てる", "てた", "てん", "てんだ", "でる", "でた", "でん", "でんだ",
        "ちゃう", "ちゃ", "ちゃお", "ちゃえ", "ちゃい", "じゃう", "じゃお", "じゃえ", "じゃい",
        "れる", "られる", "せる", "させる", "られ", "させ", "ます", "まし", "ませ", "ましょ", "ましょう",
        "です", "でし", "でしょ", "でしょう", "だろ", "だろう", "だ", "よう", "まい", "らしい", "みたい", "っぱなし",
        "ない", "なく", "なか", "なけれ", "なきゃ", "なくちゃ", "なくて", "なさい",
        "すぎ", "すぎる", "すぎた", "すぎて", "しれ", "がる", "がっ", "げ", "きり", "っきり",
    ]

    /// 동사 て·で 꼴 뒤에서만 붙는 보조 용언.
    static let japaneseTeAuxiliaries: Set<String> = [
        "いる", "い", "いた", "いて", "います", "いま", "いく", "いき", "いけ", "いこ",
        "くる", "き", "きた", "きて", "こ", "くれ", "くれる", "くれた", "くれて", "あげ", "あげる", "あげた",
        "もらう", "もら", "もらい", "おく", "おい", "おこ", "おか", "しまう", "しま", "しまい", "しまえ", "しまお",
        "みる", "み", "みた", "みて", "みよ", "みせ", "みよう", "いこう", "おこう", "しまおう", "あげよう", "もらおう",
    ]

    /// 격조사 바로 뒤에서는 새 낱말을 여는 동사·형용사 머리. (に いて, を して, が ない)
    static let japaneseVerbHeads: Set<String> = [
        "い", "し", "き", "み", "いく", "くる", "みる", "ない", "なく", "なか", "なけれ", "なら",
    ]

    static let japaneseBlockingParticles: Set<String> = [
        "は", "が", "を", "に", "へ", "も", "の", "や", "か", "よ", "ね", "な", "わ", "さ", "ぞ", "ぜ",
        "しか", "さえ", "だけ", "まで", "から", "より", "こそ", "でも", "とか", "ばかり", "ほど", "くらい", "ぐらい",
        "など", "なんて", "なんか", "って", "けど", "けれど", "のに", "ので", "には", "では", "とは",
    ]

    /// 다음 낱말을 앞에 붙이는 접두어.
    static let japanesePrefixes: Set<String> = [
        "お", "ご", "第", "未", "非", "不", "無", "超", "再", "新", "全", "反", "真", "最", "大", "小", "高", "低",
        "各", "毎", "両", "諸", "副", "準", "総", "被", "旧",
    ]

    /// 앞말에 붙는 접미사.
    static let japaneseSuffixes: Set<String> = [
        "様", "さま", "さん", "ちゃん", "くん", "たち", "達", "ども", "共", "等", "的", "ぶり", "ごと", "だらけ", "っぽい",
    ]

    /// 숫자 낱말 뒤에 붙는 말 (十年後, 三日前, 二度目).
    static let japaneseNumberSuffixes: Set<String> = ["後", "前", "間", "目", "中", "頃", "ごろ", "ぶり", "以上", "以下", "越し", "パーセント"]

    /// 동사 연용형 뒤에 붙어 한 동사가 되는 뒷동사.
    static let japaneseCompoundTails: [String] = [
        "出す", "出し", "出せ", "出そ", "出さ", "続け", "続く", "続き", "始め", "合う", "合い", "合え", "合お", "合わ",
        "込む", "込ん", "込み", "込め", "切る", "切っ", "切れ", "切り", "上がる", "上がっ", "上がれ", "上がり", "上げ",
        "付け", "付い", "掛け", "過ぎ", "直す", "直し", "抜く", "抜け", "抜い", "返す", "返し", "尽く", "回る", "回っ",
        "去る", "去っ", "去り", "寄せ", "放つ", "放っ", "放し",
    ]

    /// 동사·형용사 연용형(い단·え단 가나로 끝나는 말)인지.
    static func isJapaneseVerbStem(_ word: JapaneseWord) -> Bool {
        guard let last = word.raw.last, !attachedJapaneseTokens.contains(word.raw), !word.number else { return false }
        guard word.raw.count > 1 || word.raw.contains(where: isHan) else { return false }
        return "いきしちにひみりぎじぢびぴえけせてねへめれげぜでべぺイキシチニヒミリギジビピエケセテネヘメレゲゼデベペ".contains(last)
    }

    /// 思う·迷う 처럼 한자 뒤 う 로 끝나는 동사는 끝 う 를 장음으로 줄이지 않는다.
    static func endsWithVerbU(_ raw: String) -> Bool {
        let chars = Array(raw)
        guard chars.count >= 2, chars[chars.count - 1] == "う" else { return false }
        return isHan(chars[chars.count - 2])
    }

    // MARK: - 숫자와 조수사

    static let japaneseNumeralDigits: [Character: Int] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    static let japaneseNumeralUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    static let japaneseNumeralGroups: [Character: Int] = ["万": 10_000, "億": 100_000_000]

    static func isJapaneseNumeral(_ raw: String) -> Bool {
        !raw.isEmpty && raw.allSatisfy {
            japaneseNumeralDigits[$0] != nil || japaneseNumeralUnits[$0] != nil || japaneseNumeralGroups[$0] != nil
        }
    }

    static func japaneseNumeralValue(_ raw: String) -> Int? {
        var total = 0
        var section = 0
        var digit: Int?
        for char in raw {
            if let value = japaneseNumeralDigits[char] {
                // 숫자가 너무 길면 넘치기 전에 운영체제 읽기로 돌린다.
                guard (digit ?? 0) < 100_000_000 else { return nil }
                digit = (digit ?? 0) * 10 + value
            } else if let unit = japaneseNumeralUnits[char] {
                section += (digit ?? 1) * unit
                digit = nil
            } else if let group = japaneseNumeralGroups[char] {
                let base = section + (digit ?? 0)
                total += (base == 0 ? 1 : base) * group
                section = 0
                digit = nil
            } else {
                return nil
            }
        }
        let value = total + section + (digit ?? 0)
        // 1조 넘는 수는 万·億 로 읽을 수 없다.
        return value < 1_000_000_000_000 ? value : nil
    }

    enum JapaneseCounterSound { case plain, gemK, gemS, gemP, day, native, person }

    /// 조수사: 읽기, 숫자와 만나 바뀌는 소리. gemP 는 (ほ·ぽ·ぼ) 세 꼴을 `|` 로 나눠 둔다.
    static let japaneseCounters: [String: (reading: String, sound: JapaneseCounterSound)] = [
        "人": ("nin", .person), "人目": ("ninme", .person), "つ": ("tsu", .native),
        "日": ("nichi", .day), "日間": ("nichikan", .day), "日目": ("nichime", .day),
        "回": ("kai", .gemK), "回目": ("kaime", .gemK), "個": ("ko", .gemK), "階": ("kai", .gemK), "曲": ("kyoku", .gemK),
        "ヶ月": ("kagetsu", .gemK), "か月": ("kagetsu", .gemK), "ヵ月": ("kagetsu", .gemK), "カ月": ("kagetsu", .gemK),
        "歳": ("sai", .gemS), "才": ("sai", .gemS), "冊": ("satsu", .gemS), "週": ("shuu", .gemS), "週間": ("shuukan", .gemS),
        "本": ("hon|pon|bon", .gemP), "杯": ("hai|pai|bai", .gemP), "匹": ("hiki|piki|biki", .gemP),
        "分": ("fun|pun|pun", .gemP), "分間": ("funkan|punkan|punkan", .gemP), "歩": ("ho|po|po", .gemP),
        "度": ("do", .plain), "度目": ("dome", .plain), "年": ("nen", .plain), "年間": ("nenkan", .plain), "年目": ("nenme", .plain),
        "時": ("ji", .plain), "時間": ("jikan", .plain), "月": ("gatsu", .plain), "秒": ("byou", .plain), "秒間": ("byoukan", .plain),
        "枚": ("mai", .plain), "番": ("ban", .plain), "番目": ("banme", .plain), "円": ("en", .plain), "倍": ("bai", .plain),
        "位": ("i", .plain), "号": ("gou", .plain), "点": ("ten", .plain), "通り": ("toori", .plain), "章": ("shou", .plain),
    ]

    /// 숫자(한자 숫자 낱말이나 何)와 뒤따르는 조수사를 한 낱말로 묶어 읽는다.
    static func mergeJapaneseNumbers(_ source: [JapaneseWord]) -> [JapaneseWord] {
        // 三本(mimoto)처럼 숫자와 조수사가 한 낱말로 나와 다르게 읽히면 나눠서 다시 읽는다. 十分(juubun, 충분히)은 둔다.
        var words: [JapaneseWord] = []
        for word in source {
            let digits = word.raw.prefix { japaneseNumeralDigits[$0] != nil || japaneseNumeralUnits[$0] != nil || japaneseNumeralGroups[$0] != nil }
            let rest = String(word.raw.dropFirst(digits.count))
            if !digits.isEmpty, japaneseCounters[rest] != nil, word.latin != "juubun" {
                words.append(JapaneseWord(raw: String(digits), latin: ""))
                words.append(JapaneseWord(raw: rest, latin: ""))
            } else {
                words.append(word)
            }
        }
        var out: [JapaneseWord] = []
        var index = 0
        var afterMonth = false
        while index < words.count {
            var end = index
            while end < words.count, isJapaneseNumeral(words[end].raw) { end += 1 }
            let isNan = end == index && words[index].raw == "何"
            if isNan { end = index + 1 }
            guard end > index else {
                out.append(words[index])
                index += 1
                afterMonth = false
                continue
            }
            var counter: String?
            var counterEnd = end
            if end + 1 < words.count, japaneseCounters[words[end].raw + words[end + 1].raw] != nil {
                counter = words[end].raw + words[end + 1].raw
                counterEnd = end + 2
            } else if end < words.count, japaneseCounters[words[end].raw] != nil {
                counter = words[end].raw
                counterEnd = end + 1
            }
            let numeral = words[index..<end].map(\.raw).joined()
            let value = isNan ? nil : japaneseNumeralValue(numeral)
            if counter == nil, isNan || end - index == 1 || value == nil {
                // 조수사 없는 낱말 하나는 운영체제 읽기를 그대로 둔다.
                for word in words[index..<end] {
                    var number = word
                    number.number = !isNan
                    out.append(number)
                }
                index = end
                afterMonth = false
                continue
            }
            let latin = japaneseCountedRomaji(value, counter: counter ?? "", afterMonth: afterMonth)
            out.append(JapaneseWord(raw: words[index..<counterEnd].map(\.raw).joined(), latin: latin, number: true))
            afterMonth = counter == "月"
            index = counterEnd
        }
        return out
    }

    static let japaneseDigitRomaji = ["", "ichi", "ni", "san", "yon", "go", "roku", "nana", "hachi", "kyuu"]

    /// 1~9999 를 읽는다.
    static func japaneseSectionRomaji(_ value: Int, group: Bool = false) -> String {
        let thousands = ["", "sen", "nisen", "sanzen", "yonsen", "gosen", "rokusen", "nanasen", "hassen", "kyuusen"]
        let hundreds = ["", "hyaku", "nihyaku", "sanbyaku", "yonhyaku", "gohyaku", "roppyaku", "nanahyaku", "happyaku", "kyuuhyaku"]
        let t = value / 1000, h = (value / 100) % 10, d = (value / 10) % 10, o = value % 10
        var out = ""
        if t > 0 { out += (group && t == 1) ? "issen" : thousands[t] }
        if h > 0 { out += hundreds[h] }
        if d > 0 { out += (d == 1 ? "" : japaneseDigitRomaji[d]) + "juu" }
        if o > 0 { out += japaneseDigitRomaji[o] }
        return out
    }

    /// 로마자 조각을 잇는다. ん 뒤에 모음·y 가 오면 `'` 로 갈라 ん 을 받침으로 둔다. (sen + en → sen'en)
    static func joinRomaji(_ parts: String...) -> String {
        parts.reduce("") { out, part in
            if out.hasSuffix("n"), let first = part.first, "aiueoy".contains(first) { return out + "'" + part }
            return out + part
        }
    }

    /// 숫자를 앞부분과 마지막 자리 조각으로 나눈다. 조수사는 마지막 조각의 소리만 바꾼다.
    static func japaneseNumberParts(_ value: Int) -> (head: String, last: String, unit: Int) {
        guard value > 0 else { return ("", "zero", 0) }
        // 1조 넘는 수는 자리마다 읽는다.
        guard value < 1_000_000_000_000 else {
            let digits = String(value).compactMap { $0.wholeNumberValue }
            return ("", digits.map { $0 == 0 ? "zero" : japaneseDigitRomaji[$0] }.joined(), 0)
        }
        var head = ""
        let oku = value / 100_000_000, man = (value / 10_000) % 10_000, rest = value % 10_000
        var parts: [(String, Int)] = []
        if oku > 0 { parts.append(((oku == 1 ? "ichi" : japaneseSectionRomaji(oku, group: true)) + "oku", 100_000_000)) }
        if man > 0 { parts.append(((man == 1 ? "ichi" : japaneseSectionRomaji(man, group: true)) + "man", 10_000)) }
        let t = rest / 1000, h = (rest / 100) % 10, d = (rest / 10) % 10, o = rest % 10
        if t > 0 { parts.append((japaneseSectionRomaji(t * 1000), 1000)) }
        if h > 0 { parts.append((japaneseSectionRomaji(h * 100), 100)) }
        if d > 0 { parts.append((japaneseSectionRomaji(d * 10), 10)) }
        if o > 0 { parts.append((japaneseDigitRomaji[o], 1)) }
        let last = parts.removeLast()
        head = parts.map(\.0).reduce("") { joinRomaji($0, $1) }
        return (head, last.0, last.1)
    }

    static func japaneseNumberRomaji(_ value: Int) -> String {
        let parts = japaneseNumberParts(value)
        return joinRomaji(parts.head, parts.last)
    }

    /// 숫자 + 조수사 읽기. 一本 ippon, 三本 sanbon, 六回 rokkai, 八歳 hassai, 四時 yoji, 七月 shichigatsu 처럼 소리가 바뀐다.
    static func japaneseCountedRomaji(_ value: Int?, counter: String, afterMonth: Bool) -> String {
        guard let spec = japaneseCounters[counter] else {
            return value.map(japaneseNumberRomaji) ?? "nan"
        }
        let forms = spec.reading.split(separator: "|").map(String.init)
        guard let value else {
            switch spec.sound {
            case .gemP: return joinRomaji("nan", forms[2])
            case .native: return "ikutsu"
            default: return joinRomaji("nan", counter == "階" ? "gai" : forms[0])
            }
        }
        switch (counter, value) {
        case ("人", 1): return "hitori"
        case ("人", 2): return "futari"
        case ("人目", 1): return "hitorime"
        case ("人目", 2): return "futarime"
        case ("歳", 20), ("才", 20): return "hatachi"
        default: break
        }
        if spec.sound == .native {
            let natives = ["hitotsu", "futatsu", "mittsu", "yottsu", "itsutsu", "muttsu", "nanatsu", "yattsu", "kokonotsu", "too"]
            return (1...10).contains(value) ? natives[value - 1] : japaneseNumberRomaji(value)
        }
        if spec.sound == .day {
            let tail = String(forms[0].dropFirst("nichi".count))
            let days: [Int: String] = [
                1: afterMonth ? "tsuitachi" : "ichinichi", 2: "futsuka", 3: "mikka", 4: "yokka", 5: "itsuka",
                6: "muika", 7: "nanoka", 8: "youka", 9: "kokonoka", 10: "tooka", 14: "juuyokka", 20: "hatsuka", 24: "nijuuyokka",
            ]
            if let day = days[value] { return day + tail }
        }
        let parts = japaneseNumberParts(value)
        let digit = parts.unit == 1 ? value % 10 : 0
        var last = parts.last
        switch spec.sound {
        case .gemK, .gemS, .gemP:
            let consonant = spec.sound == .gemK ? "k" : spec.sound == .gemS ? "s" : "p"
            let geminates = spec.sound == .gemS
                ? (parts.unit == 1 ? [1, 8].contains(digit) : parts.unit == 10)
                : (parts.unit == 1 ? [1, 6, 8].contains(digit) : [10, 100].contains(parts.unit))
            if geminates {
                // ichi→ik, roku→rok, hachi→hak, juu→juk, hyaku→hyak 에 뒤 자음을 겹친다
                if last.hasSuffix("chi") { last = String(last.dropLast(3)) + consonant }
                else if last.hasSuffix("ku") { last = String(last.dropLast(2)) + consonant }
                else if last.hasSuffix("uu") { last = String(last.dropLast(1)) + consonant }
                if spec.sound == .gemP { return joinRomaji(parts.head, last, forms[1]) }
                return joinRomaji(parts.head, last, forms[0])
            }
            if spec.sound == .gemP {
                let voiced = digit == 3 || parts.unit == 1000
                let plosive = counter.hasPrefix("分") && digit == 4
                return joinRomaji(parts.head, last, voiced ? forms[2] : plosive ? forms[1] : forms[0])
            }
            if counter == "階", digit == 3 { return joinRomaji(parts.head, last, "gai") }
            return joinRomaji(parts.head, last, forms[0])
        default:
            if parts.unit == 1 { last = japaneseDigitVariant(digit, counter: counter, fallback: last) }
            if spec.sound == .day, digit == 4 { return joinRomaji(parts.head, "yokka", String(forms[0].dropFirst("nichi".count))) }
            return joinRomaji(parts.head, last, forms[0])
        }
    }

    /// 四·七·九 는 조수사에 따라 よ·し·しち·く 로 읽는다.
    static func japaneseDigitVariant(_ digit: Int, counter: String, fallback: String) -> String {
        switch (digit, counter) {
        case (4, "時"), (4, "時間"), (4, "年"), (4, "年間"), (4, "年目"), (4, "人"), (4, "人目"), (4, "円"): return "yo"
        case (4, "月"): return "shi"
        case (7, "時"), (7, "時間"), (7, "月"), (7, "日"), (7, "日間"): return "shichi"
        case (9, "時"), (9, "時間"), (9, "月"), (9, "日"), (9, "日間"): return "ku"
        default: return fallback
        }
    }

    // MARK: - 로마자 → 한글

    /// 실제 노래 발음에 맞춰 カ·タ·チャ·ツ 행을 ㅋ·ㅌ·ㅊ·츠로 적고, 촉음은 ㅅ 받침, ん 은 ㄴ 받침으로 적는다.
    /// 장음은 오·우 단(おう·おお·うう·ー)만 줄이고, いい·ああ·ええ 는 두 음절로 둔다.
    static func romajiSyllables(_ raw: String, keepFinalU: Bool = false) -> (syllables: [Syl], leadingSokuon: Bool, trailingSokuon: Bool) {
        var text = raw.lowercased()
        let macron: [Character: Character] = ["ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o", "â": "a", "î": "i", "û": "u", "ê": "e", "ô": "o"]
        text = String(text.map { macron[$0] ?? $0 })
            .replacingOccurrences(of: "~tsu", with: "q")
            .replacingOccurrences(of: "~tu", with: "q")
        text = joinSmallKana(text)
        let parts = text.split(whereSeparator: { $0 == "'" || $0 == "’" })
        var syllables: [Syl] = []
        var leadingSokuon = false
        var trailingSokuon = false
        for (offset, part) in parts.enumerated() {
            let state = parseRomaji(String(part), into: &syllables, keepFinalU: keepFinalU && offset == parts.count - 1)
            if state.leadingSokuon { leadingSokuon = true }
            trailingSokuon = state.trailingSokuon
        }
        return (syllables, leadingSokuon, trailingSokuon)
    }

    /// 로마자 음절 머리 자음 묶음.
    static let romajiOnsets: Set<String> = [
        "k", "g", "s", "z", "t", "d", "n", "h", "b", "p", "m", "r", "y", "w", "v", "f", "j", "ch", "sh", "ts",
        "ky", "gy", "ny", "hy", "by", "py", "my", "ry", "dy", "ty", "fy", "vy", "dz", "dj", "kw", "gw",
    ]

    /// 작은 가나 표기 `~a`·`~yu` 를 앞 음절과 합친다. (vu~o→vo, u~i→wi, to~u→tu, de~yu→dyu, fu~a→fa, ne~e→nee)
    static func joinSmallKana(_ text: String) -> String {
        guard text.contains("~") else { return text }
        var out: [Character] = []
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard chars[index] == "~" else {
                out.append(chars[index])
                index += 1
                continue
            }
            var next = index + 1
            var glide = ""
            if next < chars.count, chars[next] == "y" || chars[next] == "w" {
                glide = String(chars[next])
                next += 1
            }
            guard next < chars.count, "aiueo".contains(chars[next]) else {
                index = next
                continue
            }
            let small = String(chars[next])
            index = next + 1
            guard let lastVowel = out.last, "aiueo".contains(lastVowel) else {
                out.append(contentsOf: glide + small)
                continue
            }
            var runStart = out.count - 1
            while runStart > 0, out[runStart - 1].isLetter, !"aiueoq".contains(out[runStart - 1]) { runStart -= 1 }
            let run = String(out[runStart..<(out.count - 1)])
            var consonant = ""
            for length in stride(from: min(2, run.count), through: 1, by: -1) where romajiOnsets.contains(String(run.suffix(length))) {
                consonant = String(run.suffix(length))
                break
            }
            let vowel = String(lastVowel)
            let merged: String
            if glide == "y" {
                merged = ["sh", "ch", "j"].contains(consonant) ? consonant + small : consonant + "y" + small
            } else if glide == "w" {
                merged = consonant + "w" + small
            } else if vowel == small {
                merged = consonant + vowel + small
            } else if consonant.isEmpty {
                merged = vowel == "u" ? "w" + small : vowel == "i" && small == "e" ? "ye" : vowel + small
            } else if ["v", "f", "ts"].contains(consonant) {
                merged = consonant + small
            } else if ["t", "d"].contains(consonant), vowel == "o" || vowel == "e" {
                merged = consonant + small
            } else if ["k", "g"].contains(consonant), vowel == "u" {
                merged = consonant + "w" + small
            } else if ["s", "z"].contains(consonant), vowel == "u", small == "i" {
                merged = consonant + small
            } else if ["sh", "ch", "j"].contains(consonant), vowel == "i", small == "e" {
                merged = consonant + small
            } else {
                merged = consonant + vowel + small
            }
            out.removeLast(consonant.count + 1)
            out.append(contentsOf: merged)
        }
        return String(out)
    }

    struct Syl {
        var cho: Int
        var jung: Int
        var jong: Int = 0
        var raw: String? = nil
        var text: String { raw ?? HangulReading.syllable(cho, jung, jong) }
    }

    static func parseRomaji(_ raw: String, into syllables: inout [Syl], keepFinalU: Bool = false) -> (leadingSokuon: Bool, trailingSokuon: Bool) {
        let collapsed = collapseJapaneseLongVowels(raw.filter { $0.isLetter }, keepFinalU: keepFinalU)
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
                if syllables.isEmpty || syllables[syllables.count - 1].jong != 0 {
                    syllables.append(Syl(cho: 11, jung: 18, jong: 4))
                } else {
                    syllables[syllables.count - 1].jong = 4
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
        "kgstdnhbpmrjcfywzv".contains(char)
    }

    /// 오·우 단 장음(ou·oo·uu)만 한 음절로 줄인다. `keepFinalU` 면 끝의 う 는 그대로 둔다(思う).
    static func collapseJapaneseLongVowels(_ text: String, keepFinalU: Bool = false) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        while index < chars.count {
            if index + 1 < chars.count {
                let pair = String(chars[index...index + 1])
                let finalU = keepFinalU && index + 2 == chars.count && chars[index + 1] == "u"
                if (pair == "ou" || pair == "oo" || pair == "uu"), !finalU {
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
            ("py", 17), ("my", 6), ("ry", 5), ("dy", 3), ("ty", 16), ("fy", 17), ("vy", 7),
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
        map["dzu"] = (12, 18)
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
        map["tsa"] = (14, 0)
        map["tsi"] = (14, 20)
        map["tse"] = (14, 5)
        map["tso"] = (14, 8)
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
        map["dji"] = (12, 20)
        map["zi"] = (12, 20)
        map["di"] = (3, 20)
        map["ja"] = (12, 0)
        map["ju"] = (12, 13)
        map["jo"] = (12, 8)
        map["je"] = (12, 5)
        map["dja"] = (12, 0)
        map["dju"] = (12, 13)
        map["djo"] = (12, 8)
        map["wa"] = (11, 9)
        map["wo"] = (11, 14)
        map["wi"] = (11, 16)
        map["we"] = (11, 15)
        map["kwa"] = (15, 9)
        map["kwi"] = (15, 16)
        map["kwe"] = (15, 15)
        map["kwo"] = (15, 14)
        map["gwa"] = (0, 9)
        map["gwi"] = (0, 16)
        map["gwe"] = (0, 15)
        map["gwo"] = (0, 14)
        return map
    }()
}
