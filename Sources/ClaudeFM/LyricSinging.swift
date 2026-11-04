import AppKit

/// 지금 재생 중인 곡의 가사를 찾아, 그 박의 줄을 메뉴바 아래에 말풍선으로 띄운다.
@MainActor
final class LyricSinging: ObservableObject {
    private static let bubbleEnabledKey = "lyricBubbleEnabled"
    private static let feelingEnabledKey = "lyricFeelingEnabled"

    @Published var isBubbleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBubbleEnabled, forKey: Self.bubbleEnabledKey)
            if isBubbleEnabled, song == nil, let snapshot, let trackKey, resolvedKey != trackKey {
                let now = ProcessInfo.processInfo.systemUptime
                let track = NowTrack(
                    title: snapshot.title,
                    artist: snapshot.artist,
                    album: snapshot.album,
                    duration: snapshot.duration,
                    elapsed: snapshot.elapsed(at: now),
                    rate: snapshot.rate
                )
                fetch(track, key: trackKey)
            }
            present()
        }
    }

    @Published var isFeelingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFeelingEnabled, forKey: Self.feelingEnabledKey)
            if bubbleShown {
                bubble.updateFeeling(currentFeeling, enabled: isFeelingEnabled)
            }
        }
    }

    private let bubble = LyricBubble()
    private let button: () -> NSButton?
    private var timer: Timer?
    private var polling = false
    private var lastPoll = 0.0
    private var snapshot: Snapshot?
    private var trackKey: String?
    private var song: LyricSong?
    private var resolvedKey: String?
    private var failedAt = 0.0
    private var fetchingKey: String?
    private var suppressed = false
    private var externalPlaying = false
    private var pauseGraceUntil = 0.0
    private var preview: String?
    private var previewUntil = 0.0
    private var currentFeeling = VocalFeeling.calm
    private var lastAnchor: (rect: NSRect, screen: NSScreen)?
    private var spaceObserver: NSObjectProtocol?
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil
    /// 말풍선이 떠 있는 동안 상태 아이콘 툴팁이 가사를 가리지 않게 한다.
    private(set) var bubbleShown = false
    var onBubbleVisibility: ((Bool) -> Void)?
    /// 다른 앱에서 노래가 재생 중이면 라디오를 멈추도록 알린다.
    var onExternalSongPlaying: (() -> Void)?

    init(button: @escaping () -> NSButton?) {
        self.button = button
        if UserDefaults.standard.object(forKey: Self.bubbleEnabledKey) == nil {
            self.isBubbleEnabled = true
        } else {
            self.isBubbleEnabled = UserDefaults.standard.bool(forKey: Self.bubbleEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.feelingEnabledKey) == nil {
            self.isFeelingEnabled = true
        } else {
            self.isFeelingEnabled = UserDefaults.standard.bool(forKey: Self.feelingEnabledKey)
        }
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.present()
                self?.bubble.orderFrontIfVisible()
            }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        bubble.hide()
    }

    /// 팝오버가 열려 있는 동안 말풍선이 가리지 않게 한다.
    func suppress(_ hidden: Bool) {
        suppressed = hidden
        present()
    }

    /// Claude FM을 재생할 때 다른 미디어 재생을 일시중지한다.
    func pauseExternalMedia() {
        pauseGraceUntil = ProcessInfo.processInfo.systemUptime + 3.5
        externalPlaying = false
        snapshot?.rate = 0
        present()
        NowPlaying.pause()
    }

    /// 오디오 파장에서 계산한 실시간 보컬 필링을 말풍선에 반영한다.
    func updateFeeling(_ feeling: VocalFeeling) {
        currentFeeling = feeling
        guard bubbleShown else { return }
        bubble.updateFeeling(feeling, enabled: isFeelingEnabled)
    }

    /// 디버그에서 말풍선 모양만 확인할 때. 비우면 영어·일본어·중국어 예시 발음을 보여 준다.
    func debugPreview(_ line: String?) {
        let sample = line?.trimmingCharacters(in: .whitespacesAndNewlines)
        preview = (sample?.isEmpty == false) ? sample : HangulReading.line("hello さくら 爱你")
        previewUntil = ProcessInfo.processInfo.systemUptime + 25
        present()
    }

    private struct Snapshot {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval?
        var elapsedAtFetch: TimeInterval
        var rate: Double
        var fetchedUptime: TimeInterval

        init(_ track: NowTrack, at uptime: TimeInterval) {
            title = track.title
            artist = track.artist
            album = track.album
            duration = track.duration
            elapsedAtFetch = track.elapsed
            rate = track.rate
            fetchedUptime = uptime
        }

        func elapsed(at now: TimeInterval) -> TimeInterval {
            max(0, elapsedAtFetch + rate * (now - fetchedUptime))
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPoll >= 0.8 {
            lastPoll = now
            poll()
        }
        present()
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        NowPlaying.current { [weak self] track in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.polling = false
                self.apply(track)
            }
        }
    }

    private func apply(_ track: NowTrack?) {
        guard let track else {
            externalPlaying = false
            if snapshot != nil {
                snapshot = nil
                song = nil
                trackKey = nil
                resolvedKey = nil
                present()
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var currentTrack = track
        if now < pauseGraceUntil {
            if abs(track.rate) <= 0.05 {
                pauseGraceUntil = 0
                externalPlaying = false
            } else {
                currentTrack.rate = 0
            }
        } else if abs(track.rate) > 0.05 {
            if !externalPlaying {
                externalPlaying = true
                onExternalSongPlaying?()
            }
        } else {
            externalPlaying = false
        }
        let key = currentTrack.title.lowercased() + "\n" + currentTrack.artist.lowercased()
        if key == trackKey, let prev = snapshot, abs(currentTrack.rate) > 0.05 {
            let prevElapsed = prev.elapsed(at: now)
            let backwardJitter = prevElapsed - currentTrack.elapsed
            if backwardJitter > 0, backwardJitter < 0.9 {
                currentTrack.elapsed = prevElapsed
            }
        }
        snapshot = Snapshot(currentTrack, at: now)
        if key != trackKey {
            trackKey = key
            song = nil
            resolvedKey = nil
            failedAt = 0
            if debug { NSLog("ClaudeFM lyric lookup %@ / %@", currentTrack.title, currentTrack.artist) }
            if isBubbleEnabled {
                fetch(currentTrack, key: key)
            }
        } else if isBubbleEnabled, song == nil, resolvedKey != key, failedAt > 0,
                  now - failedAt > 5 {
            fetch(currentTrack, key: key)
        }
        present()
    }

    private func fetch(_ track: NowTrack, key: String) {
        guard fetchingKey != key else { return }
        fetchingKey = key
        failedAt = ProcessInfo.processInfo.systemUptime
        Task { [weak self] in
            let found = await LyricLibrary.shared.song(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
            await MainActor.run {
                guard let self else { return }
                if self.fetchingKey == key { self.fetchingKey = nil }
                guard self.trackKey == key else { return }
                if let found {
                    self.song = found
                    self.resolvedKey = key
                    if self.debug {
                        NSLog("ClaudeFM lyric hit %d줄 instrumental %@", found.lines.count, found.instrumental ? "yes" : "no")
                    }
                } else {
                    // 없다는 응답은 라이브러리가 기억하므로 다시 물어도 네트워크로 나가지 않는다.
                    // 연결이 실패한 경우만 잠시 뒤 같은 곡으로 다시 묻는다.
                    self.failedAt = ProcessInfo.processInfo.systemUptime
                }
                self.present()
            }
        }
    }

    private func present() {
        let now = ProcessInfo.processInfo.systemUptime
        if let preview, now < previewUntil {
            if isBubbleEnabled, !suppressed, let anchor = anchor() {
                let parts = preview.components(separatedBy: "|")
                let current = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let next = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                let isInterlude = current == "♪" || current == "간주" || current == LyricCue.interludeToken
                let isHumming = current == "흥얼" || current == "음~" || current == LyricCue.hummingToken
                let cue: LyricCue
                if isHumming {
                    cue = .humming()
                } else if isInterlude {
                    cue = .interlude(next: next)
                } else {
                    cue = LyricCue(current: current, next: next)
                }
                showBubble(cue, anchor)
            } else {
                hideBubble()
            }
            return
        }
        preview = nil
        guard isBubbleEnabled, !suppressed, let snapshot, abs(snapshot.rate) > 0.05, let anchor = anchor() else {
            hideBubble()
            return
        }
        if let song {
            if song.instrumental {
                showBubble(.interlude(), anchor)
            } else if let cue = song.cue(at: snapshot.elapsed(at: now)), !cue.current.isEmpty {
                showBubble(cue, anchor)
            } else {
                showBubble(.humming(), anchor)
            }
            return
        }
        // 가사 조회가 끝났는데도 가사를 모를 때(또는 조회가 길어질 때)는 흥얼거리는 효과를 띄운다.
        if fetchingKey == nil || (failedAt > 0 && now - failedAt > 0.8) {
            showBubble(.humming(), anchor)
        } else {
            hideBubble()
        }
    }

    private func showBubble(_ cue: LyricCue, _ anchor: (rect: NSRect, screen: NSScreen)) {
        bubble.show(
            cue,
            feeling: isFeelingEnabled ? currentFeeling : .calm,
            feelingEnabled: isFeelingEnabled,
            anchor: anchor.rect,
            screen: anchor.screen
        )
        setBubbleShown(true)
    }

    private func hideBubble() {
        bubble.hide()
        setBubbleShown(false)
    }

    private func setBubbleShown(_ shown: Bool) {
        guard bubbleShown != shown else { return }
        bubbleShown = shown
        onBubbleVisibility?(shown)
    }

    private func anchor() -> (rect: NSRect, screen: NSScreen)? {
        guard let button = button(), let window = button.window else { return lastAnchor }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = window.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return lastAnchor
        }
        if rect.width > 0 {
            lastAnchor = (rect, screen)
            return (rect, screen)
        }
        if let lastAnchor {
            return (lastAnchor.rect, screen)
        }
        return (rect, screen)
    }
}
