import AppKit

/// 메뉴바·팝오버에 쓰는 Clawd 그림. 칸 그리기는 `ClawdPixels` 가 하고, 여기서는 AppKit 으로 칠한다.
enum ClawdSprite {
    static let canvas = NSSize(width: ClawdPixels.width, height: ClawdPixels.height)
    static let frameCount = ClawdPixels.frameCount

    /// 메뉴바용 이미지. 음표 색은 그릴 때의 외관(라이트/다크)을 따른다.
    static func image(frame: Int, playing: Bool, dance: DancePose = .idle, scale: CGFloat = 1,
                      accent: SpriteAccent = .none) -> NSImage {
        let size = NSSize(width: canvas.width * scale, height: canvas.height * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(frame: frame, playing: playing, dance: dance, scale: scale, origin: .zero, noteColor: .labelColor,
                 accent: accent)
            return true
        }
        image.accessibilityDescription = "Claude FM"
        return image
    }

    /// 뒤집힌(flipped) 좌표계에서 스프라이트를 그린다.
    /// `accent` 가 있으면 음표 대신 가사 반응 그림을 띄운다. `decorations` 를 끄면 미러볼 장식을 빼고 그린다.
    static func draw(frame: Int, playing: Bool, dance: DancePose = .idle, scale: CGFloat, origin: CGPoint, noteColor: NSColor,
                     accent: SpriteAccent = .none, decorations: Bool = true) {
        // 라벨색처럼 외관에 따라 바뀌는 색은 지금 그리는 외관으로 풀어서 쓴다.
        let resolved = noteColor.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let ink = RGBColor(r: Double(resolved.redComponent), g: Double(resolved.greenComponent), b: Double(resolved.blueComponent))
        ClawdPixels.render(frame: frame, playing: playing, dance: dance, noteColor: ink, accent: accent,
                           decorations: decorations) { x, y, color, alpha in
            let x0 = (origin.x + CGFloat(x) * scale).rounded(), x1 = (origin.x + CGFloat(x + 1) * scale).rounded()
            let y0 = (origin.y + CGFloat(y) * scale).rounded(), y1 = (origin.y + CGFloat(y + 1) * scale).rounded()
            color.nsColor(alpha: CGFloat(alpha)).setFill()
            NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).fill()
        }
    }
}

extension RGBColor {
    func nsColor(alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: alpha)
    }
}
