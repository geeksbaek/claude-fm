import AppKit

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

/// 헤드폰을 쓴 Clawd 픽셀 스프라이트. 한 칸이 1pt 이고 y 는 위에서 아래로 증가한다.
/// 몸은 Claude Code 로고(▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝)를 정사각 픽셀로 푼 비율을 따른다:
/// 몸통 12×8, 1×2 눈, 양옆 2칸 팔, 2칸 다리 4개.
enum ClawdSprite {
    static let canvas = NSSize(width: 24, height: 14)
    static let frameCount = 96

    private static let palette: [Character: NSColor] = [
        "O": NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1), // 몸통 #D97757
        "H": NSColor(srgbRed: 0.784, green: 0.588, blue: 0.290, alpha: 1), // 헤드밴드 #C8964A
        "C": NSColor(srgbRed: 0.420, green: 0.259, blue: 0.149, alpha: 1), // 이어컵 #6B4226
        "c": NSColor(srgbRed: 0.627, green: 0.439, blue: 0.235, alpha: 1), // 이어컵 쿠션 #A0703C
    ]
    private static let eyeColor = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.075, alpha: 1)
    private static let headFlash = NSColor(srgbRed: 0.98, green: 0.84, blue: 0.42, alpha: 1)
    private static let sparkle = NSColor(srgbRed: 1, green: 0.84, blue: 0.20, alpha: 1)
    private static let thump = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.28, alpha: 1)
    private static let discoColors: [NSColor] = [
        NSColor(srgbRed: 0.36, green: 0.92, blue: 0.98, alpha: 1), // 네온 시안
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.82, alpha: 1), // 마젠타 핑크
        NSColor(srgbRed: 1.00, green: 0.88, blue: 0.28, alpha: 1), // 미러볼 골드
        NSColor(srgbRed: 0.72, green: 0.54, blue: 1.00, alpha: 1), // 네온 바이올렛
        NSColor(srgbRed: 0.42, green: 0.96, blue: 0.68, alpha: 1), // 민트 그린
    ]
    private static let mirrorSilver = NSColor(srgbRed: 0.92, green: 0.95, blue: 1.0, alpha: 1)
    private static let mirrorCord = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.74, alpha: 0.85)

    /// 양팔(col 0..1, 14..15)을 분리해 안무마다 팔 높이와 각도를 다르게 그린다.
    private static let coreBody: [String] = [
        "....HHHHHHHH....",
        "..HH........HH..",
        ".CCOOOOOOOOOOCC.",
        ".CcOOOOOOOOOOcC.",
        ".CcOOOOOOOOOOcC.",
        ".CCOOOOOOOOOOCC.",
        "..OOOOOOOOOOOO..",
        "..OOOOOOOOOOOO..",
        "..OOOOOOOOOOOO..",
        "..OOOOOOOOOOOO..",
    ]
    private static let openEyes = [(4, 4), (4, 5), (11, 4), (11, 5)]
    private static let closedEyes = [(4, 5), (5, 5), (10, 5), (11, 5)]
    private static let happyEyes = [(4, 4), (5, 5), (10, 5), (11, 4)]
    /// 잔잔할 때 반쯤 감은 눈. 한 칸짜리 가로선.
    private static let softEyes = [(4, 5), (11, 5)]
    private static let legColumns = [3, 5, 10, 12]
    private static let wideLegColumns = [2, 5, 10, 13]
    private static let topMargin = 1

    private static let notes: [[String]] = [
        [".NN.",
         ".N.N",
         ".N..",
         "NN..",
         "NN.."],
        [".NNNN",
         ".N..N",
         ".N..N",
         "NN.NN",
         "NN.NN"],
    ]
    private static let noteLeft = 18
    private static let noteDrift = [0, 0, 1, 1, 1, 1, 0, 0]

    /// 메뉴바용 이미지. 음표 색은 그릴 때의 외관(라이트/다크)을 따른다.
    static func image(frame: Int, playing: Bool, dance: DancePose = .idle, scale: CGFloat = 1) -> NSImage {
        let size = NSSize(width: canvas.width * scale, height: canvas.height * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(frame: frame, playing: playing, dance: dance, scale: scale, origin: .zero, noteColor: .labelColor)
            return true
        }
        image.accessibilityDescription = "Claude FM"
        return image
    }

    /// 뒤집힌(flipped) 좌표계에서 스프라이트를 그린다.
    static func draw(frame: Int, playing: Bool, dance: DancePose = .idle, scale: CGFloat, origin: CGPoint, noteColor: NSColor) {
        func pixel(_ x: Int, _ y: Int, _ color: NSColor) {
            guard x >= 0, y >= 0, x < Int(canvas.width), y < Int(canvas.height) else { return }
            let x0 = (origin.x + CGFloat(x) * scale).rounded(), x1 = (origin.x + CGFloat(x + 1) * scale).rounded()
            let y0 = (origin.y + CGFloat(y) * scale).rounded(), y1 = (origin.y + CGFloat(y + 1) * scale).rounded()
            color.setFill()
            NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).fill()
        }

        let dancing = dance.active
        let mood = dance.mood
        let style: DanceStyle = dancing
            ? dance.style
            : (playing ? DanceStyle(rawValue: (frame / 16) % DanceStyle.allCases.count) ?? .bounce : .bounce)
        let showDisco = dance.hasMirrorball || (playing && style != .bounce)
        let airborne = dance.bounce == .air
        let landing = dance.bounce == .land
        let bob = !dancing && playing && frame % 4 >= 2 && mood != .drive
        let top = topMargin + (airborne ? -1 : (bob || landing) ? 1 : 0)

        let xOff: Int
        if dancing || playing {
            switch style {
            case .moonwalk:
                let cycle = [0, 1, 2, 1]
                xOff = cycle[(frame / 2) % cycle.count]
            case .waveTilt:
                xOff = (frame / 2) % 2 == 0 ? 0 : 2
            default:
                if dancing {
                    switch mood {
                    case .calm:
                        xOff = (frame / 2) % 4 < 2 ? 0 : 1
                    case .drive:
                        xOff = (dance.stepRight ? 1 : 0) + (airborne ? 1 : 0)
                    default:
                        xOff = dance.stepRight ? 2 : 0
                    }
                } else {
                    xOff = (frame / 4) % 2 == 0 ? 0 : 1
                }
            }
        } else if mood == .drive && frame % 2 == 0 {
            xOff = 1
        } else {
            xOff = 0
        }

        // 미러볼 조명 효과: 천장에 매달린 미러볼과 사방으로 퍼지는 반짝이 스포트라이트
        if showDisco {
            drawMirrorballAndLights(frame: frame, xOff: xOff, airborne: airborne, pixel: pixel)
        }

        // 웨이브나 턴 동작에서는 상체(머리·헤드폰)가 1칸 좌우로 리듬감 있게 기울어진다.
        let headShift: Int
        switch style {
        case .waveTilt:
            headShift = (frame % 4 < 2) ? 1 : -1
        case .spinJump where airborne || frame % 4 == 1:
            headShift = dance.stepRight ? 1 : -1
        default:
            headShift = 0
        }

        let flashHead = (mood == .drive && (airborne || frame % 4 == 0)) || (showDisco && frame % 3 == 0)
        let discoTint = discoColors[frame % discoColors.count]
        for (row, line) in coreBody.enumerated() {
            let rowShift = (row <= 4) ? max(0, min(2, xOff + headShift)) : xOff
            for (col, ch) in line.enumerated() {
                let color: NSColor?
                if ch == "H", flashHead {
                    color = showDisco ? discoTint : headFlash
                } else if ch == "c", showDisco, (col + frame) % 3 == 0 {
                    color = discoColors[(frame + 2) % discoColors.count]
                } else {
                    color = palette[ch]
                }
                if let color { pixel(col + rowShift, top + row, color) }
            }
        }

        // 안무(DanceStyle)에 따른 양팔 동작 그리기
        let bodyColor = palette["O"]!
        drawArms(style: style, frame: frame, xOff: xOff, top: top, airborne: airborne, stepRight: dance.stepRight, color: bodyColor, pixel: pixel)

        // 눈 표정: 만세·디스코·턴 동작에서는 신나는 눈(^ ^)이나 윙크를 섞어 생동감을 준다.
        let eyeShift = max(0, min(2, xOff + headShift))
        let eyes: [(Int, Int)]
        if style == .handsUp && (airborne || frame % 4 < 2) {
            eyes = happyEyes
        } else if style == .discoFever && frame % 4 < 2 {
            eyes = [(4, 4), (4, 5), (10, 5), (11, 5)] // 윙크
        } else if playing {
            eyes = closedEyes
        } else if mood == .calm {
            eyes = softEyes
        } else {
            eyes = openEyes
        }
        for (x, y) in eyes {
            pixel(x + eyeShift, top + y, eyeColor)
        }

        // 안무(DanceStyle)에 따른 다리 스텝 그리기
        let footBottom = topMargin + coreBody.count + 1 + (airborne ? -1 : 0)
        let activeLegs = (style == .spinJump && airborne) ? wideLegColumns : legColumns
        for (index, baseX) in activeLegs.enumerated() {
            var legX = baseX + xOff
            var liftFoot = airborne && ((index < 2) != dance.stepRight)
            switch style {
            case .moonwalk:
                let stride = (frame + index) % 4
                if stride == 0 {
                    liftFoot = true
                    legX += (dance.stepRight ? -1 : 1)
                }
            case .waveTilt:
                liftFoot = (frame + index) % 4 == 0
            case .discoFever:
                if airborne || frame % 2 == 0 {
                    if dance.stepRight && index == 3 {
                        legX += 1
                        liftFoot = true
                    } else if !dance.stepRight && index == 0 {
                        legX -= 1
                        liftFoot = true
                    }
                }
            default:
                break
            }
            if bob || landing || liftFoot {
                pixel(legX, liftFoot ? footBottom - 1 : footBottom, bodyColor)
            } else {
                pixel(legX, footBottom - 1, bodyColor)
                pixel(legX, footBottom, bodyColor)
            }
        }

        if mood == .bright && !showDisco {
            let spots: [(Int, Int)] = airborne
                ? [(0, 2), (15, 3)]
                : {
                    switch frame % 4 {
                    case 0: return [(3, 0), (14, 0)]
                    case 1: return [(7, 0), (1, 0)]
                    case 2: return [(11, 0), (5, 0)]
                    default: return [(15, 0), (9, 0)]
                    }
                }()
            for (x, y) in spots {
                pixel(x + (y == 0 ? 0 : xOff), y == 0 ? 0 : top + y, sparkle)
            }
        }

        if mood == .bass {
            let legs = Set(activeLegs.map { $0 + xOff })
            let span = (airborne ? [1, 6, 7, 8, 9, 15] : landing ? [6, 7, 8, 9] : [7, 8]).map { $0 + xOff }
            let color = thump.withAlphaComponent(airborne ? 1 : 0.75)
            for x in span where (0..<18).contains(x) && !legs.contains(x) {
                pixel(x, 13, color)
            }
        }

        // FM 을 들을 때도, 다른 소리에 춤출 때도, 분위기만 남아도 음표는 띄운다.
        guard playing || dancing || mood != .quiet else { return }
        let step = frame % 8
        let glyph = (mood == .drive || mood == .bass) ? notes[1] : notes[(frame / 8) % notes.count]
        let rise: Int
        switch mood {
        case .calm: rise = step / 2
        case .bass: rise = min(step, 3)
        case .bright: rise = min(step + 2, 7)
        default: rise = step
        }
        let alpha: CGFloat = mood == .calm ? 0.55 : (mood == .drive ? 1 : (step == 0 ? 0.6 : step >= 6 ? 0.45 : 1))
        let noteTint = showDisco ? discoColors[(frame / 2) % discoColors.count].withAlphaComponent(max(0.75, alpha)) : noteColor.withAlphaComponent(alpha)
        let noteTop = 7 - rise
        let drift = mood == .calm ? noteDrift[step] / 2 : noteDrift[step]
        for (row, line) in glyph.enumerated() {
            for (col, ch) in line.enumerated() where ch == "N" {
                pixel(noteLeft + drift + col, noteTop + row, noteTint)
            }
        }
    }

    private static func drawArms(
        style: DanceStyle,
        frame: Int,
        xOff: Int,
        top: Int,
        airborne: Bool,
        stepRight: Bool,
        color: NSColor,
        pixel: (Int, Int, NSColor) -> Void
    ) {
        let leftRows: [Int]
        let rightRows: [Int]
        var leftTip: (Int, Int)?
        var rightTip: (Int, Int)?

        switch style {
        case .bounce:
            leftRows = [6, 7]
            rightRows = [6, 7]
        case .handsUp:
            if airborne || frame % 2 == 0 {
                leftRows = [3, 4]
                rightRows = [3, 4]
                leftTip = (0, 2)
                rightTip = (15, 2)
            } else {
                leftRows = stepRight ? [4, 5] : [6, 7]
                rightRows = stepRight ? [6, 7] : [4, 5]
            }
        case .waveTilt:
            let phase = frame % 4
            leftRows = (phase == 0 || phase == 1) ? [4, 5] : [7, 8]
            rightRows = (phase == 0 || phase == 1) ? [7, 8] : [4, 5]
        case .moonwalk:
            let swing = (frame / 2) % 2 == 0
            leftRows = swing ? [5, 6] : [7, 8]
            rightRows = swing ? [7, 8] : [5, 6]
        case .spinJump:
            if airborne {
                leftRows = [3, 4]
                rightRows = [3, 4]
                leftTip = (0, 2)
                rightTip = (15, 2)
            } else {
                leftRows = (frame % 2 == 0) ? [5, 6] : [6, 7]
                rightRows = (frame % 2 == 0) ? [6, 7] : [5, 6]
            }
        case .discoFever:
            if stepRight || frame % 4 < 2 {
                leftRows = [7, 8]
                rightRows = [3, 4]
                rightTip = (15, 2)
            } else {
                leftRows = [3, 4]
                rightRows = [7, 8]
                leftTip = (0, 2)
            }
        }

        for r in leftRows {
            pixel(0 + xOff, top + r, color)
            pixel(1 + xOff, top + r, color)
        }
        for r in rightRows {
            pixel(14 + xOff, top + r, color)
            pixel(15 + xOff, top + r, color)
        }
        if let (tx, ty) = leftTip {
            pixel(tx + xOff, top + ty, color)
        }
        if let (tx, ty) = rightTip {
            pixel(tx + xOff, top + ty, color)
        }
    }

    /// 천장에 매달린 미니 미러볼과 회전하는 오색 반짝이 조명을 그린다.
    private static func drawMirrorballAndLights(
        frame: Int,
        xOff: Int,
        airborne: Bool,
        pixel: (Int, Int, NSColor) -> Void
    ) {
        // 상단 미러볼 (x = 16..17, y = 0..2)
        pixel(16, 0, mirrorCord)
        let f0 = (frame % 2 == 0) ? mirrorSilver : discoColors[frame % discoColors.count]
        let f1 = (frame % 2 == 1) ? mirrorSilver : discoColors[(frame + 1) % discoColors.count]
        let f2 = discoColors[(frame + 2) % discoColors.count]
        let f3 = (frame % 3 == 0) ? mirrorSilver : discoColors[(frame + 3) % discoColors.count]
        pixel(16, 1, f0)
        pixel(17, 1, f1)
        pixel(16, 2, f2)
        pixel(17, 2, f3)

        // 미러볼에서 퍼져 나가는 반짝이 스포트라이트 입자들
        let beams: [[(Int, Int)]] = [
            [(1, 0), (6, 0), (12, 0), (0, 4), (17, 6), (2, 12)],
            [(2, 0), (9, 0), (14, 0), (1, 2), (16, 9), (14, 12)],
            [(0, 1), (4, 0), (11, 0), (15, 4), (0, 10), (7, 13)],
            [(3, 0), (8, 0), (13, 0), (0, 6), (17, 11), (12, 13)],
        ]
        let pattern = beams[frame % beams.count]
        for (idx, spot) in pattern.enumerated() {
            let beamColor = (idx == 0 && airborne)
                ? mirrorSilver
                : discoColors[(frame + idx) % discoColors.count].withAlphaComponent(0.92)
            pixel(spot.0, spot.1, beamColor)
        }
    }
}
