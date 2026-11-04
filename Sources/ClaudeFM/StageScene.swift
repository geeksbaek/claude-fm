import Foundation

/// 무대 한 장면을 그리는 데 필요한 것. 무대 창이 프레임마다 채운다.
struct StageInput {
    /// 흐르는 시간(초). 조명과 입자가 이 시각으로 움직인다.
    var time: Double = 0
    /// 메뉴바와 같은 박자의 스프라이트 프레임.
    var spriteFrame = 0
    var pose = DancePose.idle
    /// Claude FM 을 듣는 중(눈을 감고 흥얼거린다).
    var playing = false
    var accent = SpriteAccent.none
    var feeling = VocalFeeling.calm
    var spectrum: [Double] = Array(repeating: 0, count: SpectrumMeter.bandCount)
    var beatCount = 0
    /// 지금 박 안에서 얼마나 지났는지(0...1).
    var beatPhase = 0.0
    /// 지금 줄의 가사 반응. 꺼질 때도 서서히 사라지도록 마지막 반응을 남겨 둔다.
    var reaction: LyricReaction?
    var reactionLevel = 0.0
    /// 후렴이 얼마나 켜졌는지(0...1).
    var hookLevel = 0.0
    var bursts: [StageBurst] = []
    /// 하늘색을 고르는 지금 시각(0...23).
    var hour = 21
    /// 음악이 흐르는 중. 아니면 조명을 낮추고 관객이 쉰다.
    var live = false
    /// 관객 환호(0...1). 폭죽이 터지거나 무대를 누르면 다 같이 뛴다.
    var cheer = 0.0
    /// 전광판 위에 제목·곡 기록 글자가 뜨는 중(0...1). 전광판을 어둡게 눌러 글자가 읽히게 한다.
    var splash = 0.0
    /// 시스템 설정의 '동작 줄이기'. 전광판이 번쩍이지 않는다.
    var reduceMotion = false
}

/// 무대에서 터진 폭죽과 그 나이.
struct StageBurst {
    var burst: ConfettiBurst
    var age: Double
}

/// 무대 픽셀 배치. 높이 180 칸쯤을 기준으로 비율로 잡는다.
struct StageLayout {
    let width: Int
    let height: Int
    let spriteScale: Int
    let trussY: Int
    let floorTop: Int
    let floorBottom: Int
    let crowdTop: Int
    let screenX: Int
    let screenY: Int
    let screenW: Int
    let screenH: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        spriteScale = max(2, min(6, Int((Double(height) * 0.24 / 14).rounded())))
        trussY = max(4, height / 22)
        floorTop = Int(Double(height) * 0.64)
        floorBottom = floorTop + max(6, height / 14)
        crowdTop = Int(Double(height) * 0.80)
        screenW = max(40, Int(Double(width) * 0.42))
        screenH = max(24, Int(Double(height) * 0.30))
        screenX = (width - screenW) / 2
        screenY = trussY + max(6, height / 22)
    }

    /// Clawd 몸통 가운데 x.
    var centerX: Int { width / 2 }
}

enum StageScene {
    static func render(_ input: StageInput, into canvas: RasterCanvas) {
        let layout = StageLayout(width: canvas.width, height: canvas.height)
        let mood = input.live ? (input.pose.mood == .quiet ? MusicMood.groove : input.pose.mood) : .quiet
        let palette = MoodPalette.of(mood)
        let sky = timeSky(input.hour, palette: palette)
        let hop = input.pose.active ? input.pose.hop : 0
        let energy = input.live ? min(1, 0.35 + input.feeling.wave * 0.65) : 0.12

        drawSky(canvas, layout, sky: sky, time: input.time)
        if input.reaction == .moon { drawMoon(canvas, layout, level: input.reactionLevel, sky: sky) }
        if input.reaction == .sun { drawSun(canvas, layout, level: input.reactionLevel, time: input.time) }
        if input.reaction == .star { drawStarShower(canvas, layout, level: input.reactionLevel, time: input.time) }
        drawSkyline(canvas, layout, sky: sky, time: input.time)
        drawBeams(canvas, layout, input: input, palette: palette, energy: energy, hop: hop)
        drawScreen(canvas, layout, input: input, palette: palette, hop: hop)
        drawTruss(canvas, layout, input: input, palette: palette, hop: hop)
        if input.live, mood != .calm, input.pose.hasMirrorball || mood == .bright || mood == .drive || input.hookLevel > 0.5 {
            drawMirrorball(canvas, layout, time: input.time, hop: hop)
        }
        drawSpeakers(canvas, layout, bass: input.live ? input.feeling.bass : 0, hop: hop)
        drawFloor(canvas, layout, input: input, palette: palette, hop: hop)
        if input.reaction == .fire { drawFireJets(canvas, layout, level: input.reactionLevel, time: input.time, hop: hop) }
        drawClawd(canvas, layout, input: input, palette: palette, hop: hop)
        drawFog(canvas, layout, time: input.time, palette: palette, live: input.live)
        drawCrowd(canvas, layout, input: input, palette: palette, hop: hop)
        if let reaction = input.reaction, input.reactionLevel > 0.01 {
            drawWeather(canvas, layout, reaction: reaction, level: input.reactionLevel, time: input.time)
        }
        for burst in input.bursts {
            drawConfetti(canvas, burst)
        }
    }

