import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let player = RadioPlayer()
    private let rhythm = RhythmDance()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var singing = LyricSinging { [weak self] in self?.statusItem.button }
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
            rootView: PopoverView(player: player, rhythm: rhythm, singing: singing)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        buildMenu()
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
        singing.start()

        if ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("io.github.geeksbaek.claude-fm.popover"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.togglePopover() }
            }
            DistributedNotificationCenter.default().addObserver(
                forName: .init("io.github.geeksbaek.claude-fm.lyric"), object: nil, queue: .main
            ) { [weak self] note in
                let line = (note.userInfo?["line"] as? String) ?? (note.object as? String)
                MainActor.assumeIsolated { self?.singing.debugPreview(line) }
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

    private func syncAnimation() {
        // 박의 점프는 0.1초 안쪽이라, 재생 중이거나 춤추는 동안에는 프레임을 촘촘히 본다.
        if player.isPlaying || rhythm.isDancing {
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
        let pose = rhythm.pose()
        singing.updateFeeling(rhythm.feeling())
        if pose.showsMotion != rhythm.isDancing {
            rhythm.applyDancing(pose.showsMotion)
            if !pose.showsMotion, !player.isPlaying {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
        let key = IconKey(at: Date(), playing: player.isPlaying, title: player.title, pose: pose,
                          needsPermission: rhythm.needsPermission)
        guard key != lastIcon else { return }
        lastIcon = key
        render(key)
    }

    private func render(_ key: IconKey) {
        statusItem.button?.image = ClawdSprite.image(frame: key.note, playing: key.playing, dance: key.pose)
        statusItem.button?.toolTip = singing.bubbleShown ? nil : key.tip
    }

    // MARK: - 우클릭 메뉴

    private let toggleItem = NSMenuItem(title: "", action: #selector(togglePlayback), keyEquivalent: "")
    private let bubbleItem = NSMenuItem(title: "가사 말풍선 표시", action: #selector(toggleBubble), keyEquivalent: "")
    private let feelingItem = NSMenuItem(title: "말풍선 파장 필링 효과", action: #selector(toggleFeeling), keyEquivalent: "")

    private func buildMenu() {
        toggleItem.target = self
        bubbleItem.target = self
        feelingItem.target = self
        audioAccessItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(bubbleItem)
        menu.addItem(feelingItem)
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
        bubbleItem.state = singing.isBubbleEnabled ? .on : .off
        feelingItem.state = singing.isFeelingEnabled ? .on : .off
        rhythm.refreshAccess()
        if rhythm.needsPermission {
            if audioAccessItem.menu == nil { menu.insertItem(audioAccessItem, at: menu.numberOfItems - 2) }
        } else if audioAccessItem.menu != nil {
            menu.removeItem(audioAccessItem)
        }
    }

    @objc private func openAudioAccess() { RhythmDance.openSettings() }

    @objc private func togglePlayback() { player.toggle() }

    @objc private func toggleBubble() { singing.isBubbleEnabled.toggle() }

    @objc private func toggleFeeling() { singing.isFeelingEnabled.toggle() }

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

    init(at date: Date, playing: Bool, title: String, pose: DancePose, needsPermission: Bool) {
        self.playing = playing
        note = (playing || pose.showsMotion) ? Animation.frame(at: date) : 0
        dancing = pose.active
        bounce = pose.bounce
        stepRight = pose.stepRight
        mood = pose.mood
        style = pose.style
        mirrorball = pose.hasMirrorball
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
