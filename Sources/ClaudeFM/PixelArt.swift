import Foundation

/// 화면 종류와 무관한 sRGB 색. AppKit 쪽에서 NSColor·CGColor 로 바꿔 쓴다.
struct RGBColor: Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: RGBColor, _ amount: Double) -> RGBColor {
        let t = min(1, max(0, amount))
        return RGBColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func scaled(_ factor: Double) -> RGBColor {
        RGBColor(r: min(1, r * factor), g: min(1, g * factor), b: min(1, b * factor))
    }

    static let white = RGBColor(0xFFFFFF)
    static let coral = RGBColor(0xD97757)
}

/// 5×5 픽셀 그림. `N` 은 본색, `c` 는 강조색, `.` 은 빈칸.
struct PixelGlyph: Equatable {
    var rows: [String]
    var color: RGBColor
    var accent: RGBColor

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    /// 칠할 칸과 그 색.
    var pixels: [(x: Int, y: Int, color: RGBColor)] {
        var out: [(x: Int, y: Int, color: RGBColor)] = []
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                switch ch {
                case "N": out.append((x, y, color))
                case "c": out.append((x, y, accent))
                default: break
                }
            }
        }
        return out
    }

    static func reaction(_ reaction: LyricReaction) -> PixelGlyph {
        switch reaction {
        case .love:
            return PixelGlyph(rows: [
                ".N.N.",
                "NcNNN",
                "NNNNN",
                ".NNN.",
                "..N..",
            ], color: RGBColor(0xFF4D6D), accent: RGBColor(0xFFC2CF))
        case .star:
            return PixelGlyph(rows: [
                "..N..",
                "..N..",
                "NNcNN",
                ".NNN.",
                ".N.N.",
            ], color: RGBColor(0xFFC93C), accent: RGBColor(0xFFF1B8))
        case .fire:
            return PixelGlyph(rows: [
                "..N..",
                ".NN..",
                ".NcN.",
                "NcccN",
                ".NNN.",
            ], color: RGBColor(0xFF6B2C), accent: RGBColor(0xFFD23F))
        case .tears:
            return PixelGlyph(rows: [
                "..N..",
                ".NNN.",
                "NNNNN",
                "NcNNN",
                ".NNN.",
            ], color: RGBColor(0x4FA8FF), accent: RGBColor(0xCDE8FF))
        case .moon:
            return PixelGlyph(rows: [
                ".NNN.",
                "NN.c.",
                "NN...",
                "NN...",
                ".NNN.",
            ], color: RGBColor(0xF5C542), accent: RGBColor(0xFFF1B8))
        case .flower:
            return PixelGlyph(rows: [
                ".N.N.",
                "NNNNN",
                ".NcN.",
                "NNNNN",
                ".N.N.",
            ], color: RGBColor(0xFF7EB6), accent: RGBColor(0xFFD23F))
        case .sun:
            return PixelGlyph(rows: [
                "N.N.N",
                ".NNN.",
                "NNcNN",
                ".NNN.",
                "N.N.N",
            ], color: RGBColor(0xFFA62B), accent: RGBColor(0xFFE066))
        case .snow:
            return PixelGlyph(rows: [
                "..N..",
                "N.N.N",
                ".NcN.",
                "N.N.N",
                "..N..",
            ], color: RGBColor(0x7CC4FF), accent: RGBColor(0xE8F6FF))
        }
    }
}