    // MARK: - 하늘

    struct Sky {
        var top: RGBColor
        var bottom: RGBColor
        var stars: Double
        var horizon: RGBColor
    }

    /// 밤에는 별이 많고, 해 질 녘에는 지평선이 노을빛이고, 낮에는 푸른 저녁 같은 하늘.
    static func timeSky(_ hour: Int, palette: MoodPalette) -> Sky {
        switch hour {
        case 6..<16:
            return Sky(top: palette.skyTop.mixed(with: RGBColor(0x0F2A55), 0.55),
                       bottom: palette.skyBottom.mixed(with: RGBColor(0x3C6FA8), 0.5),
                       stars: 0.25, horizon: RGBColor(0x6FA3D6))
        case 16..<19:
            return Sky(top: palette.skyTop.mixed(with: RGBColor(0x231447), 0.5),
                       bottom: palette.skyBottom.mixed(with: RGBColor(0xD9645A), 0.45),
                       stars: 0.45, horizon: RGBColor(0xFF9A5C))
        default:
            return Sky(top: palette.skyTop, bottom: palette.skyBottom, stars: 1, horizon: palette.skyBottom.scaled(1.4))
        }
    }

    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

    private struct SkyKey: Hashable {
        var width: Int
        var rows: Int
        var top: RGBColor
        var bottom: RGBColor
        var horizon: RGBColor
    }

    private static func drawSky(_ canvas: RasterCanvas, _ layout: StageLayout, sky: Sky, time: Double) {
        let bottomY = layout.floorTop
        let key = SkyKey(width: layout.width, rows: bottomY, top: sky.top, bottom: sky.bottom, horizon: sky.horizon)
        if !canvas.restore(key, rows: bottomY) {
            drawSkyGradient(canvas, layout, sky: sky)
            canvas.remember(key, rows: bottomY)
        }
        drawStars(canvas, layout, sky: sky, time: time)
    }

    private static func drawSkyGradient(_ canvas: RasterCanvas, _ layout: StageLayout, sky: Sky) {
        let bottomY = layout.floorTop
        let bands = 9.0
        for y in 0..<bottomY {
            let t = Double(y) / Double(max(1, bottomY - 1))
            let level = t * bands
            let low = floor(level)
            let frac = level - low
            let colorA = sky.top.mixed(with: sky.bottom, low / bands)
            let colorB = sky.top.mixed(with: sky.bottom, min(1, (low + 1) / bands))
            for x in 0..<layout.width {
                let threshold = bayer[(x & 3) + (y & 3) * 4]
                canvas.plot(x, y, frac > threshold ? colorB : colorA)
            }
        }
        // 지평선 쪽 노을·도시 불빛
        for row in 0..<max(4, layout.height / 18) {
            let y = bottomY - 1 - row
            canvas.span(0, layout.width - 1, y, sky.horizon, 0.10 * (1 - Double(row) / Double(max(4, layout.height / 18))), additive: true)
        }
    }

    private static func drawStars(_ canvas: RasterCanvas, _ layout: StageLayout, sky: Sky, time: Double) {
        let count = Int(Double(layout.width * layout.floorTop) / 160 * sky.stars)
        for index in 0..<count {
            let x = Int(PixelNoise.unit(index, 11) * Double(layout.width))
            let y = Int(pow(PixelNoise.unit(index, 12), 1.6) * Double(layout.floorTop) * 0.75)
            let twinkle = 0.5 + 0.5 * sin(time * (1.2 + PixelNoise.unit(index, 13) * 2.4) + PixelNoise.unit(index, 14) * 6.28)
            let bright = PixelNoise.unit(index, 15) > 0.9
            let alpha = (bright ? 0.55 : 0.22) + twinkle * (bright ? 0.45 : 0.3)
            canvas.glow(x, y, RGBColor(0xFFF6E0), alpha)
            if bright, twinkle > 0.7 {
                canvas.glow(x - 1, y, RGBColor(0xFFF6E0), alpha * 0.35)
                canvas.glow(x + 1, y, RGBColor(0xFFF6E0), alpha * 0.35)
                canvas.glow(x, y - 1, RGBColor(0xFFF6E0), alpha * 0.35)
                canvas.glow(x, y + 1, RGBColor(0xFFF6E0), alpha * 0.35)
            }
        }
    }

