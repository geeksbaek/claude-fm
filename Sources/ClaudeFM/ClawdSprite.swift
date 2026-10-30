import AppKit

/// 헤드폰을 쓴 Clawd 픽셀 스프라이트. 한 칸이 1pt 이고 y 는 위에서 아래로 증가한다.
/// 몸은 Claude Code 로고(▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝)를 정사각 픽셀로 푼 비율을 따른다:
/// 몸통 12×8, 1×2 눈, 양옆 2칸 팔, 2칸 다리 4개.
enum ClawdSprite {
    static let canvas = NSSize(width: 24, height: 14)
    static let frameCount = 16

    private static let palette: [Character: NSColor] = [
        "O": NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1), // 몸통 #D97757
        "H": NSColor(srgbRed: 0.784, green: 0.588, blue: 0.290, alpha: 1), // 헤드밴드 #C8964A
        "C": NSColor(srgbRed: 0.420, green: 0.259, blue: 0.149, alpha: 1), // 이어컵 #6B4226
        "c": NSColor(srgbRed: 0.627, green: 0.439, blue: 0.235, alpha: 1), // 이어컵 쿠션 #A0703C
    ]
    private static let eyeColor = NSColor(srgbRed: 0.078, green: 0.078, blue: 0.075, alpha: 1)

    /// 고개를 까딱일 때 함께 움직이는 헤드폰·몸통·팔.
    private static let body: [String] = [
        "....HHHHHHHH....",
        "..HH........HH..",
        ".CCOOOOOOOOOOCC.",
        ".CcOOOOOOOOOOcC.",
        ".CcOOOOOOOOOOcC.",
        ".CCOOOOOOOOOOCC.",
        "OOOOOOOOOOOOOOOO",
        "OOOOOOOOOOOOOOOO",
        "..OOOOOOOOOOOO..",
        "..OOOOOOOOOOOO..",
    ]
    private static let openEyes = [(4, 4), (4, 5), (11, 4), (11, 5)]
    private static let closedEyes = [(4, 5), (5, 5), (10, 5), (11, 5)]
    private static let legColumns = [3, 5, 10, 12]
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
    static func image(frame: Int, playing: Bool, scale: CGFloat = 1) -> NSImage {
        let size = NSSize(width: canvas.width * scale, height: canvas.height * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(frame: frame, playing: playing, scale: scale, origin: .zero, noteColor: .labelColor)
            return true
        }
        image.accessibilityDescription = "Claude FM"
        return image
    }

    /// 뒤집힌(flipped) 좌표계에서 스프라이트를 그린다.
    static func draw(frame: Int, playing: Bool, scale: CGFloat, origin: CGPoint, noteColor: NSColor) {
        func pixel(_ x: Int, _ y: Int, _ color: NSColor) {
            // 배율이 정수가 아니어도 칸 사이에 틈이 생기지 않도록 경계를 반올림한다.
            let x0 = (origin.x + CGFloat(x) * scale).rounded(), x1 = (origin.x + CGFloat(x + 1) * scale).rounded()
            let y0 = (origin.y + CGFloat(y) * scale).rounded(), y1 = (origin.y + CGFloat(y + 1) * scale).rounded()
            color.setFill()
            NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).fill()
        }

        let bob = playing && frame % 4 >= 2 ? 1 : 0
        let top = topMargin + bob

        for (row, line) in body.enumerated() {
            for (col, ch) in line.enumerated() {
                if let color = palette[ch] { pixel(col, top + row, color) }
            }
        }

        // 재생 중에는 눈을 감고 음악에 빠져 있다.
        for (x, y) in playing ? closedEyes : openEyes {
            pixel(x, top + y, eyeColor)
        }

        // 고개를 숙이면 몸이 눌리면서 다리가 한 칸 짧아진다.
        let legBottom = topMargin + body.count + 1
        let legRows = bob == 1 ? [legBottom] : [legBottom - 1, legBottom]
        for x in legColumns {
            for y in legRows { pixel(x, y, palette["O"]!) }
        }

        guard playing else { return }
        let step = frame % 8
        let glyph = notes[(frame / 8) % notes.count]
        let alpha: CGFloat = step == 0 ? 0.6 : step >= 6 ? 0.45 : 1
        let color = noteColor.withAlphaComponent(alpha)
        let noteTop = 7 - step
        for (row, line) in glyph.enumerated() {
            for (col, ch) in line.enumerated() where ch == "N" {
                pixel(noteLeft + noteDrift[step] + col, noteTop + row, color)
            }
        }
    }
}
