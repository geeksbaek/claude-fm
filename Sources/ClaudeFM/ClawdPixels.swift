import Foundation

/// 헤드폰을 쓴 Clawd 픽셀 스프라이트의 칸 그리기. 화면 종류와 무관하게 칸 좌표와 색만 낸다.
/// 한 칸이 1pt 이고 y 는 위에서 아래로 증가한다.
/// 몸은 Claude Code 로고(▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝)를 정사각 픽셀로 푼 비율을 따른다:
/// 몸통 12×8, 1×2 눈, 양옆 2칸 팔, 2칸 다리 4개.
enum ClawdPixels {
    static let width = 24
    static let height = 14
    static let frameCount = 96

    /// 칸 하나를 칠한다. 좌표는 스프라이트 칸 단위다.
    typealias Plot = (_ x: Int, _ y: Int, _ color: RGBColor, _ alpha: Double) -> Void

    private static let palette: [Character: RGBColor] = [
        "O": RGBColor(r: 0.851, g: 0.467, b: 0.341), // 몸통 #D97757
        "H": RGBColor(r: 0.784, g: 0.588, b: 0.290), // 헤드밴드 #C8964A
        "C": RGBColor(r: 0.420, g: 0.259, b: 0.149), // 이어컵 #6B4226
        "c": RGBColor(r: 0.627, g: 0.439, b: 0.235), // 이어컵 쿠션 #A0703C
    ]
    static let bodyColor = palette["O"]!
    private static let eyeColor = RGBColor(r: 0.078, g: 0.078, b: 0.075)
    private static let headFlash = RGBColor(r: 0.98, g: 0.84, b: 0.42)
    private static let sparkle = RGBColor(r: 1, g: 0.84, b: 0.20)
    private static let thump = RGBColor(r: 0.98, g: 0.62, b: 0.28)
    static let discoColors: [RGBColor] = [
        RGBColor(r: 0.36, g: 0.92, b: 0.98), // 네온 시안
        RGBColor(r: 1.00, g: 0.42, b: 0.82), // 마젠타 핑크
        RGBColor(r: 1.00, g: 0.88, b: 0.28), // 미러볼 골드
        RGBColor(r: 0.72, g: 0.54, b: 1.00), // 네온 바이올렛
        RGBColor(r: 0.42, g: 0.96, b: 0.68), // 민트 그린
    ]
    static let mirrorSilver = RGBColor(r: 0.92, g: 0.95, b: 1.0)
    private static let mirrorCord = RGBColor(r: 0.62, g: 0.66, b: 0.74)

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

    /// `accent` 가 있으면 음표 대신 가사 반응 그림을 띄운다. `decorations` 를 끄면 미러볼 장식을 빼고 그린다(무대용).
    static func render(
        frame: Int,
        playing: Bool,
        dance: DancePose = .idle,
        noteColor: RGBColor,
        accent: SpriteAccent = .none,
        decorations: Bool = true,
        plot: Plot
    ) {
        func pixel(_ x: Int, _ y: Int, _ color: RGBColor, _ alpha: Double) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            plot(x, y, color, alpha)
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
        if showDisco, decorations {
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
                let color: RGBColor?
                if ch == "H", flashHead {
                    color = showDisco ? discoTint : headFlash
                } else if ch == "c", showDisco, (col + frame) % 3 == 0 {
                    color = discoColors[(frame + 2) % discoColors.count]
                } else {
                    color = palette[ch]
                }
                if let color { pixel(col + rowShift, top + row, color, 1) }
            }
        }

        // 안무(DanceStyle)에 따른 양팔 동작 그리기
        drawArms(style: style, frame: frame, xOff: xOff, top: top, airborne: airborne, stepRight: dance.stepRight,
                 color: bodyColor, pixel: pixel)

