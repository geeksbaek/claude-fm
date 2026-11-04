import Foundation

// 한국어 발음 읽기 검사. 예문마다 기대하는 읽기와 견준다.
// 갈래마다 파일 하나에 예문(`…Cases`)과 기대값 없이 결과만 보는 줄(`…Probes`)을 둔다.

/// 예문 하나. `japanese` 는 가나가 있는 곡 안의 한자 줄처럼 일본어로 읽어야 하는 줄이다.
struct ReadingCase {
    let text: String
    let expected: String
    let japanese: Bool

    init(_ text: String, _ expected: String, japanese: Bool = false) {
        self.text = text
        self.expected = expected
        self.japanese = japanese
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    for text in arguments {
        print("\(text) → \(HangulReading.line(text))")
    }
    exit(0)
}

let suites: [(name: String, cases: [ReadingCase])] = [
    ("영어", englishCases),
    ("일본어", japaneseCases),
    ("중국어", chineseCases),
    ("숫자·섞인 줄", mixedCases),
]
var failed = 0
var total = 0
for suite in suites {
    var missed = 0
    for item in suite.cases {
        total += 1
        let got = HangulReading.line(item.text, preferJapanese: item.japanese)
        guard got != item.expected else { continue }
        missed += 1
        print("✗ \(suite.name)  \(item.text)\n    기대  \(item.expected)\n    결과  \(got)")
    }
    failed += missed
    print("\(suite.name) \(suite.cases.count - missed)/\(suite.cases.count)")
}

let probes = englishProbes + japaneseProbes + chineseProbes + mixedProbes
if !probes.isEmpty {
    print("살펴보기")
    for text in probes {
        print("  \(text) → \(HangulReading.line(text))")
    }
}
print(failed == 0 ? "읽기 예문 \(total)개 모두 통과" : "읽기 예문 \(total)개 중 \(failed)개 틀림")
exit(failed == 0 ? 0 : 1)
