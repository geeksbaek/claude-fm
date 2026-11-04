import SwiftUI

struct PopoverView: View {
    @ObservedObject var player: RadioPlayer
    @ObservedObject var rhythm: RhythmDance
    @ObservedObject var singing: LyricSinging
    @ObservedObject var caster: StageCaster
    /// 팝오버를 닫고 무대 창을 연다.
    let openStage: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoView(player: player)
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: Animation.danceInterval)) { context in
                    Image(nsImage: ClawdSprite.image(frame: Animation.frame(at: context.date), playing: player.isPlaying,
                                                     dance: dancePose, scale: 2, accent: accent))
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
                    if let song = nowSongText {
                        Text(song)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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

            // 팝오버가 열려 있으면 말풍선이 숨으므로, 지금 부르는 줄을 여기서 이어 부른다.
            if singing.nowTitle != nil {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                    PopoverLyricLine(scene: singing.scene(at: ProcessInfo.processInfo.systemUptime),
                                     karaoke: singing.isKaraokeEnabled,
                                     lyricsWanted: singing.wantsLyrics,
                                     playing: singing.externalSongPlaying)
                }
                .frame(height: 24)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...100)
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                toggleRow("가사 말풍선", symbol: singing.isBubbleEnabled ? "text.bubble.fill" : "text.bubble",
                          isOn: $singing.isBubbleEnabled)
                toggleRow("말풍선 파장 필링 효과", symbol: singing.isFeelingEnabled ? "waveform.path.ecg" : "waveform.path",
                          isOn: $singing.isFeelingEnabled)
                    .disabled(!singing.isBubbleEnabled)
                toggleRow("노래방 채움", symbol: "music.mic", isOn: $singing.isKaraokeEnabled)
                toggleRow("가사 반응과 후렴 폭죽", symbol: singing.isReactionEnabled ? "sparkles" : "sparkle",
                          isOn: $singing.isReactionEnabled)
                if singing.hasSyncedLyrics {
                    syncRow
                }
            }

            if rhythm.needsPermission {
                Button("시스템 오디오 권한 열기…") { RhythmDance.openSettings() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }

            if let today = rhythm.today.summary(on: Date()) {
                Label(today, systemImage: "music.quarternote.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // TV 로 보내는 동안에는 어디로 보내는지와 소리가 어디서 나는지 적는다.
            if let line = caster.statusLine {
                Label(line, systemImage: caster.isCasting ? "tv.fill" : "tv")
                    .font(.system(size: 11))
                    .foregroundStyle(caster.isActive ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: openStage) {
                    Label("무대", systemImage: "music.note.tv")
                }
                .help("Clawd 의 콘서트 무대를 엽니다")
                Button { caster.popUpMenuAtMouse() } label: {
                    Label("TV", systemImage: caster.isActive ? "tv.fill" : "tv")
                }
                .help(caster.isActive ? caster.menuTitle : "같은 Wi-Fi 의 크롬캐스트로 무대를 보냅니다")
                Spacer()
                Button("YouTube에서 열기") { NSWorkspace.shared.open(RadioPlayer.watchURL) }
                Button("종료") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 348)
    }

    private func toggleRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    /// 블루투스 헤드폰처럼 소리가 늦게 들리면 가사를 늦춘다.
    private var syncRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "metronome")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("가사 싱크")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button { singing.nudgeSync(by: -0.1) } label: {
                Image(systemName: "minus.circle")
            }
            .help("가사를 0.1초 빠르게")
            Button { singing.nudgeSync(by: 0) } label: {
                Text(syncText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(minWidth: 46)
            }
            .help("처음으로 되돌리기")
            Button { singing.nudgeSync(by: 0.1) } label: {
                Image(systemName: "plus.circle")
            }
            .help("가사를 0.1초 늦게")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private var syncText: String {
        let value = singing.syncOffset
        if abs(value) < 0.05 { return "0.0초" }
        return String(format: "%@%.1f초", value > 0 ? "+" : "−", abs(value))
    }

    /// 후렴에서는 팝오버의 Clawd 도 두 팔을 든다.
    private var dancePose: DancePose {
        var pose = rhythm.pose()
        if accent.hook, pose.active { pose.style = .handsUp }
        return pose
    }

    private var accent: SpriteAccent {
        let accent = singing.spriteAccent
        return SpriteAccent(reaction: accent.reaction, hook: accent.hook)
    }

    private var nowSongText: String? {
        guard let title = singing.nowTitle else { return nil }
        if let artist = singing.nowArtist { return "♪ \(title) · \(artist)" }
        return "♪ \(title)"
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
        case .playing: return withTempo("재생 중 · LIVE")
        case .paused: return pausedText
        case .buffering: return "버퍼링…"
        case .ended: return "방송이 끝났어요"
        case .failed(let message): return message
        }
    }

    private var pausedText: String {
        if let caption = rhythm.mood.caption { return withTempo(caption) }
        if rhythm.needsPermission { return "춤추려면 시스템 오디오 권한이 필요해요" }
        return "일시정지"
    }

    /// 박을 잡았으면 빠르기를 붙인다.
    private func withTempo(_ text: String) -> String {
        guard let bpm = rhythm.bpm else { return text }
        return "\(text) · ♩ \(bpm)"
    }

    private var statusColor: Color {
        switch player.status {
        case .playing: return .red
        case .failed: return .orange
        default: return .secondary
        }
    }
}

