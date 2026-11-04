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
        rule(.snow, #"눈이\s?(?:내려|내리|내린|와요|와서|오네|오면|온다|와\b|와$)|눈\s?내리|눈송이|첫눈|함박눈|눈꽃|눈사람|겨울|\b(?:snow\w*|winter|frozen|freez\w*)\b|雪|(?<![越])冬"#),
        rule(.fire, #"불꽃|불타|불길(?!한)|불처럼|불이\s?붙|불을\s?붙|불태|타오르|타올라|뜨거|열정|\b(?:fire|fires|firework\w*|burn\w*|flames?|blaz\w*|ignite\w*|lit|hot|heat)\b|花火|火(?!曜)|炎|燃|熱|烧|ファイア"#),
        rule(.love, #"사랑|좋아해|좋아했|하트|심장|두근|설레|키스|입맞|\b(?:lov(?:e|es|ed|ing|er|ers|ely)|heart\w*|kiss\w*|darling|sweetheart)\b|愛|爱|恋|好き|スキ|ハート|キス|(?<!ク)ラブ|ドキドキ|どきどき|喜欢|心动|心跳|真心|恋心|心臓|我的心|你的心"#),
        rule(.star, #"(?<![이특개차구분작결송성식])별(?:빛|들|자리|처럼|이|을|만|과|에|의|님|똥)|샛별|반짝|은하|빛나|\b(?:\w*star(?:s|light|dust|ry)?|shin(?:e|es|ing)|sparkl\w*|twinkl\w*|glitter\w*|galax\w*)\b|星|輝|煌|キラキラ|きらきら|スター|闪|耀"#),
        rule(.tears, #"눈물|(?<!기)울어|울고|울지|울었|울음|(?<![준나로경소예대장무])비가|빗물|빗소리|빗속|빗방울|비\s?내리|비처럼|소나기|장마|\b(?:tears?|cry|cries|crying|cried|rain(?:s|y|ing|ed|drops?)?|weep\w*)\b|涙|泣|雨|なみだ|泪|哭"#),
        rule(.moon, #"달빛|달님|보름달|초승달|반달|달이\s?뜨|달\s?아래|달처럼|밤하늘|한밤|\b(?:moon\w*|midnight)\b|(?<![岁歲今毎来先])月(?!曜)|夜空|真夜中|ムーン|午夜"#),
        rule(.flower, #"(?<!불|눈)꽃|장미|피어나|\b(?:flowers?|bloom\w*|blossom\w*|roses?|petals?|daisy|daisies)\b|花|咲|桜|さくら|サクラ|薔薇|バラ|玫瑰|樱"#),
        rule(.sun, #"햇살|햇빛|햇볕|태양|해가\s?뜨|해처럼|눈부시|눈부신|눈부셔|\b(?:sun|suns|sunny|sunshine|sunlight|sunrise|sunset|summer)\b|太陽|太阳|陽|阳光|日差し|ひざし|夏"#),
    ]
}