        // 눈 표정: 만세·디스코·턴 동작에서는 신나는 눈(^ ^)이나 윙크를 섞어 생동감을 준다.
        let eyeShift = max(0, min(2, xOff + headShift))
        let eyes: [(Int, Int)]
        if style == .handsUp && (airborne || frame % 4 < 2) {
            eyes = happyEyes
        } else if style == .discoFever && frame % 4 < 2 {
            eyes = [(4, 4), (4, 5), (10, 5), (11, 5)] // 윙크
        } else if accent.hook && !dancing {
            eyes = happyEyes
        } else if playing {
            eyes = closedEyes
        } else if mood == .calm {
            eyes = softEyes
        } else {
            eyes = openEyes
        }
        for (x, y) in eyes {
            pixel(x + eyeShift, top + y, eyeColor, 1)
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
                pixel(legX, liftFoot ? footBottom - 1 : footBottom, bodyColor, 1)
            } else {
                pixel(legX, footBottom - 1, bodyColor, 1)
                pixel(legX, footBottom, bodyColor, 1)
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
                pixel(x + (y == 0 ? 0 : xOff), y == 0 ? 0 : top + y, sparkle, 1)
            }
        }

        if mood == .bass {
            let legs = Set(activeLegs.map { $0 + xOff })
            let span = (airborne ? [1, 6, 7, 8, 9, 15] : landing ? [6, 7, 8, 9] : [7, 8]).map { $0 + xOff }
            for x in span where (0..<18).contains(x) && !legs.contains(x) {
                pixel(x, 13, thump, airborne ? 1 : 0.75)
            }
        }

        // FM 을 들을 때도, 다른 소리에 춤출 때도, 분위기만 남아도 음표는 띄운다. 가사를 부르는 중이면 반응 그림을 띄운다.
        guard playing || dancing || mood != .quiet || accent.reaction != nil else { return }
        let step = frame % 8
        let glyph = (mood == .drive || mood == .bass) ? notes[1] : notes[(frame / 8) % notes.count]
        let rise: Int
        switch mood {
        case .calm: rise = step / 2
        case .bass: rise = min(step, 3)
        case .bright: rise = min(step + 2, 7)
        default: rise = step
        }
        let alpha: Double = mood == .calm ? 0.55 : (mood == .drive ? 1 : (step == 0 ? 0.6 : step >= 6 ? 0.45 : 1))
        let noteTop = 7 - rise
        let drift = mood == .calm ? noteDrift[step] / 2 : noteDrift[step]
        if let reaction = accent.reaction {
            let picture = PixelGlyph.reaction(reaction)
            let glyphAlpha = max(0.85, alpha)
            for dot in picture.pixels {
                pixel(noteLeft + drift + dot.x, noteTop + dot.y, dot.color, glyphAlpha)
            }
            return
        }
        let noteTint = showDisco ? discoColors[(frame / 2) % discoColors.count] : noteColor
        let noteAlpha = showDisco ? max(0.75, alpha) : alpha
        for (row, line) in glyph.enumerated() {
            for (col, ch) in line.enumerated() where ch == "N" {
                pixel(noteLeft + drift + col, noteTop + row, noteTint, noteAlpha)
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
        color: RGBColor,
        pixel: (Int, Int, RGBColor, Double) -> Void
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
            pixel(0 + xOff, top + r, color, 1)
            pixel(1 + xOff, top + r, color, 1)
        }
        for r in rightRows {
            pixel(14 + xOff, top + r, color, 1)
            pixel(15 + xOff, top + r, color, 1)
        }
        if let (tx, ty) = leftTip {
            pixel(tx + xOff, top + ty, color, 1)
        }
        if let (tx, ty) = rightTip {
            pixel(tx + xOff, top + ty, color, 1)
        }
    }

    /// 천장에 매달린 미니 미러볼과 회전하는 오색 반짝이 조명을 그린다.
    private static func drawMirrorballAndLights(
        frame: Int,
        xOff: Int,
        airborne: Bool,
        pixel: (Int, Int, RGBColor, Double) -> Void
    ) {
        // 상단 미러볼 (x = 16..17, y = 0..2)
        pixel(16, 0, mirrorCord, 0.85)
        let f0 = (frame % 2 == 0) ? mirrorSilver : discoColors[frame % discoColors.count]
        let f1 = (frame % 2 == 1) ? mirrorSilver : discoColors[(frame + 1) % discoColors.count]
        let f2 = discoColors[(frame + 2) % discoColors.count]
        let f3 = (frame % 3 == 0) ? mirrorSilver : discoColors[(frame + 3) % discoColors.count]
        pixel(16, 1, f0, 1)
        pixel(17, 1, f1, 1)
        pixel(16, 2, f2, 1)
        pixel(17, 2, f3, 1)

        // 미러볼에서 퍼져 나가는 반짝이 스포트라이트 입자들
        let beams: [[(Int, Int)]] = [
            [(1, 0), (6, 0), (12, 0), (0, 4), (17, 6), (2, 12)],
            [(2, 0), (9, 0), (14, 0), (1, 2), (16, 9), (14, 12)],
            [(0, 1), (4, 0), (11, 0), (15, 4), (0, 10), (7, 13)],
            [(3, 0), (8, 0), (13, 0), (0, 6), (17, 11), (12, 13)],
        ]
        let pattern = beams[frame % beams.count]
        for (idx, spot) in pattern.enumerated() {
            if idx == 0 && airborne {
                pixel(spot.0, spot.1, mirrorSilver, 1)
            } else {
                pixel(spot.0, spot.1, discoColors[(frame + idx) % discoColors.count], 0.92)
            }
        }
    }
}