/// 팝오버 안의 가사 한 줄. 노래방처럼 부른 만큼 코랄로 채우고, 간주에는 다음 줄을 흐리게 미리 보여 준다.
struct PopoverLyricLine: View {
    let scene: LyricPerformance?
    let karaoke: Bool
    /// 말풍선이나 무대가 켜져 있어 가사를 찾는 중인지.
    var lyricsWanted = true
    /// 다른 앱에서 노래가 실제로 흐르는 중인지.
    var playing = true

    private static let sung = Color(nsColor: NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1))

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            lyric
            // 곡이 얼마나 흘렀는지 가는 막대로. 길이를 몰라도 자리는 지켜 글이 들썩이지 않게 한다.
            let progress = scene?.progress(at: ProcessInfo.processInfo.systemUptime)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    if let progress {
                        Capsule().fill(Self.sung.opacity(0.85))
                            .frame(width: max(2, proxy.size.width * CGFloat(progress)))
                    }
                }
            }
            .frame(height: 2)
        }
    }

    @ViewBuilder
    private var lyric: some View {
        if let line = shown(scene) {
            HStack(spacing: 6) {
                Text(line.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Self.sung)
                if let progress = line.progress {
                    Text(line.text)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Text(line.text)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundStyle(Self.sung)
                                    .frame(width: proxy.size.width, alignment: .leading)
                                    .mask(alignment: .leading) {
                                        Rectangle().frame(width: proxy.size.width * Self.widthFraction(line.text, progress))
                                    }
                            }
                        }
                } else {
                    Text(line.text)
                        .font(.system(size: 12, weight: line.dim ? .regular : .semibold))
                        .foregroundStyle(line.dim ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 글자 수로 센 채움을 이 줄 글꼴의 폭 비율로 바꾼다. 띄어쓰기에서는 채움이 머물지 않는다.
    private static func widthFraction(_ text: String, _ progress: Double) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let measure: (String) -> Double = { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
        let full = measure(text)
        guard full > 0 else { return CGFloat(progress) }
        return CGFloat(min(1, KaraokeText.sungWidth(text, progress: progress, measure: measure) / full))
    }

    private struct Shown {
        var icon: String
        var text: String
        var progress: Double?
        var dim: Bool
    }

    /// 줄을 부르는 동안은 그 줄을, 아니면 지금 상태를 흐리게 보여 준다.
    private func shown(_ scene: LyricPerformance?) -> Shown? {
        guard let scene else {
            if !playing { return Shown(icon: "♪", text: "잠시 멈췄어요", progress: nil, dim: true) }
            return Shown(icon: "♪", text: lyricsWanted ? "가사를 찾는 중…" : "가사 말풍선을 켜면 여기서도 따라 불러요",
                         progress: nil, dim: true)
        }
        let cue = scene.cue
        if !lyricsWanted {
            return Shown(icon: "♪", text: "가사 말풍선을 켜면 여기서도 따라 불러요", progress: nil, dim: true)
        }
        if cue.isTitle { return Shown(icon: "♪", text: "전주가 흐르는 중", progress: nil, dim: true) }
        if cue.isHumming { return Shown(icon: "♪", text: "가사를 몰라서 흥얼거리는 중", progress: nil, dim: true) }
        if let recap = cue.recap { return Shown(icon: "♪", text: recap.headline + " · " + recap.caption, progress: nil, dim: true) }
        if cue.isInterlude {
            return Shown(icon: "♪", text: cue.next.map { "다음: " + $0 } ?? "간주가 흐르는 중", progress: nil, dim: true)
        }
        let elapsed = scene.clock?.elapsed(at: ProcessInfo.processInfo.systemUptime)
        let progress = karaoke ? elapsed.flatMap { cue.progress(at: $0) } : nil
        return Shown(icon: "♪", text: cue.current, progress: progress, dim: false)
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
