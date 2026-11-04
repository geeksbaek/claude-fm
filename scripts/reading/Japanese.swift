// 일본어 읽기 예문.
import Foundation

let japaneseCases: [ReadingCase] = [
]

let japaneseProbes: [String] = {
    #if os(macOS)
    readingDump(japaneseCorpus, japanese: true)
    #endif
    return []
}()

/// 낱말 나누기를 살펴보는 예문.
let japaneseCorpus: [String] = [
    "君の名は", "夜に駆ける", "私は明日も君に会いたい", "ありがとう", "さよならの夏", "心から愛してる",
    "あの日見た花の名前を僕達はまだ知らない", "ずっと一緒にいたい", "大丈夫だよ", "抱きしめたい", "残酷な天使のテーゼ",
    "東京", "笑顔", "運命", "風になる",
    "今日も君を想ってる", "一人じゃないよ", "二人で歩いた道", "大人になったら", "何度でも", "何もいらない", "何を言っても",
    "世界の果てまで", "運命の赤い糸", "約束だよ", "奇跡を信じて", "恋をしたんだ", "愛してるって言って", "涙が止まらない",
    "未来へ向かって", "永遠に続く", "明日へ", "昨日の夢", "今夜は眠れない", "星空の下で", "青空に手を伸ばして",
    "桜の花が散る頃", "春の風", "夏の終わり", "秋の空", "冬の星座", "君がいない世界なんて", "僕らはきっと",
    "好きだよ", "大好きなんだ", "会いたくて会いたくて", "忘れないで", "離さないで", "そばにいて", "もう一度",
    "待ってるよ", "行こうよ", "帰ろう", "歌おう", "笑って", "泣かないで", "泣いちゃう", "消えてしまいそうな",
    "届けたい", "思い出す", "思うよ", "言えなかった", "走り出す", "生きていく", "信じてる", "輝いてる",
    "知らないふり", "分からないよ", "綺麗だね", "優しい声", "悲しい歌", "嬉しい", "寂しい夜", "楽しい時間",
    "新しい朝", "美しい世界", "眩しい光", "苦しいほど", "懐かしい匂い", "恥ずかしい", "いいよ", "かわいい",
    "欲しい", "小さな手", "大きな夢", "遠い空", "近くにいて",
    "ハッピーエンド", "メロディー", "ストーリー", "パーティー", "ドリーム", "ラブソング", "キスして", "ダンス",
    "スター", "ハート", "メモリー", "ファンタジー", "ヴォーカル", "ウィンター", "フェイク", "ジェラシー", "チェリー",
    "ディスコ", "トゥモロー", "デュエット", "ティアラ", "フォーエバー", "ミュージック", "ビューティフル",
    "クリスマス", "プレゼント", "グッバイ", "ベイビー", "レディー", "ガール", "ボーイ", "ロックンロール",
    "ステージ", "ライブ", "スマイル", "ワンダフル", "ウォーク", "シェイク", "ファイト", "ヴィーナス", "チューリップ",
    "ジャンプ", "カフェ", "ウェディング", "ツイン", "シャツ", "ピアノ", "ギター", "マイク", "ゲーム", "ドア",
    "ニュース", "コンピューター", "エレベーター",
    "ティ", "ディ", "トゥ", "ドゥ", "デュ", "テュ", "ファ", "フィ", "フェ", "フォ", "フュ", "ヴァ", "ヴィ", "ヴ",
    "ヴェ", "ヴォ", "ウィ", "ウェ", "ウォ", "シェ", "ジェ", "チェ", "ツァ", "ツィ", "ツェ", "ツォ", "イェ",
    "クァ", "グァ", "スィ", "ズィ", "キェ", "ニェ", "ヂ", "ヅ", "ヲ", "ゐ", "ゑ", "ゔ", "ゎ", "ヵ", "ヶ",
    "はなぢ", "つづく", "きづく", "ちぢむ", "いずれ", "わぁ", "きゃー", "すごーい", "ねぇ", "あぁ",
    "一緒に", "一生", "一瞬", "一番", "一度だけ", "一つになる", "二度と", "三日月", "百年", "千年",
    "今", "今日", "明日", "昨日", "毎日", "今年", "本当に", "本気で", "素敵な", "幸せ", "大切な人", "大事なもの",
    "気持ち", "言葉", "願い事", "想い", "思い出", "花火", "夕焼け", "故郷", "物語", "季節", "景色", "瞳", "翼",
    "宇宙", "太陽", "月", "雨", "雪", "海", "光", "影", "声", "手", "胸", "心臓", "唇", "指", "髪",
    "君", "僕", "俺", "あなた", "貴方", "彼", "彼女", "誰", "何処", "何故", "人", "人々", "時々", "日々", "色々",
    "少年", "少女", "先生", "学校", "友達", "家族", "恋人", "天使", "悪魔", "神様", "王子様", "お姫様",
    "魔法", "秘密", "自由", "勇気", "希望", "孤独", "絶望", "情熱", "衝動", "本能", "感情", "記憶", "時間", "瞬間",
    "永遠", "現実", "理想", "真実", "嘘", "本音", "未来", "過去", "青春", "恋愛", "原因", "今夜", "千円",
    "簡単", "案内", "散歩", "新聞", "天気", "先輩", "三枚", "銀河", "金曜日", "日曜日", "雨上がり", "夜明け",
    "真夜中", "真っ白", "真っ赤", "真っ直ぐ", "一日中", "世界中",
    "君だけ", "僕だけの", "君しかいない", "君のことが好き", "会いに行くよ", "迎えに来て", "見つけた", "見つめて",
    "探してる", "待ってて", "届かない", "叶えたい", "守りたい", "変わらない", "終わらない", "止まらない",
    "戻れない", "帰れない", "逃げないで", "負けないで", "諦めないで", "頑張って", "振り向いて", "抱きしめて",
    "触れたい", "感じてる", "響いてる", "揺れてる", "溢れ出す", "舞い上がれ", "飛び立とう", "踊ろう", "叫ぼう",
    "歩こう", "進もう", "始めよう", "終わりにしよう", "続く", "気づく", "近づく", "傷つく", "築く", "続けよう",
    "思う", "迷う", "誘う", "漂う", "揃う", "拾う", "救う", "狂う", "歌う", "笑う", "違う", "願う", "言う",
    "会おう", "言おう", "行こう", "しよう", "そう", "どう", "もう", "こう", "ああ", "ねえ", "おお", "いい",
    "遠い", "多い", "大きい", "通り", "氷", "お母さん", "お父さん", "お兄ちゃん", "お姉さん", "おばあちゃん",
    "東京タワー", "渋谷", "新宿", "大阪", "北海道", "日本", "富士山", "夏祭り", "花火大会",
    "恋をしよう", "君に恋してる", "愛し合おう", "愛を叫べ", "夢を見ていた", "夢を追いかけて", "空を飛びたい",
    "雨が降ってる", "風が吹いてる", "星が光る", "月が綺麗ですね", "ありがとうございます", "ごめんなさい",
    "さようなら", "おはよう", "おやすみ", "いただきます", "大丈夫", "もしもし", "よろしくね", "頑張れ",
    "行ってきます", "ただいま", "おかえり", "いってらっしゃい", "何でもない", "何となく", "何もかも", "何回も",
    "何時も", "いつも", "いつか", "いつまでも", "どこまでも", "どこにもない", "誰もいない", "誰かのために",
    "君のために", "僕のせいで", "君のおかげで", "好きになっちゃった", "忘れちゃった", "言っちゃった",
    "来ちゃった", "しちゃおう", "やっちゃえ", "待ってたんだ", "知ってるよ", "分かってる", "思ってた",
    "言ってたじゃん", "だって", "だから", "でも", "けど", "それでも", "それなのに", "もしも", "きっと",
    "やっぱり", "ちょっと", "もっと", "ずっと", "さっき", "あっという間", "待って", "行った", "買った",
    "切ない", "儚い", "愛しい", "恋しい", "夢見る", "少しずつ", "ゆっくり", "はっきり", "しっかり", "びっくり",
    "ドキドキ", "ワクワク", "キラキラ", "ふわふわ", "ギュッと", "ぎゅっと", "そっと", "ほっと", "パッと", "ハッと",
    "えっ", "あっ", "よっ", "はっ", "かっこいい", "やばい", "マジで", "超かわいい", "未完成", "非日常", "最高",
    "最後", "最初", "最強", "大嫌い", "小さい", "高い空", "新世界", "全世界", "不思議", "無理", "再会", "真っ暗",
    "東京の空", "二人の未来", "一人ぼっち", "君と僕", "僕と君の", "恋の歌", "愛の歌", "夜の街", "朝の光",
    "僕たち", "私たち", "君たち", "僕ら", "子供たち", "友達と", "君さえいれば", "君こそが", "一緒なら",
    "春が来る", "夏が来た", "冬が終わる", "時が経つ", "時を超えて", "時計の針", "心の中で", "心の奥", "胸の奥",
    "夢の中", "闇の中", "光の中へ", "君の声が聞こえる", "聞かせて", "教えて", "見せて", "連れて行って",
    "行かないで", "来ないで", "見ないで", "しないで",
    "君と出会えた奇跡を信じてる", "今すぐ会いに行くよ", "このまま時が止まればいいのに", "何度でも立ち上がるんだ",
    "君の笑顔が見たいから", "夢の続きを見せてよ", "涙の数だけ強くなれる", "夜空に輝く星のように",
    "言葉にできない想いを", "もう二度と離さない", "ずっとずっと好きだった", "あなたのことを忘れない",
    "いつかまた会える日まで", "僕らは今を生きている", "君がいれば何もいらない", "風が吹いたら思い出して",
    "二人だけの秘密だよ", "明日はきっといい日になる", "どんな時も君のそばにいる", "愛してるなんて言えないよ",
    "君のことばかり考えてる", "叶わない恋だとしても", "さよならなんて言わないで", "心臓がドキドキしてる",
    "胸の奥が痛くなる", "誰にも言えない秘密", "どうしてこんなに好きなんだろう", "笑っていてほしい",
    "抱きしめてほしいの", "早く会いたいな", "一緒に帰ろうよ", "手をつないで歩こう", "君の声が聞きたい",
    "思い出に変わる前に", "悲しみを越えて", "光を探して走り続ける", "未来はまだ見えないけど", "世界が終わるまで",
    "運命なんて信じない", "約束の場所で待ってる", "君に届け", "花のように咲いて", "雨上がりの空に虹がかかる",
    "桜舞い散る季節に", "夏の夜に花火を見た", "時間よ止まれ", "愛をください", "もっと強くなりたい",
    "このままでいいの", "どこへ行けばいい", "教えてよ", "君は僕の太陽だ", "僕は君の味方だよ",
    "本当の気持ちを伝えたい", "大切なものは目に見えない", "自由に生きたい", "勇気を出して", "孤独な夜を越えて",
    "永遠に君を愛す", "夢見る少女じゃいられない", "ハッピーバースデー", "メリークリスマス", "君とのラブストーリー",
    "ダンスしよう", "キラキラ光る", "ドキドキが止まらない", "好きだよね", "行くぜ", "負けないぞ", "そうだね",
    "だよな", "かな", "かしら", "のね", "わよ", "じゃん", "でしょ", "だろう", "ですか", "ますよ", "ましょう",
    "ません", "ました", "でした", "見ている", "見てる", "来てくれた", "してあげる", "してほしい", "食べたい",
    "飲みたい", "行きたい", "見たい", "したい", "会える", "会えない", "会わない", "会った", "会って",
    "愛されたい", "愛せない", "愛した", "恋した", "恋して", "勉強して", "電話して", "連絡して", "約束して",
    "1人で", "2人の", "3つの願い", "100年後も", "24時間ずっと", "1999年の夏", "7月7日", "3月9日",
    "1000年先も", "10年後", "5分だけ", "1秒でも", "2度目の春", "100万回", "1番星", "1回だけ", "8月の空",
    "12時の鐘", "4時の約束", "9時に", "6月の雨", "1日中", "20歳の夏", "1つだけ", "2つの心", "3人で", "4人",
]

