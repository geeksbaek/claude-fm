import SwiftUI

struct PopoverView: View {
    @ObservedObject var player: RadioPlayer
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoView(player: player)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: Animation.frameInterval)) { context in
                    Image(nsImage: ClawdSprite.image(frame: Animation.frame(at: context.date),
                                                     playing: player.isPlaying, scale: 2))
                        .id(colorScheme)
                }
                .frame(width: ClawdSprite.canvas.width * 2, height: ClawdSprite.canvas.height * 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: player.toggle) {
                    Image(systemName: playButtonSymbol)
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(player.isPlaying ? "일시정지" : "재생")
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...100)
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("YouTube에서 열기") { NSWorkspace.shared.open(RadioPlayer.watchURL) }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 348)
    }

    private var playButtonSymbol: String {
        switch player.status {
        case .playing, .buffering: return "pause.circle.fill"
        case .failed: return "arrow.clockwise.circle.fill"
        default: return "play.circle.fill"
        }
    }

    private var statusText: String {
        switch player.status {
        case .loading: return "연결 중…"
        case .playing: return "재생 중 · LIVE"
        case .paused: return "일시정지"
        case .buffering: return "버퍼링…"
        case .ended: return "방송이 끝났어요"
        case .failed(let message): return message
        }
    }

    private var statusColor: Color {
        switch player.status {
        case .playing: return .red
        case .failed: return .orange
        default: return .secondary
        }
    }
}

/// 팝오버를 닫았다 열어도 재생이 끊기지 않도록 플레이어의 WKWebView 를 빌려 와 보여 준다.
struct VideoView: NSViewRepresentable {
    let player: RadioPlayer

    func makeNSView(context: Context) -> NSView {
        let container = VideoContainer()
        container.player = player
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        player.videoContainer = container
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    final class VideoContainer: NSView {
        weak var player: RadioPlayer?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { player?.attachVideo() }
        }
    }
}

/// 메뉴바와 팝오버가 같은 박자로 움직이도록 시각에서 프레임을 계산한다.
enum Animation {
    static let frameInterval: TimeInterval = 0.15

    static func frame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameInterval) % ClawdSprite.frameCount
    }
}
