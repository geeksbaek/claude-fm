import AppKit
import Foundation

/// 시스템 오디오의 박자를 메뉴바와 팝오버가 같이 쓰도록 들고 있는다.
@MainActor
final class RhythmDance: ObservableObject {
    @Published private(set) var isDancing = false
    @Published private(set) var mood = MusicMood.quiet
    @Published private(set) var needsPermission = false

    /// 춤이 시작·끝나거나 새 박이 들어올 때. 메뉴바 아이콘을 바로 갱신한다.
    var onActivityChange: (() -> Void)?
    /// 오디오 파장이 들어올 때마다 가사 말풍선에 실시간 필링(외침·속삭임·파장)을 전달한다.
    var onFeelingChange: ((VocalFeeling) -> Void)?

    private var clock = BeatClock()
    private let tap = SystemAudioTap()
    private var accessTimer: Timer?
    private var heardAudio = false
    private var silenceWhileRunning: TimeInterval = 0
    private var lastAccess: Int?
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil
    private var lastDebugLog = 0.0

    func start() {
        tap.onChunk = { [weak self] chunk in
            MainActor.assumeIsolated { self?.ingest(chunk) }
        }
        guard #available(macOS 14.2, *) else { return }
        tap.start()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollAccess() }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
        pollAccess()
    }

    func stop() {
        accessTimer?.invalidate()
        accessTimer = nil
        guard #available(macOS 14.2, *) else { return }
        tap.stop()
    }

    func pose(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> DancePose {
        clock.pose(at: time)
    }

    func feeling(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> VocalFeeling {
        clock.feeling(at: time)
    }

    /// 소리 콜백이 끊겨도 메뉴바 타이머가 움직임이 끝난 것을 알 수 있게 한다.
    func applyDancing(_ dancing: Bool) {
        guard dancing != isDancing else { return }
        isDancing = dancing
    }

    /// 설정에서 권한을 바꾼 직후 팝오버나 메뉴를 열면 탭을 다시 붙인다.
    func refreshAccess() {
        pollAccess()
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
        ]
        for text in urls {
            if let url = URL(string: text), NSWorkspace.shared.open(url) { return }
        }
    }

    private func ingest(_ chunk: SystemAudioTap.Chunk) {
        let now = ProcessInfo.processInfo.systemUptime
        let beatsBefore = clock.beatCount
        clock.ingest(low: chunk.low, high: chunk.high, full: chunk.full, dt: chunk.dt, now: now)
        if chunk.full >= BeatClock.audibleEnergy {
            heardAudio = true
            silenceWhileRunning = 0
            if needsPermission { needsPermission = false }
        }
        let pose = clock.pose(at: now)
        let moving = pose.showsMotion
        let motionChanged = moving != isDancing
        let moodChanged = pose.mood != mood
        if motionChanged { isDancing = moving }
        if moodChanged { mood = pose.mood }
        if motionChanged || moodChanged || clock.beatCount != beatsBefore { onActivityChange?() }
        onFeelingChange?(clock.feeling(at: now))
        guard debug, now - lastDebugLog > 1 else { return }
        lastDebugLog = now
        let line = String(format: "full=%.6f low=%.6f high=%.6f beats=%d dancing=%@ mood=%@ access=%@\n",
                          chunk.full, chunk.low, chunk.high, clock.beatCount, moving ? "yes" : "no",
                          String(describing: pose.mood), String(describing: lastAccess))
        NSLog("[ClaudeFM] rhythm \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func pollAccess() {
        let status = SystemAudioAccess.preflight()
        if debug, status != lastAccess {
            NSLog("[ClaudeFM] audio capture access \(String(describing: status))")
        }
        if let status, status != lastAccess {
            let granted = status == 0 && lastAccess != nil && lastAccess != 0
            lastAccess = status
            if granted, #available(macOS 14.2, *) { tap.start() }
        }

        // 이미 허용됐으면 안내하지 않는다. 권한이 없을 때 탭은 오류 없이 0만 돌려준다.
        let waiting = status != 0 && !heardAudio && SystemAudioTap.defaultOutputIsRunning()
        silenceWhileRunning = waiting ? silenceWhileRunning + 0.5 : 0
        let needed = waiting && silenceWhileRunning >= 3
        guard needed != needsPermission else { return }
        needsPermission = needed
        onActivityChange?()
    }
}

/// 시스템 오디오 녹음 권한. 공개 API가 없어서 TCC에 상태만 물어 보고, 권한을 바꾸지는 않는다.
private enum SystemAudioAccess {
    /// 0 허용, 1 거부, 2 아직 묻지 않음. 심볼이 없으면 nil.
    static func preflight() -> Int? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_LAZY),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        let function = unsafeBitCast(symbol, to: Preflight.self)
        return function("kTCCServiceAudioCapture" as CFString, nil)
    }
}
