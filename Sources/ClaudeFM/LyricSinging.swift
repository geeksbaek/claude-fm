import AppKit

/// 지금 재생 중인 곡의 가사를 찾아, 그 박의 줄을 메뉴바 아래에 말풍선으로 띄운다.
@MainActor
final class LyricSinging: ObservableObject {
    private static let bubbleEnabledKey = "lyricBubbleEnabled"
    private static let feelingEnabledKey = "lyricFeelingEnabled"
    private static let karaokeEnabledKey = "lyricKaraokeEnabled"
    private static let reactionEnabledKey = "lyricReactionEnabled"
    private static let syncOffsetKey = "lyricSyncOffset"
    /// 싱크는 이 범위 안에서 0.1초씩 옮긴다.
    static let syncRange: ClosedRange<Double> = -3...3

    @Published var isBubbleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBubbleEnabled, forKey: Self.bubbleEnabledKey)
            fetchIfNeeded()
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

    /// 노래방처럼 부른 만큼 글자를 채운다.
    @Published var isKaraokeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isKaraokeEnabled, forKey: Self.karaokeEnabledKey)
            present()
        }
    }

    /// 가사 속 낱말(사랑·별·불꽃…)에 맞춘 그림과 후렴 폭죽.
    @Published var isReactionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReactionEnabled, forKey: Self.reactionEnabledKey)
            present()
        }
    }

    /// 가사를 늦추는 초. 블루투스 헤드폰처럼 소리가 늦게 들리면 올린다.
    @Published private(set) var syncOffset: Double {
        didSet {
            UserDefaults.standard.set(syncOffset, forKey: Self.syncOffsetKey)
            present()
        }
    }

    /// 다른 앱에서 지금 재생 중인 곡. 팝오버와 무대에 보여 준다.
    @Published private(set) var nowTitle: String?
    @Published private(set) var nowArtist: String?
    /// 시각이 적힌 가사를 찾았는지. 싱크 조절을 보여 줄지 가린다.
    @Published private(set) var hasSyncedLyrics = false

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
    private var stageActive = false
    private var externalPlaying = false
    private var pauseGraceUntil = 0.0
    private var preview: String?
    private var previewUntil = 0.0
    private var currentFeeling = VocalFeeling.calm
    private var lastAnchor: (rect: NSRect, screen: NSScreen)?
    private var spaceObserver: NSObjectProtocol?
    private var titleCardUntil = 0.0
    private var lastHookStart: TimeInterval?
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil
    /// 말풍선이 떠 있는 동안 상태 아이콘 툴팁이 가사를 가리지 않게 한다.
    private(set) var bubbleShown = false
    /// 지금 보여 주는 장면. 메뉴바 Clawd 와 무대가 읽는다.
    private(set) var performance: LyricPerformance?
    var onBubbleVisibility: ((Bool) -> Void)?
    /// 다른 앱에서 노래가 재생 중이면 라디오를 멈추도록 알린다.
    var onExternalSongPlaying: (() -> Void)?
    /// 동기 가사의 후렴 덩어리가 시작할 때. 폭죽을 터뜨린다.
    var onHookStart: ((LyricCue) -> Void)?
    /// 간주 끝 카운트다운을 박에 맞추려고 박 간격을 묻는다.
    var beatPeriod: (() -> Double?)?
    /// 무대가 지금 화면에 보이는지. 보일 때만 말풍선을 숨긴다.
    var stageIsVisible: (() -> Bool)?

    init(button: @escaping () -> NSButton?) {
        self.button = button
        let defaults = UserDefaults.standard
        func flag(_ key: String) -> Bool {
            defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
        }
        isBubbleEnabled = flag(Self.bubbleEnabledKey)
        isFeelingEnabled = flag(Self.feelingEnabledKey)
        isKaraokeEnabled = flag(Self.karaokeEnabledKey)
        isReactionEnabled = flag(Self.reactionEnabledKey)
        let savedOffset = (defaults.double(forKey: Self.syncOffsetKey) * 10).rounded() / 10
        syncOffset = Self.syncRange.contains(savedOffset) ? savedOffset : 0
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

    /// 무대가 열려 있으면 말풍선 대신 무대가 가사를 부른다. 말풍선을 꺼 두었어도 가사는 찾는다.
    func setStageActive(_ active: Bool) {
        guard stageActive != active else { return }
        stageActive = active
        fetchIfNeeded()
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

    /// 무대가 프레임마다 묻는 지금 장면. 말풍선보다 촘촘히 새 줄을 알아챈다.
    func scene(at now: TimeInterval) -> LyricPerformance? {
        makePerformance(at: now)
    }

    /// 메뉴바 Clawd 가 따라 할 가사 반응. 줄을 부르는 동안만 있다.
    var spriteAccent: (reaction: LyricReaction?, hook: Bool) {
        guard isReactionEnabled, let cue = performance?.cue,
              !cue.isInterlude, !cue.isHumming, !cue.isTitle, cue.recap == nil else { return (nil, false) }
        return (cue.reaction, cue.isHook)
    }

    /// 가사 싱크를 0.1초 단위로 옮긴다. 0 이면 처음으로 되돌린다.
    func nudgeSync(by seconds: Double) {
        let target = seconds == 0 ? 0 : syncOffset + seconds
        let clamped = min(Self.syncRange.upperBound, max(Self.syncRange.lowerBound, (target * 10).rounded() / 10))
        if clamped != syncOffset { syncOffset = clamped }
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

    private var wantsLyrics: Bool { isBubbleEnabled || stageActive }

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
                setNowPlaying(title: nil, artist: nil)
                setSyncedLyrics(false)
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
        setNowPlaying(title: currentTrack.title, artist: currentTrack.artist)
        if key != trackKey {
            trackKey = key
            song = nil
            resolvedKey = nil
            failedAt = 0
            lastHookStart = nil
            setSyncedLyrics(false)
            // 곡이 바뀌면 전주 동안 제목을 잠깐 보여 준다. 가사가 곧 시작하면 그 전에 걷는다.
            titleCardUntil = abs(currentTrack.rate) > 0.05 ? now + 4.5 : 0
            if debug { NSLog("ClaudeFM lyric lookup %@ / %@", currentTrack.title, currentTrack.artist) }
            if wantsLyrics {
                fetch(currentTrack, key: key)
            }
        } else if wantsLyrics, song == nil, resolvedKey != key, failedAt > 0,
                  now - failedAt > 5 {
            fetch(currentTrack, key: key)
        }
        present()
    }

    /// 말풍선을 켜거나 무대를 열었을 때, 아직 찾지 않은 지금 곡의 가사를 찾는다.
    private func fetchIfNeeded() {
        guard wantsLyrics, song == nil, let snapshot, let trackKey, resolvedKey != trackKey else { return }
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
                    self.setSyncedLyrics(found.synced && !found.instrumental)
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

    private func setNowPlaying(title: String?, artist: String?) {
        if nowTitle != title { nowTitle = title }
        let shownArtist = (artist?.isEmpty == false) ? artist : nil
        if nowArtist != shownArtist { nowArtist = shownArtist }
    }

    private func setSyncedLyrics(_ synced: Bool) {
        if hasSyncedLyrics != synced { hasSyncedLyrics = synced }
    }

    /// 지금 곡 시각에 맞는 장면을 고른다. 재생 중이 아니면 nil.
    private func makePerformance(at now: TimeInterval) -> LyricPerformance? {
        guard let snapshot, abs(snapshot.rate) > 0.05 else { return nil }
        let clock = PlaybackClock(elapsed: snapshot.elapsed(at: now) - syncOffset, uptime: now, rate: snapshot.rate)
        let elapsed = clock.elapsed
        let cue: LyricCue
        if now < titleCardUntil, showsTitleCard(at: elapsed) {
            cue = .title(snapshot.title, artist: snapshot.artist)
        } else if let song {
            if song.instrumental {
                cue = .interlude()
            } else if let found = song.cue(at: elapsed), !found.current.isEmpty {
                cue = found
            } else {
                cue = .humming()
            }
        } else if fetchingKey == nil || (failedAt > 0 && now - failedAt > 0.8) {
            // 가사 조회가 끝났는데도 가사를 모를 때(또는 조회가 길어질 때)는 흥얼거리는 효과를 띄운다.
            cue = .humming()
        } else {
            return nil
        }
        return LyricPerformance(
            cue: cue,
            clock: song?.synced == true ? clock : nil,
            title: snapshot.title,
            artist: snapshot.artist
        )
    }

    /// 첫 줄이 곧 시작하면 제목 카드를 일찍 걷어 카운트다운이 보이게 한다.
    private func showsTitleCard(at elapsed: TimeInterval) -> Bool {
        guard let song, !song.instrumental, song.synced else { return true }
        guard let first = song.lines.first(where: { !$0.text.isEmpty }) else { return true }
        return elapsed < first.time - LyricCue.countdownBeat(beatPeriod?()) * Double(LyricCue.countdownDots) - 0.6
    }

    private func present() {
        let now = ProcessInfo.processInfo.systemUptime
        let scene = makePerformance(at: now)
        performance = scene
        if let scene { celebrateIfHookStarts(scene) }

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
                showBubble(cue, clock: nil, anchor)
            } else {
                hideBubble()
            }
            return
        }
        preview = nil
        let stageCovers = stageActive && (stageIsVisible?() ?? true)
        guard isBubbleEnabled, !suppressed, !stageCovers, let scene, let anchor = anchor() else {
            hideBubble()
            return
        }
        showBubble(scene.cue, clock: scene.clock, anchor)
    }

    /// 후렴 덩어리 첫 줄이 시작하는 박에 한 번만 알린다. 곡 첫머리의 후렴은 건너뛴다.
    private func celebrateIfHookStarts(_ scene: LyricPerformance) {
        guard isReactionEnabled, scene.cue.hookStart, let start = scene.cue.start, let clock = scene.clock,
              start != lastHookStart else { return }
        let elapsed = clock.elapsed
        guard elapsed >= start - 0.03 else { return }
        lastHookStart = start
        guard elapsed - start < 0.8, start >= 15 else { return }
        onHookStart?(scene.cue)
    }

    private func showBubble(_ cue: LyricCue, clock: PlaybackClock?, _ anchor: (rect: NSRect, screen: NSScreen)) {
        bubble.show(
            cue,
            clock: clock,
            style: BubbleStyle(
                karaoke: isKaraokeEnabled,
                reactions: isReactionEnabled,
                beatPeriod: beatPeriod?()
            ),
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

    /// 폭죽을 터뜨릴 메뉴바 아이콘 자리.
    func iconAnchor() -> (rect: NSRect, screen: NSScreen)? {
        anchor()
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
