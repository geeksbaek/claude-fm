import AppKit
import WebKit

/// 보이지 않는 WKWebView 에서 YouTube IFrame Player 로 Claude FM 라이브를 재생한다.
@MainActor
final class RadioPlayer: NSObject, ObservableObject {
    enum Status: Equatable {
        case loading, playing, paused, buffering, ended
        case failed(String)
    }

    static let videoID = "tRsQsTMvPNg"
    /// 영상이 내려가면 채널의 현재 라이브로 넘어간다.
    static let channelID = "UCV03SRZXJEz-hchIAogeJOg"
    static let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    /// YouTube 는 Referer 없는 임베드를 거부(오류 153)하므로 https 출처를 붙여 로드한다.
    private static let pageOrigin = "https://localhost"

    @Published private(set) var status: Status = .loading
    @Published private(set) var title = "Claude FM"
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            run("fm.setVolume(\(Int(volume)))")
        }
    }

    let webView: WKWebView
    /// 웹뷰가 창에 붙어 있지 않으면 페이지가 hidden 이 되어 YouTube 가 재생을 시작하지 않는다.
    /// 팝오버가 닫혀 있는 동안에는 투명하게 띄워 둔 이 창에 웹뷰를 맡겨 둔다.
    private let hostWindow: NSWindow
    weak var videoContainer: NSView?
    private var triedChannelLive = false
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil

    var isPlaying: Bool { status == .playing }

    override init() {
        let saved = UserDefaults.standard.object(forKey: "volume") as? Double
        volume = saved ?? 60

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        // 투명한 호스트 창은 가려진 것으로 판정되므로 가림 감지를 끈다(비공개 API라 있을 때만).
        if webView.responds(to: NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")) {
            webView.setValue(false, forKey: "windowOcclusionDetectionEnabled")
        }

        let screen = NSScreen.main?.frame ?? .zero
        hostWindow = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 320, height: 180),
                              styleMask: .borderless, backing: .buffered, defer: false)
        hostWindow.alphaValue = 0
        hostWindow.isReleasedWhenClosed = false
        hostWindow.ignoresMouseEvents = true
        hostWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        super.init()

        detachVideo()
        hostWindow.orderFrontRegardless()

        config.userContentController.add(WeakMessageHandler(self), name: "fm")
        load(videoID: Self.videoID, channel: nil)

        if debug {
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.logProgress() }
            }
            // 메뉴바를 누르지 않고도 재생을 시험할 수 있도록 외부 신호를 받는다.
            DistributedNotificationCenter.default().addObserver(
                forName: .init("io.github.geeksbaek.claude-fm.toggle"), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.toggle() }
            }
        }
    }

    func toggle() {
        switch status {
        case .playing, .buffering: pause()
        default: play()
        }
    }

    func play() {
        if case .failed = status {
            triedChannelLive = false
            load(videoID: Self.videoID, channel: nil)
            return
        }
        run("fm.play()")
    }

    func pause() { run("fm.pause()") }

    /// 팝오버 안의 영상 칸으로 웹뷰를 옮긴다.
    func attachVideo() {
        guard let container = videoContainer, container.window != nil else { return }
        move(webView, into: container)
    }

    /// 팝오버가 닫히면 웹뷰를 호스트 창으로 되돌려 재생을 이어 간다.
    func detachVideo() {
        guard let content = hostWindow.contentView else { return }
        move(webView, into: content)
    }

    private func move(_ view: NSView, into container: NSView) {
        guard view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    private func load(videoID: String, channel: String?) {
        status = .loading
        let html = Self.html
            .replacingOccurrences(of: "__VIDEO_ID__", with: videoID)
            .replacingOccurrences(of: "__CHANNEL__", with: channel ?? "")
            .replacingOccurrences(of: "__VOLUME__", with: String(Int(volume)))
            .replacingOccurrences(of: "__ORIGIN__", with: Self.pageOrigin)
        webView.loadHTMLString(html, baseURL: URL(string: Self.pageOrigin + "/"))
    }

    private func run(_ script: String) {
        // YouTube 메서드는 플레이어 객체를 돌려주는데 Swift 로 넘길 수 없는 값이라 버린다.
        webView.evaluateJavaScript("void (window.fm && \(script))") { [debug] _, error in
            if debug, let error { NSLog("[ClaudeFM] js error: \(error)") }
        }
    }

    private func logProgress() {
        webView.evaluateJavaScript("window.fm ? fm.progress() : null") { value, _ in
            NSLog("[ClaudeFM] progress \(String(describing: value))")
        }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        let value = message["value"]
        if debug { NSLog("[ClaudeFM] \(type) \(String(describing: value))") }

        switch type {
        case "ready":
            if let name = value as? String, !name.isEmpty { title = name }
        case "state":
            // https://developers.google.com/youtube/iframe_api_reference#onStateChange
            switch value as? Int {
            case 0: status = .ended
            case 1: status = .playing
            case 2: status = .paused
            case 3: status = .buffering
            default: if status != .loading { status = .paused }
            }
        case "error":
            if !triedChannelLive {
                triedChannelLive = true
                load(videoID: "live_stream", channel: Self.channelID)
            } else {
                status = .failed("재생할 수 없어요 (YouTube 오류 \(value ?? "?"))")
            }
        default:
            break
        }
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden; } #player { width: 100%; height: 100%; }</style>
    </head>
    <body>
    <div id="player"></div>
    <script>
    const post = (type, value) => window.webkit.messageHandlers.fm.postMessage({ type, value });
    let player;
    let volume = __VOLUME__;
    window.onYouTubeIframeAPIReady = () => {
      const vars = { autoplay: 1, playsinline: 1, rel: 0, origin: "__ORIGIN__" };
      if ("__CHANNEL__") vars.channel = "__CHANNEL__";
      player = new YT.Player("player", {
        videoId: "__VIDEO_ID__",
        playerVars: vars,
        events: {
          onReady: (e) => {
            e.target.setVolume(volume);
            e.target.playVideo();
            post("ready", (e.target.getVideoData() || {}).title || "");
          },
          onStateChange: (e) => {
            // 재생 전에 정한 음량은 플레이어가 무시하므로 재생이 시작될 때 다시 맞춘다.
            if (e.data === YT.PlayerState.PLAYING) e.target.setVolume(volume);
            post("state", e.data);
          },
          onError: (e) => post("error", e.data),
        },
      });
    };
    window.fm = {
      play: () => player && player.playVideo && player.playVideo(),
      pause: () => player && player.pauseVideo && player.pauseVideo(),
      setVolume: (v) => { volume = v; player && player.setVolume && player.setVolume(v); },
      progress: () => player && player.getPlayerState
        ? { state: player.getPlayerState(), time: player.getCurrentTime(), muted: player.isMuted(), volume: player.getVolume(), visibility: document.visibilityState }
        : null,
    };
    const tag = document.createElement("script");
    tag.src = "https://www.youtube.com/iframe_api";
    tag.onerror = () => post("error", "iframe_api");
    document.head.appendChild(tag);
    </script>
    </body>
    </html>
    """
}

/// WKUserContentController 가 핸들러를 강하게 잡으므로 순환 참조를 끊는다.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var player: RadioPlayer?

    init(_ player: RadioPlayer) { self.player = player }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { player?.receive(body) }
    }
}
