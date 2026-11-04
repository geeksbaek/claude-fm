import Foundation
import NaturalLanguage

/// 운영체제에 맡기는 읽기: 일본어 낱말 나누기와 로마자 읽기, 중국어 병음, 언어 알아보기.
/// 나머지 규칙은 운영체제와 상관없이 돌아서, 검사 도구는 이 파일 대신 표로 흉내 낸 대역을 넣을 수 있다.
extension HangulReading {
    /// 일본어 낱말 하나와 그 로마자 읽기.
    struct Token: Equatable {
        var raw: String
        var latin: String
    }

    /// 일본어 문장을 낱말로 나누고 낱말마다 로마자 읽기를 붙인다.
    static func japaneseTokens(_ text: String) -> [Token] {
        let source = text as CFString
        let full = CFRange(location: 0, length: CFStringGetLength(source))
        let locale = Locale(identifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(nil, source, full, kCFStringTokenizerUnitWord, locale)
        var tokens: [Token] = []
        while true {
            let type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            if type.rawValue == 0 { break }
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let latin = (CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            tokens.append(Token(raw: substring(source, range), latin: latin))
        }
        return tokens
    }

    /// 중국어 낱말마다 성조 부호가 붙은 병음.
    static func mandarinTokens(_ text: String) -> [String] {
        transcribe(text, locale: "zh-Hans")
    }

    /// 가나 없이 한자만 있는 줄이 일본어로 들리는지.
    static func recognizesJapanese(_ sample: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage == .japanese
    }

    private static func substring(_ source: CFString, _ range: CFRange) -> String {
        let length = CFStringGetLength(source)
        guard range.location >= 0, range.length > 0, range.location + range.length <= length,
              let part = CFStringCreateWithSubstring(nil, source, range) else { return "" }
        return part as String
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
