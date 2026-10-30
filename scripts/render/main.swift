import AppKit

// ClawdSprite 를 PNG 로 뽑는다. 앱 아이콘과 미리보기 시트에 쓴다.
//   render icon <out.iconset>   앱 아이콘 iconset
//   render sheet <out.png>      재생/정지 프레임 미리보기

func png(_ size: NSSize, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .none
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: render icon <out.iconset> | render sheet <out.png>")
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
let ink = NSColor(srgbRed: 0.16, green: 0.15, blue: 0.13, alpha: 1)
let paper = NSColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1)

switch args[1] {
case "icon":
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
        for s in scales {
            let side = CGFloat(points * s)
            let data = png(NSSize(width: side, height: side)) {
                let inset = side * 0.1
                let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
                paper.setFill()
                NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()
                let scale = (tile.width * 0.82 / ClawdSprite.canvas.width).rounded(.down)
                let sprite = NSSize(width: ClawdSprite.canvas.width * scale, height: ClawdSprite.canvas.height * scale)
                let origin = CGPoint(x: (tile.midX - sprite.width / 2).rounded(), y: (tile.midY - sprite.height / 2).rounded())
                ClawdSprite.draw(frame: 4, playing: true, scale: max(scale, 1), origin: origin, noteColor: ink)
            }
            let name = s == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try data.write(to: out.appendingPathComponent(name))
        }
    }
case "sheet":
    let scale: CGFloat = 8, gap: CGFloat = 16, columns = 8
    let cell = NSSize(width: ClawdSprite.canvas.width * scale, height: ClawdSprite.canvas.height * scale)
    let rows: [(Bool, NSColor, NSColor)] = [
        (true, paper, ink), (true, NSColor(white: 0.12, alpha: 1), .white), (false, paper, ink),
    ]
    let size = NSSize(width: CGFloat(columns) * (cell.width + gap) + gap,
                      height: CGFloat(rows.count) * (cell.height + gap) + gap)
    let data = png(size) {
        for (r, (playing, background, note)) in rows.enumerated() {
            let y = gap + CGFloat(r) * (cell.height + gap)
            background.setFill()
            NSRect(x: 0, y: y - gap / 2, width: size.width, height: cell.height + gap).fill()
            for c in 0..<columns {
                let x = gap + CGFloat(c) * (cell.width + gap)
                ClawdSprite.draw(frame: c * 2 % ClawdSprite.frameCount + (c * 2 >= 8 ? 1 : 0), playing: playing,
                                 scale: scale, origin: CGPoint(x: x, y: y), noteColor: note)
            }
        }
    }
    try data.write(to: out)
default:
    print("unknown mode \(args[1])")
    exit(1)
}
