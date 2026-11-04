import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let player = RadioPlayer()
    private let rhythm = RhythmDance()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var singing = LyricSinging { [weak self] in self?.statusItem.button }
    private lazy var stage = StageWindowController { [weak self] in self?.stageSnapshot() ?? StageSnapshot() }
    private let celebration = CelebrationOverlay()
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var animationTimer: Timer?
    private var lastIcon: IconKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(player: player, rhythm: rhythm, singing: singing) { [weak self] in
                self?.popover.performClose(nil)
                self?.stage.toggle()
            }
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        buildMenu()
        installMainMenu()
        tick()

        player.$status
            .removeDuplicates()
            .sink { [weak self] _ in
                // @Published 는 값이 바뀌기 직전에 알리므로 다음 런루프에서 반영한다.
                DispatchQueue.main.async { self?.syncAnimation() }
            }
            .store(in: &cancellables)

        player.onPlay = { [weak self] in
            self?.singing.pauseExternalMedia()
        }
        rhythm.onActivityChange = { [weak self] in self?.syncAnimation() }
        rhythm.onFeelingChange = { [weak self] feeling in
            self?.singing.updateFeeling(feeling)
        }
        singing.onBubbleVisibility = { [weak self] shown in
            self?.statusItem.button?.toolTip = shown ? nil : self?.lastIcon?.tip
            self?.syncAnimation()
        }
        singing.onExternalSongPlaying = { [weak self] in
            guard let self else { return }
            switch self.player.status {
            case .loading, .playing, .buffering:
                self.player.pause()
            default:
                break
            }
        }
        singing.beatPeriod = { [weak self] in self?.rhythm.beatPeriod }
        singing.stageIsVisible = { [weak self] in self?.stage.isShowingOnActiveSpace ?? false }
        singing.onHookStart = { [weak self] cue in self?.celebrate(cue.reaction) }
        // 시각이 적힌 가사가 있으면 후렴이 폭죽을 맡고, 없으면 드롭이 맡는다.
        rhythm.onSurge = { [weak self] in
            guard let self, self.singing.isReactionEnabled, !self.singing.hasSyncedLyrics else { return }
            self.celebrate(nil)
        }
        stage.onVisibilityChange = { [weak self] open in
            self?.singing.setStageActive(open)
            self?.syncAnimation()
        }
        stage.onTogglePlayback = { [weak self] in self?.player.toggle() }
        stage.onNudgeSync = { [weak self] seconds in
            guard let self else { return }
            self.singing.nudgeSync(by: seconds)
            self.stage.noteSync(self.singing.syncOffset)
        }
        singing.start()

        if ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil {
            let center = DistributedNotificationCenter.default()
            center.addObserver(forName: .init("io.github.geeksbaek.claude-fm.popover"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.togglePopover() }
            }
            center.addObserver(forName: .init("io.github.geeksbaek.claude-fm.lyric"), object: nil, queue: .main) { [weak self] note in
                let line = (note.userInfo?["line"] as? String) ?? (note.object as? String)
                MainActor.assumeIsolated { self?.singing.debugPreview(line) }
            }
            center.addObserver(forName: .init("io.github.geeksbaek.claude-fm.stage"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stage.toggle() }
            }
            center.addObserver(forName: .init("io.github.geeksbaek.claude-fm.confetti"), object: nil, queue: .main) { [weak self] note in
                let name = (note.userInfo?["reaction"] as? String) ?? (note.object as? String)
                MainActor.assumeIsolated { self?.celebrate(name.flatMap(LyricReaction.init(rawValue:)), force: true) }
            }
        }
        rhythm.start()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            updateMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            // 앱이 비활성이면 팝오버가 키 창이 되지 못해 바로 닫히고 단축키도 먹지 않는다.
            NSApp.activate(ignoringOtherApps: true)
            rhythm.refreshAccess()
            singing.suppress(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            player.attachVideo()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        player.detachVideo()
        singing.suppress(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        singing.stop()
        rhythm.stop()
    }

    /// 후렴이 시작되면 폭죽을 터뜨린다. 무대가 보이면 무대에서, 아니면 메뉴바 아래에서.
    private func celebrate(_ reaction: LyricReaction?, force: Bool = false) {
        if stage.isShowingOnActiveSpace {
            stage.celebrate(reaction)
            return
        }
        guard force || !popover.isShown, let anchor = singing.iconAnchor() else { return }
        celebration.burst(at: anchor.rect, screen: anchor.screen, mood: rhythm.mood, reaction: reaction, force: force)
    }

    private func stageSnapshot() -> StageSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        var snapshot = StageSnapshot()
        snapshot.pose = rhythm.pose(at: now)
        snapshot.playing = player.isPlaying
        snapshot.accent = spriteAccent()
        snapshot.feeling = rhythm.feeling(at: now)
        snapshot.spectrum = rhythm.spectrum(at: now)
        snapshot.beatCount = rhythm.beatCount
        snapshot.beatPhase = rhythm.beatPhase(at: now)
        snapshot.beatPeriod = rhythm.beatPeriod
        snapshot.bpm = rhythm.bpm
        snapshot.mood = rhythm.mood
        snapshot.performance = singing.scene(at: now)
        snapshot.karaoke = singing.isKaraokeEnabled
        snapshot.reactions = singing.isReactionEnabled
        snapshot.radioTitle = player.title
        snapshot.needsPermission = rhythm.needsPermission
        return snapshot
    }

    private func spriteAccent() -> SpriteAccent {
        let accent = singing.spriteAccent
        return SpriteAccent(reaction: accent.reaction, hook: accent.hook)
    }

    private func syncAnimation() {
        // 박의 점프는 0.1초 안쪽이라, 재생 중이거나 춤추는 동안에는 프레임을 촘촘히 본다.
        // 가사를 부르는 동안에도 반응 그림이 떠오르도록 돌린다.
        if player.isPlaying || rhythm.isDancing || singing.bubbleShown || stage.isOpen {
            if animationTimer == nil {
                let timer = Timer(timeInterval: Animation.danceInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                RunLoop.main.add(timer, forMode: .common)
                animationTimer = timer
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        tick()
    }

    private func tick() {
        var pose = rhythm.pose()
        let accent = spriteAccent()
        // 후렴에서는 박에 맞춰 두 팔을 번쩍 든다.
        if accent.hook, pose.active { pose.style = .handsUp }
        singing.updateFeeling(rhythm.feeling())
        if pose.showsMotion != rhythm.isDancing {
            rhythm.applyDancing(pose.showsMotion)
            if !pose.showsMotion, !player.isPlaying, !singing.bubbleShown, !stage.isOpen {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
        let key = IconKey(at: Date(), playing: player.isPlaying, title: player.title, pose: pose, accent: accent,
                          needsPermission: rhythm.needsPermission)
        guard key != lastIcon else { return }
        lastIcon = key
        render(key)
    }

    private func render(_ key: IconKey) {
        statusItem.button?.image = ClawdSprite.image(frame: key.note, playing: key.playing, dance: key.pose, accent: key.accent)
        statusItem.button?.toolTip = singing.bubbleShown ? nil : key.tip
    }

    // MARK: - 우클릭 메뉴

    private let toggleItem = NSMenuItem(title: "", action: #selector(togglePlayback), keyEquivalent: "")
    private let stageItem = NSMenuItem(title: "무대 열기", action: #selector(toggleStage), keyEquivalent: "")
    private let bubbleItem = NSMenuItem(title: "가사 말풍선 표시", action: #selector(toggleBubble), keyEquivalent: "")
    private let feelingItem = NSMenuItem(title: "말풍선 파장 필링 효과", action: #selector(toggleFeeling), keyEquivalent: "")
    private let karaokeItem = NSMenuItem(title: "노래방 채움", action: #selector(toggleKaraoke), keyEquivalent: "")
    private let reactionItem = NSMenuItem(title: "가사 반응과 후렴 폭죽", action: #selector(toggleReaction), keyEquivalent: "")

    private func buildMenu() {
        for item in [toggleItem, stageItem, bubbleItem, feelingItem, karaokeItem, reactionItem, audioAccessItem] {
            item.target = self
        }
        menu.addItem(toggleItem)
        menu.addItem(stageItem)
        menu.addItem(.separator())
        menu.addItem(bubbleItem)
        menu.addItem(feelingItem)
        menu.addItem(karaokeItem)
        menu.addItem(reactionItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "YouTube에서 열기", action: #selector(openYouTube), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Claude FM 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private let audioAccessItem = NSMenuItem(title: "시스템 오디오 권한 열기…", action: #selector(openAudioAccess), keyEquivalent: "")

    private func updateMenu() {
        toggleItem.title = player.isPlaying ? "일시정지" : "재생"
        stageItem.title = stage.isOpen ? "무대 닫기" : "무대 열기"
        bubbleItem.state = singing.isBubbleEnabled ? .on : .off
        feelingItem.state = singing.isFeelingEnabled ? .on : .off
        karaokeItem.state = singing.isKaraokeEnabled ? .on : .off
        reactionItem.state = singing.isReactionEnabled ? .on : .off
        rhythm.refreshAccess()
        if rhythm.needsPermission {
            if audioAccessItem.menu == nil { menu.insertItem(audioAccessItem, at: menu.numberOfItems - 2) }
        } else if audioAccessItem.menu != nil {
            menu.removeItem(audioAccessItem)
        }
    }

    /// 무대가 열려 Dock 에 나와 있는 동안 쓰는 앱 메뉴. ⌘Q, ⌘W, 전체 화면 단축키가 여기서 나온다.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Claude FM")
        appMenu.addItem(NSMenuItem(title: "Claude FM 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Claude FM 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(NSMenuItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        let fullScreen = NSMenuItem(title: "전체 화면", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(fullScreen)
        windowMenu.addItem(NSMenuItem(title: "무대 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func openAudioAccess() { RhythmDance.openSettings() }

    @objc private func togglePlayback() { player.toggle() }

    @objc private func toggleStage() { stage.toggle() }

    @objc private func toggleBubble() { singing.isBubbleEnabled.toggle() }

    @objc private func toggleFeeling() { singing.isFeelingEnabled.toggle() }

    @objc private func toggleKaraoke() { singing.isKaraokeEnabled.toggle() }

    @objc private func toggleReaction() { singing.isReactionEnabled.toggle() }

    @objc private func openYouTube() { NSWorkspace.shared.open(RadioPlayer.watchURL) }
}

/// 메뉴바 아이콘이 실제로 달라질 때만 이미지를 다시 그린다.
private struct IconKey: Equatable {
    var playing: Bool
    var note: Int
    var dancing: Bool
    var bounce: DancePose.Bounce
    var stepRight: Bool
    var mood: MusicMood
    var style: DanceStyle
    var mirrorball: Bool
    var accent: SpriteAccent
    var tip: String

    var pose: DancePose {
        let hop: Double
        switch bounce {
        case .air: hop = 1
        case .land: hop = 0.4
        case .rest: hop = 0
        }
        return DancePose(
            active: dancing,
            hop: hop,
            stepRight: stepRight,
            mood: mood,
            style: style,
            danceTime: mirrorball ? 5.0 : 0.0
        )
    }

    init(at date: Date, playing: Bool, title: String, pose: DancePose, accent: SpriteAccent, needsPermission: Bool) {
        self.playing = playing
        note = (playing || pose.showsMotion || accent.reaction != nil) ? Animation.frame(at: date) : 0
        dancing = pose.active
        bounce = pose.bounce
        stepRight = pose.stepRight
        mood = pose.mood
        style = pose.style
        mirrorball = pose.hasMirrorball
        self.accent = accent
        if playing {
            tip = pose.mood.label.map { "\(title) — 재생 중 · \($0)" } ?? "\(title) — 재생 중"
        } else if let caption = pose.mood.caption {
            tip = "\(title) — \(caption)"
        } else if needsPermission {
            tip = "\(title) — 춤추려면 시스템 오디오 권한이 필요해요"
        } else {
            tip = title
        }
    }
}