extension PixelGlyph {
    /// 전광판과 무대 글자 층에 쓰는 9칸짜리 큰 그림. 색은 작은 그림과 같다.
    static func large(_ reaction: LyricReaction) -> PixelGlyph {
        let small = PixelGlyph.reaction(reaction)
        let rows: [String]
        switch reaction {
        case .love:
            rows = [
                ".NN...NN.",
                "NNNN.NNNN",
                "NcNNNNNNN",
                "NccNNNNNN",
                ".NNNNNNN.",
                "..NNNNN..",
                "...NNN...",
                "....N....",
            ]
        case .star:
            rows = [
                "....N....",
                "...NNN...",
                "...NcN...",
                "NNNNcNNNN",
                ".NNNNNNN.",
                "..NNNNN..",
                "..NNNNN..",
                ".NNN.NNN.",
                ".N.....N.",
            ]
        case .fire:
            rows = [
                "....N....",
                "...NN....",
                "...NNN.N.",
                "..NNcNNN.",
                ".NNcccNN.",
                ".NcccccNN",
                "NNcccccNN",
                "NNNcccNNN",
                ".NNNNNNN.",
            ]
        case .tears:
            rows = [
                "...N...",
                "..NNN..",
                "..NNN..",
                ".NNNNN.",
                "NNNNNNN",
                "NcNNNNN",
                "NcNNNNN",
                ".NNNNN.",
                "..NNN..",
            ]
        case .moon:
            rows = [
                "...NNNN.",
                ".NNNN...",
                ".NNN....",
                "NNN.....",
                "NNN...c.",
                "NNN.....",
                ".NNN....",
                ".NNNN...",
                "...NNNN.",
            ]
        case .flower:
            rows = [
                "...NNN...",
                "..NNNNN..",
                "...NNN...",
                "NN.ccc.NN",
                "NNNcccNNN",
                "NN.ccc.NN",
                "...NNN...",
                "..NNNNN..",
                "...NNN...",
            ]
        case .sun:
            rows = [
                "N...N...N",
                ".N..N..N.",
                "..NNNNN..",
                "..NcccN..",
                "NNNcccNNN",
                "..NcccN..",
                "..NNNNN..",
                ".N..N..N.",
                "N...N...N",
            ]
        case .snow:
            rows = [
                "....N....",
                ".N..N..N.",
                "..N.N.N..",
                "...NNN...",
                "NNNNcNNNN",
                "...NNN...",
                "..N.N.N..",
                ".N..N..N.",
                "....N....",
            ]
        }
        return PixelGlyph(rows: rows, color: small.color, accent: small.accent)
    }
}

/// 분위기마다 무대와 폭죽이 쓰는 색 묶음.
struct MoodPalette: Equatable {
    var primary: RGBColor
    var secondary: RGBColor
    var accent: RGBColor
    var skyTop: RGBColor
    var skyBottom: RGBColor

    static func of(_ mood: MusicMood) -> MoodPalette {
        switch mood {
        case .quiet:
            return MoodPalette(primary: RGBColor(0x6E6A9E), secondary: RGBColor(0x3D3A66), accent: RGBColor(0xD97757),
                               skyTop: RGBColor(0x07060F), skyBottom: RGBColor(0x14112A))
        case .calm:
            return MoodPalette(primary: RGBColor(0x7FA7FF), secondary: RGBColor(0xB79CFF), accent: RGBColor(0xFFE3A3),
                               skyTop: RGBColor(0x070B1E), skyBottom: RGBColor(0x1B1F4A))
        case .groove:
            return MoodPalette(primary: RGBColor(0xFF8A65), secondary: RGBColor(0x4FD1C5), accent: RGBColor(0xFFD166),
                               skyTop: RGBColor(0x0B0820), skyBottom: RGBColor(0x2A1340))
        case .bass:
            return MoodPalette(primary: RGBColor(0xFF4D4D), secondary: RGBColor(0xFF9F1C), accent: RGBColor(0xFFE066),
                               skyTop: RGBColor(0x120509), skyBottom: RGBColor(0x3A0C1C))
        case .bright:
            return MoodPalette(primary: RGBColor(0x5CE1E6), secondary: RGBColor(0xFFD23F), accent: RGBColor(0xFFFFFF),
                               skyTop: RGBColor(0x061424), skyBottom: RGBColor(0x14365A))
        case .drive:
            return MoodPalette(primary: RGBColor(0xFF4FD8), secondary: RGBColor(0x7C5CFF), accent: RGBColor(0x5CF2FF),
                               skyTop: RGBColor(0x0D041C), skyBottom: RGBColor(0x2E0B4F))
        }
    }

