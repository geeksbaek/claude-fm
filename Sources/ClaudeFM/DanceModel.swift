import Foundation

/// 대역 에너지와 박 간격으로 나눈 분위기. 소리가 없으면 `quiet`.
enum MusicMood: Equatable {
    case quiet, calm, groove, bass, bright, drive

    var label: String? {
        switch self {
        case .quiet: return nil
        case .calm: return "잔잔"
        case .groove: return "리듬"
        case .bass: return "저음"
        case .bright: return "밝음"
        case .drive: return "빠름"
        }
    }

    /// 일시정지일 때 팝오버에 보여주는 문장.
    var caption: String? {
        switch self {
        case .quiet: return nil
        case .calm: return "잔잔한 박에 살랑이는 중"
        case .groove: return "리듬에 맞춰 춤추는 중"
        case .bass: return "저음에 맞춰 울리는 중"
        case .bright: return "밝은 소리에 반짝이는 중"
        case .drive: return "빠른 박에 들썩이는 중"
        }
    }
}

/// 시간이 지날수록 해금·순환되는 클로드의 춤 동작.
enum DanceStyle: Int, Equatable, CaseIterable {
    case bounce = 0     // 기본 리듬 바운스
    case handsUp = 1    // 양팔 만세 / 핸즈업 펌핑
    case waveTilt = 2   // 상하체 웨이브 & 엇박 팔 흔들기
    case moonwalk = 3   // 문워크 글라이드 스텝
    case spinJump = 4   // 클라이맥스 스타 점프 & 턴
    case discoFever = 5 // 미러볼 디스코 피버 포즈
}

/// 박자에 맞춘 춤. `hop` 은 박 직후 1에서 0으로 떨어진다.
struct DancePose: Equatable {
    enum Bounce: Equatable {
        case rest, air, land
    }

    var active = false
    var hop = 0.0
    /// true 면 오른쪽으로 한 걸음 옮겨 선다.
    var stepRight = false
    var mood = MusicMood.quiet
    var style = DanceStyle.bounce
    var danceTime = 0.0

    static let idle = DancePose()

    /// 박이 있거나, 소리는 나는데 박이 없어 분위기만 남은 상태.
    var showsMotion: Bool { active || mood != .quiet }

    /// 미러볼 조명이 켜지는 상태인지.
    var hasMirrorball: Bool {
        (active && (danceTime >= 3.0 || style != .bounce)) || mood == .bright || mood == .drive
    }

    /// 1칸짜리 스프라이트에서 구분되는 점프의 단계. 분위기에 따라 뜨고 눌리는 길이가 다르다.
    var bounce: Bounce {
        guard active else { return .rest }
        switch mood {
        case .calm:
            return hop > 0.8 ? .air : .rest
        case .bass:
            if hop > 0.5 { return .air }
            if hop > 0.15 { return .land }
            return .rest
        case .drive:
            if hop > 0.45 { return .air }
            if hop > 0.15 { return .land }
            return .rest
        default:
            if hop > 0.55 { return .air }
            if hop > 0.22 { return .land }
            return .rest
        }
    }
}

/// 가사에서 온 메뉴바 Clawd 의 몸짓. 부르는 줄의 반응 그림과 후렴 여부.
struct SpriteAccent: Equatable {
    var reaction: LyricReaction?
    var hook = false

    static let none = SpriteAccent()
}

/// 메뉴바와 팝오버, 무대가 같은 박자로 움직이도록 시각에서 프레임을 계산한다.
enum Animation {
    static let frameInterval: TimeInterval = 0.15
    /// 점프가 한 박 안에 끝나므로 메뉴바와 팝오버를 이 간격으로 다시 그린다.
    static let danceInterval: TimeInterval = 1.0 / 30

    static func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameInterval) % ClawdPixels.frameCount
    }
}