    /// 무대 뒤 먼 도시. 창문 불빛이 천천히 깜빡인다.
    private static func drawSkyline(_ canvas: RasterCanvas, _ layout: StageLayout, sky: Sky, time: Double) {
        let base = layout.floorTop
        let maxHeight = Double(layout.height) * 0.2
        let shade = sky.bottom.scaled(0.42)
        var x = 0
        var index = 0
        while x < layout.width {
            let w = 6 + Int(PixelNoise.unit(index, 21) * 12)
            let h = Int(maxHeight * (0.3 + PixelNoise.unit(index, 22) * 0.7))
            canvas.fill(x, base - h, w, h, shade)
            // 옥상 테두리
            canvas.span(x, x + w - 1, base - h, sky.horizon, 0.12)
            // 창문
            var wy = base - h + 3
            while wy < base - 2 {
                var wx = x + 2
                while wx < x + w - 2 {
                    let seed = index * 997 + wx * 31 + wy
                    let lit = PixelNoise.unit(seed, 23) > 0.62
                    if lit {
                        let flicker = 0.5 + 0.5 * sin(time * 0.3 + PixelNoise.unit(seed, 24) * 20)
                        canvas.plot(wx, wy, RGBColor(0xFFD58A), 0.18 + flicker * 0.25)
                    }
                    wx += 3
                }
                wy += 4
            }
            x += w + Int(PixelNoise.unit(index, 25) * 3)
            index += 1
        }
    }