#if os(macOS)
import NaturalLanguage

/// CI 기록에서 macOS 낱말 나누기·병음·언어 알아보기를 그대로 다시 쓰려고 남기는 기록.
struct ReadingDumpRow: Encodable {
    var t: String
    var p: String
    var n: String
    var k: [[[String]]]
    var r: [[[String]]]
    var z: [[String]]
    var j: Bool
    var d: String
    var h: [String: Double]
}

func readingRuns(_ text: String) -> [String] {
    var runs: [String] = []
    var current = ""
    for char in text {
        if HangulReading.isKana(char) || HangulReading.isHan(char) || char == "々" {
            current.append(char)
        } else if !current.isEmpty {
            runs.append(current)
            current = ""
        }
    }
    if !current.isEmpty { runs.append(current) }
    return runs
}

func readingDump(_ lines: [String], japanese: Bool) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    var chars = Set<Character>()
    for text in lines {
        let normalized = HangulReading.normalizeWidth(text)
        let runs = readingRuns(normalized)
        var replaced: [String] = []
        for run in runs {
            var prepared = run
            for (target, kana) in HangulReading.japaneseReadingReplacements {
                prepared = prepared.replacingOccurrences(of: target, with: kana)
            }
            if prepared != run { replaced.append(prepared) }
        }
        let expanded = HangulReading.expandNumbers(in: normalized, hanIsJapanese: japanese, preferJapanese: japanese)
        let expandedRuns = readingRuns(expanded).filter { !runs.contains($0) }
        var extra: [String] = []
        for run in expandedRuns {
            var prepared = run
            for (target, kana) in HangulReading.japaneseReadingReplacements {
                prepared = prepared.replacingOccurrences(of: target, with: kana)
            }
            extra.append(run)
            if prepared != run { extra.append(prepared) }
        }
        for char in normalized where HangulReading.isHan(char) { chars.insert(char) }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese]
        let sample = String(normalized.filter { HangulReading.isHan($0) || HangulReading.isKana($0) })
        recognizer.processString(sample.isEmpty ? normalized : sample)
        var hypotheses: [String: Double] = [:]
        for (language, value) in recognizer.languageHypotheses(withMaximum: 3) {
            hypotheses[language.rawValue] = (value * 1000).rounded() / 1000
        }
        let row = ReadingDumpRow(
            t: text,
            p: HangulReading.line(text, preferJapanese: true),
            n: HangulReading.line(text),
            k: (runs + extra).map { run in HangulReading.japaneseTokens(run).map { [$0.raw, $0.latin] } },
            r: replaced.map { run in HangulReading.japaneseTokens(run).map { [$0.raw, $0.latin] } },
            z: (runs + expandedRuns).map { HangulReading.mandarinTokens($0) },
            j: HangulReading.soundsJapanese(normalized),
            d: NLLanguageRecognizer.dominantLanguage(for: sample.isEmpty ? normalized : sample)?.rawValue ?? "-",
            h: hypotheses
        )
        if let data = try? encoder.encode(row), let json = String(data: data, encoding: .utf8) {
            print("@@D " + json)
        }
    }
    var single: [String: [String]] = [:]
    for char in chars.sorted() {
        single[String(char)] = HangulReading.mandarinTokens(String(char))
    }
    var singleJa: [String: [[String]]] = [:]
    for char in chars.sorted() {
        singleJa[String(char)] = HangulReading.japaneseTokens(String(char)).map { [$0.raw, $0.latin] }
    }
    if let data = try? encoder.encode(single), let json = String(data: data, encoding: .utf8) {
        print("@@C " + json)
    }
    if let data = try? encoder.encode(singleJa), let json = String(data: data, encoding: .utf8) {
        print("@@K " + json)
    }
}
#endif
