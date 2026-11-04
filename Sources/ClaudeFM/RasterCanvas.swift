import Foundation

/// 작은 RGBA 픽셀 판. 무대 장면을 픽셀 단위로 그린 뒤 화면에서는 이웃 픽셀 그대로 키워 보여 준다.
/// 늘 불투명하게 두어서 섞기는 `바닥 × (1 − a) + 색 × a` 만 하면 된다.
final class RasterCanvas {
    let width: Int
    let height: Int
    /// 위에서 아래로, 한 칸에 R·G·B·A 네 바이트.
    private(set) var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        bytes = [UInt8](repeating: 255, count: self.width * self.height * 4)
    }

    /// 잘 안 바뀌는 바탕(하늘)을 기억해 두었다가 다음 프레임에 그대로 깐다.
    private var memo: (key: AnyHashable, bytes: [UInt8])?

    /// `key` 로 기억한 위쪽 `rows` 줄이 있으면 깔고 true.
    func restore(_ key: AnyHashable, rows: Int) -> Bool {
        guard let memo, memo.key == key, memo.bytes.count == min(rows, height) * width * 4 else { return false }
        bytes.replaceSubrange(0..<memo.bytes.count, with: memo.bytes)
        return true
    }

    /// 지금 위쪽 `rows` 줄을 `key` 로 기억한다.
    func remember(_ key: AnyHashable, rows: Int) {
        memo = (key, Array(bytes[0..<(min(rows, height) * width * 4)]))
    }

    func clear(_ color: RGBColor) {
        let r = Self.byte(color.r), g = Self.byte(color.g), b = Self.byte(color.b)
        bytes.withUnsafeMutableBufferPointer { buffer in
            var index = 0
            while index < buffer.count {
                buffer[index] = r
                buffer[index + 1] = g
                buffer[index + 2] = b
                buffer[index + 3] = 255
                index += 4
            }
        }
    }

    /// 사각형을 덮어 칠한다. `alpha` 가 1 보다 작으면 바닥과 섞는다.
    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBColor, _ alpha: Double = 1) {
        blend(x, y, w, h, color, alpha, additive: false)
    }

    /// 빛처럼 더한다. 조명과 반짝이에 쓴다.
    func add(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBColor, _ alpha: Double) {
        blend(x, y, w, h, color, alpha, additive: true)
    }

    func plot(_ x: Int, _ y: Int, _ color: RGBColor, _ alpha: Double = 1) {
        blend(x, y, 1, 1, color, alpha, additive: false)
    }

    func glow(_ x: Int, _ y: Int, _ color: RGBColor, _ alpha: Double) {
        blend(x, y, 1, 1, color, alpha, additive: true)
    }

    /// 가로줄 하나를 x0...x1 까지 칠한다(양 끝 포함).
    func span(_ x0: Int, _ x1: Int, _ y: Int, _ color: RGBColor, _ alpha: Double, additive: Bool = false) {
        guard x1 >= x0 else { return }
        blend(x0, y, x1 - x0 + 1, 1, color, alpha, additive: additive)
    }

    /// 꼭짓점이 위에 있는 삼각형 빛줄기. 아래로 갈수록 넓어지고 흐려진다.
    func beam(apexX: Double, apexY: Int, bottomY: Int, bottomCenter: Double, halfWidth: Double,
              _ color: RGBColor, _ alpha: Double) {
        guard bottomY > apexY else { return }
        let rows = bottomY - apexY
        for step in 0...rows {
            let t = Double(step) / Double(rows)
            let center = apexX + (bottomCenter - apexX) * t
            let half = 0.5 + halfWidth * t
            let fade = alpha * (1 - t * 0.55)
            let x0 = Int((center - half).rounded()), x1 = Int((center + half).rounded())
            span(x0, x1, apexY + step, color, fade, additive: true)
            // 가장자리를 한 칸 더 옅게 그려 빛이 번지게 한다.
            span(x0 - 1, x0 - 1, apexY + step, color, fade * 0.4, additive: true)
            span(x1 + 1, x1 + 1, apexY + step, color, fade * 0.4, additive: true)
        }
    }

    /// 속이 찬 원. 반지름이 작아도 모양이 나도록 칸 가운데를 기준으로 잰다.
    func disc(_ cx: Double, _ cy: Double, _ radius: Double, _ color: RGBColor, _ alpha: Double = 1, additive: Bool = false) {
        guard radius > 0 else { return }
        let y0 = Int((cy - radius).rounded(.down)), y1 = Int((cy + radius).rounded(.up))
        for y in y0...y1 {
            let dy = Double(y) + 0.5 - cy
            let reach = radius * radius - dy * dy
            guard reach >= 0 else { continue }
            let half = sqrt(reach)
            let x0 = Int((cx - half).rounded()), x1 = Int((cx + half).rounded()) - 1
            span(x0, x1, y, color, alpha, additive: additive)
        }
    }

    /// 가운데가 밝고 바깥으로 흐려지는 빛 무리.
    func halo(_ cx: Double, _ cy: Double, _ radius: Double, _ color: RGBColor, _ alpha: Double) {
        guard radius > 0, alpha > 0.003 else { return }
        let rings = max(2, Int(radius / 2))
        for ring in 0..<rings {
            let t = Double(ring) / Double(rings)
            disc(cx, cy, radius * (1 - t), color, alpha / Double(rings) * (0.6 + t), additive: true)
        }
    }

    /// 픽셀 그림을 `pixel` 배로 키워 찍는다.
    func glyph(_ glyph: PixelGlyph, _ x: Int, _ y: Int, pixel: Int = 1, alpha: Double = 1) {
        for dot in glyph.pixels {
            fill(x + dot.x * pixel, y + dot.y * pixel, pixel, pixel, dot.color, alpha)
        }
    }

    /// 3×5 픽셀 글꼴로 짧은 영문·숫자를 쓴다. 너비를 돌려준다.
    @discardableResult
    func text(_ string: String, _ x: Int, _ y: Int, _ color: RGBColor, _ alpha: Double = 1, pixel: Int = 1,
              additive: Bool = false) -> Int {
        var cursor = x
        for char in string.uppercased() {
            if char == " " {
                cursor += 3 * pixel
                continue
            }
            guard let rows = PixelFont.glyphs[char] else {
                cursor += 4 * pixel
                continue
            }
            for (row, line) in rows.enumerated() {
                for (col, cell) in line.enumerated() where cell == "#" {
                    blend(cursor + col * pixel, y + row * pixel, pixel, pixel, color, alpha, additive: additive)
                }
            }
            cursor += (rows.first?.count ?? 3) * pixel + pixel
        }
        return cursor - x - pixel
    }

    static func textWidth(_ string: String, pixel: Int = 1) -> Int {
        var width = 0
        for char in string.uppercased() {
            if char == " " {
                width += 3 * pixel
            } else {
                width += ((PixelFont.glyphs[char]?.first?.count ?? 3) + 1) * pixel
            }
        }
        return max(0, width - pixel)
    }

    private func blend(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBColor, _ alpha: Double, additive: Bool) {
        guard w > 0, h > 0, alpha > 0.002 else { return }
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(width, x + w), y1 = min(height, y + h)
        guard x1 > x0, y1 > y0 else { return }
        let a = Int((min(1, alpha) * 256).rounded())
        let r = Int(Self.byte(color.r)), g = Int(Self.byte(color.g)), b = Int(Self.byte(color.b))
        let stride = width * 4
        bytes.withUnsafeMutableBufferPointer { buffer in
            for row in y0..<y1 {
                var index = row * stride + x0 * 4
                for _ in x0..<x1 {
                    if additive {
                        buffer[index] = UInt8(min(255, Int(buffer[index]) + ((r * a) >> 8)))
                        buffer[index + 1] = UInt8(min(255, Int(buffer[index + 1]) + ((g * a) >> 8)))
                        buffer[index + 2] = UInt8(min(255, Int(buffer[index + 2]) + ((b * a) >> 8)))
                    } else if a >= 256 {
                        buffer[index] = UInt8(r)
                        buffer[index + 1] = UInt8(g)
                        buffer[index + 2] = UInt8(b)
                    } else {
                        let keep = 256 - a
                        buffer[index] = UInt8((Int(buffer[index]) * keep + r * a) >> 8)
                        buffer[index + 1] = UInt8((Int(buffer[index + 1]) * keep + g * a) >> 8)
                        buffer[index + 2] = UInt8((Int(buffer[index + 2]) * keep + b * a) >> 8)
                    }
                    index += 4
                }
            }
        }
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}

/// 전광판용 3×5 픽셀 글꼴. 영문 대문자, 숫자, 몇 가지 기호만 있다.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"],
        "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"],
        "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"],
        "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"],
        "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"],
        "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
        "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
        "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."],
        "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"],
        "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."],
        "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"],
        "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
        "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
        "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
        "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"],
        "3": ["##.", "..#", ".#.", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "##."],
        "♪": [".##", ".#.", ".#.", "##.", "##."],
        "♥": ["#.#", "###", "###", ".#."],
        "!": ["#", "#", "#", ".", "#"],
        ".": [".", ".", ".", ".", "#"],
        "-": ["...", "...", "###", "...", "..."],
        ":": [".", "#", ".", "#", "."],
        "·": [".", ".", "#", ".", "."],
    ]
}