    private static func drawMoon(_ canvas: RasterCanvas, _ layout: StageLayout, level: Double, sky: Sky) {
        let r = Double(layout.height) * 0.07
        let cx = Double(layout.width) * 0.14, cy = Double(layout.height) * 0.17
        canvas.halo(cx, cy, r * 2.6, RGBColor(0xFFE9A8), 0.35 * level)
        // 큰 원 안에서 비켜 놓은 원을 뺀 칸만 칠해 초승달을 만든다. 하늘은 그대로 비친다.
        let bx = cx + r * 0.45, by = cy - r * 0.2, br = r * 0.88
        for y in Int(cy - r - 1)...Int(cy + r + 1) {
            for x in Int(cx - r - 1)...Int(cx + r + 1) {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let inMoon = (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r
                let inBite = (px - bx) * (px - bx) + (py - by) * (py - by) <= br * br
                if inMoon, !inBite { canvas.plot(x, y, RGBColor(0xFFE7A0), level) }
            }
        }
    }

    private static func drawSun(_ canvas: RasterCanvas, _ layout: StageLayout, level: Double, time: Double) {
        let r = Double(layout.height) * 0.06
        let cx = Double(layout.width) * 0.86, cy = Double(layout.height) * 0.18
        canvas.halo(cx, cy, r * 3.2, RGBColor(0xFFB347), 0.45 * level)
        for ray in 0..<10 {
            let angle = time * 0.4 + Double(ray) * .pi / 5
            for step in 0..<Int(r * 0.9) {
                let d = r * 1.3 + Double(step)
                canvas.glow(Int(cx + cos(angle) * d), Int(cy + sin(angle) * d), RGBColor(0xFFC861), 0.5 * level * (1 - Double(step) / (r * 0.9)))
            }
        }
        canvas.disc(cx, cy, r, RGBColor(0xFFC24A), level)
        canvas.disc(cx - r * 0.25, cy - r * 0.25, r * 0.45, RGBColor(0xFFE59A), level * 0.8)
        // 무대 전체에 따뜻한 빛이 돈다.
        canvas.add(0, 0, layout.width, layout.floorTop, RGBColor(0xFF9A3C), 0.05 * level)
    }

    private static func drawStarShower(_ canvas: RasterCanvas, _ layout: StageLayout, level: Double, time: Double) {
        let star = PixelGlyph.reaction(.star)
        for index in 0..<7 {
            let x = Int(PixelNoise.unit(index, 31) * Double(layout.width - 6))
            let y = 2 + Int(PixelNoise.unit(index, 32) * Double(layout.floorTop) * 0.4)
            let blink = 0.5 + 0.5 * sin(time * (2 + PixelNoise.unit(index, 33) * 3) + Double(index))
            canvas.glyph(star, x, y, alpha: level * (0.35 + 0.65 * blink))
        }
        // 2.6초마다 하나씩 별똥별이 대각선으로 지나간다.
        let period = 2.6
        let cycle = Int(time / period)
        let t = (time - Double(cycle) * period) / 0.9
        guard t < 1 else { return }
        let startX = PixelNoise.unit(cycle, 34) * Double(layout.width) * 0.7
        let startY = PixelNoise.unit(cycle, 35) * Double(layout.floorTop) * 0.25
        let headX = startX + t * Double(layout.width) * 0.35
        let headY = startY + t * Double(layout.floorTop) * 0.28
        for tail in 0..<14 {
            let fade = 1 - Double(tail) / 14
            canvas.glow(Int(headX) - tail, Int(headY - Double(tail) * 0.8), RGBColor(0xFFF3C4), level * fade * (1 - t * 0.4))
        }
    }

    // MARK: - 조명과 무대

    private static func lampXs(_ layout: StageLayout) -> [Int] {
        let count = 8
        let margin = layout.width / 10
        return (0..<count).map { margin + ($0 * (layout.width - margin * 2)) / (count - 1) }
    }

    private static func drawBeams(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette,
                                  energy: Double, hop: Double) {
        let lamps = lampXs(layout)
        let colors = [palette.primary, palette.secondary, palette.accent]
        guard input.live else {
            // 쉬는 무대는 작업등 둘만 켠다.
            for x in [lamps[2], lamps[5]] {
                canvas.beam(apexX: Double(x), apexY: layout.trussY + 3, bottomY: layout.floorTop + 2,
                            bottomCenter: Double(layout.centerX), halfWidth: Double(layout.width) * 0.05,
                            RGBColor(0xFFF1D6), 0.05)
            }
            return
        }
        let hook = input.hookLevel
        for (index, x) in lamps.enumerated() {
            let speed = 0.5 + PixelNoise.unit(index, 41) * 0.5
            let swing = sin(input.time * speed + Double(index) * 1.7 + Double(input.beatCount % 4) * 0.35)
            let bottom = Double(layout.centerX) + Double(x - layout.centerX) * 0.35 + swing * Double(layout.width) * 0.22
            let color = colors[(index + input.beatCount) % colors.count]
            let alpha = (0.07 + energy * 0.06 + hop * 0.07 + hook * 0.06) * (index % 2 == input.beatCount % 2 ? 1 : 0.7)
            canvas.beam(apexX: Double(x), apexY: layout.trussY + 3, bottomY: layout.floorBottom,
                        bottomCenter: bottom, halfWidth: Double(layout.width) * (0.035 + hook * 0.015),
                        color, alpha)
        }
        // 후렴에는 바닥에서 위로 쏘는 조명이 엇갈린다.
        if hook > 0.05 {
            for side in [-1.0, 1.0] {
                let baseX = Double(layout.centerX) + side * Double(layout.width) * 0.38
                let sweep = sin(input.time * 1.6 + side) * Double(layout.width) * 0.12
                canvas.beam(apexX: baseX, apexY: 2, bottomY: layout.floorTop, bottomCenter: baseX - side * Double(layout.width) * 0.2 + sweep,
                            halfWidth: Double(layout.width) * 0.03, palette.accent, 0.06 * hook)
            }
        }
    }

    private static func drawTruss(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette, hop: Double) {
        let y = layout.trussY
        let metal = RGBColor(0x2C2B38)
        let shine = RGBColor(0x55546A)
        canvas.fill(0, y, layout.width, 2, metal)
        canvas.span(0, layout.width - 1, y, shine, 0.6)
        // 트러스 사선 무늬
        var x = 0
        while x < layout.width {
            canvas.plot(x, y + 1, shine, 0.5)
            x += 4
        }
        let colors = [palette.primary, palette.secondary, palette.accent]
        for (index, lamp) in lampXs(layout).enumerated() {
            canvas.fill(lamp - 1, y + 2, 3, 2, RGBColor(0x1A1A22))
            let on = input.live ? (0.55 + hop * 0.45) : 0.25
            let color = input.live ? colors[(index + input.beatCount) % colors.count] : RGBColor(0xFFF1D6)
            canvas.fill(lamp - 1, y + 3, 3, 1, color, on)
            canvas.halo(Double(lamp) + 0.5, Double(y) + 3.5, 4, color, 0.5 * on)
        }
    }

    private static func drawScreen(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette, hop: Double) {
        let x = layout.screenX, y = layout.screenY, w = layout.screenW, h = layout.screenH
        canvas.fill(x - 2, y - 2, w + 4, h + 4, RGBColor(0x141420))
        canvas.fill(x, y, w, h, RGBColor(0x05050A))
        let pitch = 3
        let columns = max(1, (w - 2) / pitch)
        let rows = max(1, (h - 2) / pitch)
        let offsetX = x + (w - columns * pitch + 1) / 2
        let offsetY = y + (h - rows * pitch + 1) / 2
        let levels = input.spectrum.count == SpectrumMeter.bandCount ? input.spectrum : Array(repeating: 0, count: SpectrumMeter.bandCount)
        let strobe = input.live && !input.reduceMotion ? input.hookLevel * hop * 0.25 : 0
        // 반응 그림을 전광판 가운데 크게 띄운다.
        let glyph = input.reaction.map(PixelGlyph.large)
        let glyphW = glyph?.width ?? 9, glyphH = glyph?.height ?? 9
        let glyphScale = max(1, min((rows - 2) / glyphH, (columns - 2) / glyphW))
        let glyphCols = glyphW * glyphScale, glyphRows = glyphH * glyphScale
        let glyphLeft = (columns - glyphCols) / 2, glyphTop = (rows - glyphRows) / 2
        var glyphMask: [Int: RGBColor] = [:]
        if let glyph, input.reactionLevel > 0.05 {
            for dot in glyph.pixels {
                for sy in 0..<glyphScale {
                    for sx in 0..<glyphScale {
                        let cx = glyphLeft + dot.x * glyphScale + sx
                        let cy = glyphTop + dot.y * glyphScale + sy
                        glyphMask[cy * columns + cx] = dot.color
                    }
                }
            }
        }
        let glyphShown = !glyphMask.isEmpty
        let barDim = (glyphShown ? 1 - 0.6 * input.reactionLevel : 1) * (1 - 0.75 * input.splash)
        // 쉬는 동안에는 전광판 칸으로 이름을 쓴다. 칸이 모자라면 짧게 쓴다.
        let idleWord = RasterCanvas.textWidth("CLAUDE FM") <= columns - 2 ? "CLAUDE FM" : "FM"
        var idleMask = Set<Int>()
        if !input.live, RasterCanvas.textWidth(idleWord) <= columns, rows >= 5 {
            let textCols = RasterCanvas.textWidth(idleWord)
            let left = (columns - textCols) / 2, top = (rows - 5) / 2
            var cursor = left
            for char in idleWord {
                if char == " " {
                    cursor += 3
                    continue
                }
                guard let shape = PixelFont.glyphs[char] else { continue }
                for (row, line) in shape.enumerated() {
                    for (col, cell) in line.enumerated() where cell == "#" {
                        idleMask.insert((top + row) * columns + cursor + col)
                    }
                }
                cursor += (shape.first?.count ?? 3) + 1
            }
        }
        for column in 0..<columns {
            // 여덟 대역을 열 너비에 맞춰 매끄럽게 잇는다.
            let position = Double(column) / Double(max(1, columns - 1)) * Double(SpectrumMeter.bandCount - 1)
            let lower = Int(position)
            let upper = min(SpectrumMeter.bandCount - 1, lower + 1)
            let mix = position - Double(lower)
            var level = levels[lower] * (1 - mix) + levels[upper] * mix
            if !input.live { level = 0 }
            let lit = Int((level * Double(rows)).rounded())
            for row in 0..<rows {
                let cellX = offsetX + column * pitch
                let cellY = offsetY + row * pitch
                let fromBottom = rows - 1 - row
                var color = RGBColor(0x1C1C2A)
                var alpha = 0.55
                if fromBottom < lit {
                    let t = Double(fromBottom) / Double(max(1, rows - 1))
                    color = t < 0.5 ? palette.secondary.mixed(with: palette.primary, t * 2) : palette.primary.mixed(with: palette.accent, (t - 0.5) * 2)
                    alpha = 0.85 * barDim
                }
                if let glyphColor = glyphMask[row * columns + column] {
                    color = glyphColor.mixed(with: .white, hop * 0.25)
                    alpha = input.reactionLevel * (0.8 + 0.2 * hop) * (1 - 0.75 * input.splash)
                }
                if idleMask.contains(row * columns + column) {
                    color = RGBColor.coral
                    alpha = 0.55 + 0.35 * sin(input.time * 1.4)
                }
                canvas.fill(cellX, cellY, 2, 2, color, alpha)
                if glyphMask[row * columns + column] != nil {
                    canvas.add(cellX - 1, cellY - 1, 4, 4, color, 0.12 * input.reactionLevel)
                }
                if strobe > 0.01 { canvas.add(cellX, cellY, 2, 2, .white, strobe) }
            }
        }
        // 전광판 테두리가 박마다 반짝인다.
        let rim = input.live ? 0.25 + hop * 0.35 : 0.12
        canvas.span(x - 2, x + w + 1, y - 2, palette.primary, rim)
        canvas.span(x - 2, x + w + 1, y + h + 1, palette.primary, rim * 0.6)
    }

    /// 전광판을 가리지 않도록 양옆에 하나씩 매단다.
    private static func drawMirrorball(_ canvas: RasterCanvas, _ layout: StageLayout, time: Double, hop: Double) {
        let gap = max(8, layout.width / 22)
        for (index, x) in [layout.screenX - gap, layout.screenX + layout.screenW + gap - 1].enumerated() {
            drawMirrorball(canvas, layout, x: x, time: time + Double(index) * 1.7, hop: hop, seed: index)
        }
    }

    private static func drawMirrorball(_ canvas: RasterCanvas, _ layout: StageLayout, x centerX: Int, time: Double, hop: Double, seed: Int) {
        let cx = Double(centerX) + 0.5, r = max(3.5, Double(layout.height) * 0.03)
        let cy = Double(layout.trussY) + 8 + r
        for y in layout.trussY + 2..<Int(cy - r) { canvas.plot(centerX, y, RGBColor(0x8A8FA0), 0.8) }
        let y0 = Int(cy - r), y1 = Int(cy + r)
        for y in y0...y1 {
            for x in Int(cx - r)...Int(cx + r) {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                let facet = (x + Int(time * 6) + y * 2) % 3
                let base = facet == 0 ? RGBColor(0xF2F5FF) : facet == 1 ? RGBColor(0xA7AEC4) : RGBColor(0x6C7286)
                canvas.plot(x, y, base)
            }
        }
        canvas.halo(cx, cy, r * 2.2, RGBColor(0xDDE6FF), 0.25 + hop * 0.2)
        // 미러볼이 흩뿌리는 빛 조각
        for index in 0..<16 {
            let angle = time * 0.5 + Double(index) * 2.399
            let distance = (0.12 + PixelNoise.unit(index + seed * 31, 51) * 0.6) * Double(layout.width) * 0.45
            let x = Int(cx + cos(angle) * distance)
            let y = Int(cy + 6 + abs(sin(angle * 1.3)) * distance * 0.55)
            let color = ClawdPixels.discoColors[index % ClawdPixels.discoColors.count]
            canvas.glow(x, y, color, 0.55 + hop * 0.35)
            canvas.glow(x + 1, y, color, 0.25)
        }
    }

    private static func drawSpeakers(_ canvas: RasterCanvas, _ layout: StageLayout, bass: Double, hop: Double) {
        let boxW = max(10, layout.width / 18), boxH = max(9, layout.height / 16)
        let lefts = [layout.screenX - boxW - max(6, layout.width / 30), layout.screenX + layout.screenW + max(6, layout.width / 30)]
        for left in lefts {
            for level in 0..<2 {
                let top = layout.floorTop - boxH * (level + 1)
                canvas.fill(left, top, boxW, boxH - 1, RGBColor(0x15141C))
                canvas.span(left, left + boxW - 1, top, RGBColor(0x34333F), 0.9)
                let cx = Double(left) + Double(boxW) / 2, cy = Double(top) + Double(boxH) * 0.55
                let pulse = (bass * 1.2 + hop * 0.6) * (level == 0 ? 1 : 0.7)
                let r = Double(boxH) * 0.32 + pulse
                canvas.disc(cx, cy, r + 1, RGBColor(0x2A2933))
                canvas.disc(cx, cy, r, RGBColor(0x0B0B10))
                canvas.disc(cx, cy, max(1, r * 0.35), RGBColor(0x3A3946))
                canvas.plot(Int(cx) + 2, top + 2, RGBColor(0x55546A))
            }
        }
    }

    private static func drawFloor(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette, hop: Double) {
        let top = layout.floorTop, bottom = layout.floorBottom
        canvas.fill(0, top, layout.width, bottom - top, RGBColor(0x1A1626))
        // 박마다 바닥 타일이 번갈아 켜진다.
        let tileW = max(8, layout.width / 26)
        let tileCount = layout.width / tileW + 1
        let colors = [palette.primary, palette.secondary, palette.accent]
        for tile in 0..<tileCount {
            let x = tile * tileW
            canvas.fill(x, top + 1, tileW - 1, bottom - top - 2, RGBColor(0x231E33))
            guard input.live else { continue }
            let lit = (tile + input.beatCount) % 3 == 0
            if lit {
                let color = colors[(tile / 3 + input.beatCount) % colors.count]
                canvas.add(x, top + 1, tileW - 1, bottom - top - 2, color, 0.18 + hop * 0.32 + input.hookLevel * 0.12)
            }
        }
        canvas.span(0, layout.width - 1, top, palette.primary, input.live ? 0.55 + hop * 0.3 : 0.2)
        canvas.fill(0, bottom, layout.width, 2, RGBColor(0x0B0A12))
        // 관객석 바닥
        canvas.fill(0, bottom + 2, layout.width, layout.height - bottom - 2, RGBColor(0x0A0911))
    }

    private static func drawFireJets(_ canvas: RasterCanvas, _ layout: StageLayout, level: Double, time: Double, hop: Double) {
        let jetHeight = Double(layout.height) * 0.2 * (0.45 + hop * 0.55) * level
        for side in [0.07, 0.93] {
            let baseX = Double(layout.width) * side
            let rows = Int(jetHeight)
            guard rows > 2 else { continue }
            for step in 0..<rows {
                let t = Double(step) / Double(rows)
                let flicker = PixelNoise.signed(Int(time * 30) + step, Int(side * 100))
                let half = max(0.5, (1 - t) * 5 + flicker)
                let color = t < 0.35 ? RGBColor(0xFFE27A) : t < 0.7 ? RGBColor(0xFF8A2B) : RGBColor(0xE8402A)
                let y = layout.floorTop - step
                canvas.span(Int(baseX - half + flicker), Int(baseX + half + flicker), y, color, level * (1 - t * 0.5), additive: false)
            }
            canvas.halo(baseX, Double(layout.floorTop) - jetHeight * 0.4, jetHeight * 0.6, RGBColor(0xFF7A2B), 0.35 * level)
        }
    }

    private static func drawClawd(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette, hop: Double) {
        let s = layout.spriteScale
        let originX = layout.centerX - 8 * s
        let originY = layout.floorTop - 13 * s
        // 발밑에 박을 따라 숨 쉬는 빛
        canvas.halo(Double(layout.centerX), Double(layout.floorTop) + 1, Double(9 * s),
                    palette.primary, input.live ? 0.22 + hop * 0.22 : 0.1)
        ClawdPixels.render(frame: input.spriteFrame, playing: input.playing, dance: input.pose, noteColor: .white,
                           accent: input.accent, decorations: false) { x, y, color, alpha in
            canvas.fill(originX + x * s, originY + y * s, s, s, color, alpha)
        }
    }

    private static func drawFog(_ canvas: RasterCanvas, _ layout: StageLayout, time: Double, palette: MoodPalette, live: Bool) {
        let y = Double(layout.floorTop) + 1
        let tint = palette.primary.mixed(with: .white, 0.6)
        for index in 0..<6 {
            let speed = (index % 2 == 0 ? 1.0 : -1.0) * (3 + PixelNoise.unit(index, 61) * 4)
            var x = (PixelNoise.unit(index, 62) * Double(layout.width) + time * speed).truncatingRemainder(dividingBy: Double(layout.width + 60))
            if x < 0 { x += Double(layout.width + 60) }
            canvas.halo(x - 30, y + PixelNoise.signed(index, 63) * 3, Double(layout.height) * 0.09, tint, live ? 0.06 : 0.03)
        }
    }

    // MARK: - 관객

    private static func drawCrowd(_ canvas: RasterCanvas, _ layout: StageLayout, input: StageInput, palette: MoodPalette, hop: Double) {
        let mood = input.pose.mood
        let hook = input.hookLevel
        let jump: Double
        if !input.live {
            jump = 0
        } else if hook > 0.5 || mood == .drive {
            jump = 3
        } else if mood == .calm {
            jump = 1
        } else {
            jump = 2
        }
        let calm = input.live && mood == .calm && input.cheer < 0.3
        let stickColors = [palette.primary, palette.secondary, palette.accent]
        // 후렴에는 네 박마다 응원봉 색이 다 같이 바뀐다.
        let stickColor = hook > 0.5 ? stickColors[(input.beatCount / 4) % stickColors.count] : palette.primary
        let swing = cos(.pi * (Double(input.beatCount % 2) + input.beatPhase))

        for row in 0..<2 {
            let headW = row == 0 ? 5 : 7
            let headH = row == 0 ? 4 : 6
            let spacing = row == 0 ? max(7, layout.width / 34) : max(10, layout.width / 24)
            let baseY = layout.crowdTop + (row == 0 ? 2 : layout.height / 14)
            let body = row == 0 ? RGBColor(0x120E1C) : RGBColor(0x08070D)
            let count = layout.width / spacing + 2
            for index in 0..<count {
                let seed = index * 7 + row * 1_000
                let x = index * spacing - spacing / 2 + Int(PixelNoise.signed(seed, 71) * Double(spacing) * 0.3)
                let personal = 0.5 + PixelNoise.unit(seed, 72) * 0.8
                // 환호할 때는 박과 상관없이 저마다의 박자로 펄쩍펄쩍 뛴다.
                let leap = input.cheer * abs(sin(input.time * 9 + PixelNoise.unit(seed, 76) * 6.28)) * 4
                // 후렴에서는 관객석에 파도가 왼쪽에서 오른쪽으로 지나간다.
                let wavePosition = Double(x) / Double(max(1, layout.width)) * 2 * .pi - input.time * 3.2
                let crest = hook > 0.5 ? max(0, sin(wavePosition)) : 0
                let surge = crest * crest * 4 * hook
                let bob = -Int(max(hop * jump * personal, leap, surge).rounded())
                let headY = baseY + bob + Int(PixelNoise.unit(seed, 73) * 2)
                // 응원봉·휴대폰 불빛을 든 손
                let holds = PixelNoise.unit(seed, 74) < (hook > 0.5 || input.cheer > 0.3 ? 0.92 : calm ? 0.5 : 0.42)
                if input.live || input.cheer > 0.05, holds {
                    let hand = x + (PixelNoise.unit(seed, 75) > 0.5 ? headW + 1 : -2)
                    let raise = (hook > 0.5 ? 10 : 7) + Int((crest * 3 * hook).rounded())
                    if calm {
                        let sway = Int((sin(input.time * 1.1 + Double(index) * 0.35) * 2).rounded())
                        let tipY = headY - raise + 2
                        canvas.fill(hand + sway, tipY, 1, 3, RGBColor(0x2A2A33))
                        canvas.glow(hand + sway, tipY, RGBColor(0xFFF4D6), 0.9)
                        canvas.halo(Double(hand + sway) + 0.5, Double(tipY) + 0.5, 2.5, RGBColor(0xFFF4D6), 0.16)
                    } else {
                        let lean = Int((swing * 3).rounded())
                        let tipX = hand + lean
                        let tipY = headY - raise
                        // 막대
                        for step in 0..<raise {
                            let t = Double(step) / Double(raise)
                            canvas.plot(hand + Int((Double(lean) * t).rounded()), headY - step, RGBColor(0x3B3A46))
                        }
                        canvas.fill(tipX, tipY - 1, 1, 3, stickColor)
                        canvas.glow(tipX, tipY, .white, 0.25 + hop * 0.5)
                        canvas.halo(Double(tipX) + 0.5, Double(tipY) + 0.5, 2.5 + hop * 1.2, stickColor, 0.16 + hop * 0.14 + hook * 0.08)
                    }
                }
                // 머리와 어깨
                canvas.fill(x + 1, headY, headW - 2, 1, body)
                canvas.fill(x, headY + 1, headW, headH - 1, body)
                canvas.fill(x - 2, headY + headH, headW + 4, layout.height - headY - headH, body)
                // 무대 빛이 머리 윗선에 걸린다.
                let rim = input.live ? 0.35 + hop * 0.25 : 0.1
                canvas.span(x + 1, x + headW - 2, headY, palette.primary, rim)
            }
        }
    }

    // MARK: - 가사 반응 날씨

    private static func drawWeather(_ canvas: RasterCanvas, _ layout: StageLayout, reaction: LyricReaction, level: Double, time: Double) {
        switch reaction {
        case .love:
            let heart = PixelGlyph.reaction(.love)
            for index in 0..<9 {
                let period = 3.4 + PixelNoise.unit(index, 81) * 1.6
                let u = (time / period + PixelNoise.unit(index, 82)).truncatingRemainder(dividingBy: 1)
                let x = Int(PixelNoise.unit(index, 83) * Double(layout.width - 8) + sin(time * 1.3 + Double(index)) * 5)
                let y = layout.crowdTop - Int(u * Double(layout.height) * 0.55)
                let fade = u < 0.15 ? u / 0.15 : u > 0.72 ? max(0, (1 - u) / 0.28) : 1
                canvas.glyph(heart, x, y, pixel: index % 3 == 0 ? 2 : 1, alpha: level * fade)
            }
        case .tears:
            let count = layout.width * layout.height / 260
            for index in 0..<count {
                let speed = 150 + PixelNoise.unit(index, 84) * 70
                let y = (PixelNoise.unit(index, 85) * Double(layout.height) + time * speed).truncatingRemainder(dividingBy: Double(layout.height))
                let x = (PixelNoise.unit(index, 86) * Double(layout.width) + y * 0.25).truncatingRemainder(dividingBy: Double(layout.width))
                canvas.fill(Int(x), Int(y), 1, 3, RGBColor(0x9CCBFF), 0.45 * level)
            }
        case .snow:
            let count = layout.width * layout.height / 130
            for index in 0..<count {
                let speed = 10 + PixelNoise.unit(index, 87) * 16
                let y = (PixelNoise.unit(index, 88) * Double(layout.height) + time * speed).truncatingRemainder(dividingBy: Double(layout.height))
                var x = PixelNoise.unit(index, 89) * Double(layout.width) + sin(time * 0.9 + Double(index)) * 4
                x = x.truncatingRemainder(dividingBy: Double(layout.width))
                let big = PixelNoise.unit(index, 90) > 0.82
                canvas.fill(Int(x), Int(y), big ? 2 : 1, big ? 2 : 1, RGBColor(0xF4FAFF), 0.85 * level)
            }
        case .flower:
            for index in 0..<30 {
                let speed = 18 + PixelNoise.unit(index, 91) * 18
                let y = (PixelNoise.unit(index, 92) * Double(layout.height) + time * speed).truncatingRemainder(dividingBy: Double(layout.height))
                var x = PixelNoise.unit(index, 93) * Double(layout.width) + sin(time * 1.2 + Double(index)) * 8 + time * 9
                x = x.truncatingRemainder(dividingBy: Double(layout.width))
                let flip = Int(time * 4 + Double(index)) % 2 == 0
                canvas.fill(Int(x), Int(y), flip ? 2 : 1, flip ? 1 : 2, index % 4 == 0 ? RGBColor(0xFFE0EE) : RGBColor(0xFF9CC8), 0.9 * level)
            }
        case .fire:
            for index in 0..<16 {
                let period = 1.6 + PixelNoise.unit(index, 94)
                let u = (time / period + PixelNoise.unit(index, 95)).truncatingRemainder(dividingBy: 1)
                let side = index % 2 == 0 ? 0.07 : 0.93
                let x = Int(Double(layout.width) * side + PixelNoise.signed(index, 96) * 10 + sin(time * 3 + Double(index)) * 2)
                let y = layout.floorTop - Int(u * Double(layout.height) * 0.42)
                canvas.glow(x, y, u < 0.5 ? RGBColor(0xFFD25A) : RGBColor(0xFF6A2A), level * (1 - u))
            }
        case .star:
            let star = PixelGlyph.reaction(.star)
            for index in 0..<5 {
                let period = 2.8 + PixelNoise.unit(index, 97)
                let u = (time / period + PixelNoise.unit(index, 98)).truncatingRemainder(dividingBy: 1)
                let x = Int(PixelNoise.unit(index, 99) * Double(layout.width - 6))
                let y = layout.crowdTop - Int(u * Double(layout.height) * 0.4)
                canvas.glyph(star, x, y, alpha: level * (1 - u))
            }
        case .moon, .sun:
            break
        }
    }

    private static func drawConfetti(_ canvas: RasterCanvas, _ item: StageBurst) {
        for piece in item.burst.pieces(at: item.age) {
            if let glyph = piece.glyph {
                canvas.glyph(PixelGlyph.reaction(glyph), Int(piece.x) - 2, Int(piece.y) - 2, alpha: piece.alpha)
            } else {
                let size = max(1, Int(piece.size.rounded()))
                let thin = piece.face < 0.35
                canvas.fill(Int(piece.x), Int(piece.y), thin ? 1 : size, size, piece.color, piece.alpha)
            }
        }
    }
}