    /// 폭죽 종이 색. 분위기 색에 Claude 코랄과 금색을 섞는다.
    var confetti: [RGBColor] {
        [primary, secondary, accent, RGBColor(0xD97757), RGBColor(0xFFD23F), RGBColor(0xFFFFFF)]
    }
}

/// 같은 씨앗이면 늘 같은 값을 주는 작은 난수. 무대 입자를 상태 없이 그릴 때 쓴다.
enum PixelNoise {
    static func unit(_ seed: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(salt)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 29
        return Double(x % 1_000_003) / 1_000_003
    }

    static func signed(_ seed: Int, _ salt: Int = 0) -> Double {
        unit(seed, salt) * 2 - 1
    }
}

/// 한 번 터지는 폭죽. 입자 위치를 시간의 식으로 바로 구해서 프레임마다 상태를 들고 있지 않는다.
/// 좌표는 그리는 쪽 단위(포인트나 무대 픽셀)이고 y 는 아래로 커진다.
struct ConfettiBurst: Equatable {
    struct Piece: Equatable {
        var x: Double
        var y: Double
        /// 1 이면 넓은 면, 0 이면 옆면. 종이가 뒤집히며 반짝이는 느낌을 준다.
        var face: Double
        var size: Double
        var color: RGBColor
        var alpha: Double
        var glyph: LyricReaction?
    }

    var originX: Double
    var originY: Double
    /// 퍼지는 세기. 포인트 단위 화면이면 1, 작은 무대 픽셀이면 더 작게.
    var scale: Double
    var count: Int
    var seed: Int
    var colors: [RGBColor]
    /// 섞어 뿌릴 반응 그림. 사랑 노래면 하트도 같이 날린다.
    var glyph: LyricReaction?
    /// 아래로만 쏟아지는지(메뉴바), 위로 솟았다 떨어지는지(무대).
    var upward: Bool

    static let lifetime = 2.4

    func pieces(at t: Double) -> [Piece] {
        guard t >= 0, t < Self.lifetime, !colors.isEmpty else { return [] }
        let gravity = 210.0 * scale
        let drag = 2.3
        var out: [Piece] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let angle: Double
            if upward {
                angle = -Double.pi / 2 + PixelNoise.signed(seed + i, 1) * 1.15
            } else {
                angle = Double.pi / 2 + PixelNoise.signed(seed + i, 1) * 1.25
            }
            let speed = (150 + PixelNoise.unit(seed + i, 2) * 260) * scale * (upward ? 1.35 : 1)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed
            let decay = (1 - exp(-drag * t)) / drag
            let terminal = gravity / drag
            let flutter = sin(t * (5 + PixelNoise.unit(seed + i, 3) * 4) + PixelNoise.unit(seed + i, 4) * 6.28) * 7 * scale
            let x = originX + vx * decay + flutter * min(1, t * 2)
            let y = originY + terminal * t + (vy - terminal) * decay
            let spin = t * (7 + PixelNoise.unit(seed + i, 5) * 9) + PixelNoise.unit(seed + i, 6) * 6.28
            let fadeStart = Self.lifetime * 0.62
            let alpha = t < fadeStart ? 1 : max(0, 1 - (t - fadeStart) / (Self.lifetime - fadeStart))
            let color = colors[((seed + i) % colors.count + colors.count) % colors.count]
            let useGlyph = glyph != nil && i % 5 == 0
            out.append(Piece(
                x: x,
                y: y,
                face: abs(cos(spin)),
                size: (useGlyph ? 1.0 : 1.5 + PixelNoise.unit(seed + i, 7) * 1.5) * max(scale, 0.2),
                color: color,
                alpha: alpha,
                glyph: useGlyph ? glyph : nil
            ))
        }
        return out
    }
}
