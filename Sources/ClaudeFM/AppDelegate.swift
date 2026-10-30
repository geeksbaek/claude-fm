import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let player = RadioPlayer()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let menu = NSMenu()
    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(player: player))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        buildMenu()
        render()

        player.$status
            .removeDuplicates()
            .sink { [weak self] _ in
                // @Published 는 값이 바뀌기 직전에 알리므로 다음 런루프에서 반영한다.
                DispatchQueue.main.async { self?.playbackChanged() }
            }
            .store(in: &cancellables)

        if ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("io.github.geeksbaek.claude-fm.popover"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.togglePopover() }
            }
        }
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            player.attachVideo()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        player.detachVideo()
    }

    private func playbackChanged() {
        if player.isPlaying {
            guard animationTimer == nil else { return }
            let timer = Timer(timeInterval: Animation.frameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.render() }
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        render()
    }

    private func render() {
        statusItem.button?.image = ClawdSprite.image(frame: Animation.frame(at: Date()), playing: player.isPlaying)
        statusItem.button?.toolTip = player.isPlaying ? "\(player.title) — 재생 중" : player.title
    }

    // MARK: - 우클릭 메뉴

    private let toggleItem = NSMenuItem(title: "", action: #selector(togglePlayback), keyEquivalent: "")

    private func buildMenu() {
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "YouTube에서 열기", action: #selector(openYouTube), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Claude FM 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateMenu() {
        toggleItem.title = player.isPlaying ? "일시정지" : "재생"
    }

    @objc private func togglePlayback() { player.toggle() }

    @objc private func openYouTube() { NSWorkspace.shared.open(RadioPlayer.watchURL) }
}
