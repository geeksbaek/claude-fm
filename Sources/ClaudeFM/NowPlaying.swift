import Foundation

/// 지금 재생 중인 곡. 메뉴바 앱이 시스템에 알린 제목·가수·위치만 읽고, 소리는 받지 않는다.
struct NowTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    var elapsed: TimeInterval
    var rate: Double

    init(title: String, artist: String, album: String, duration: TimeInterval?, elapsed: TimeInterval, rate: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.rate = rate
    }
}

enum NowPlaying {
    static func current(_ done: @escaping (NowTrack?) -> Void) {
        // macOS 15.4부터는 일반 앱이 MediaRemote에 직접 물으면 빈 응답만 받는다.
        // 시스템 바이너리인 osascript로 읽어야 크롬 유튜브 뮤직처럼 지금 곡을 알린 앱이 보인다.
        if #available(macOS 15.4, *) {
            DispatchQueue.global(qos: .utility).async {
                let track = SystemNowPlayingScript.track()
                DispatchQueue.main.async { done(track) }
            }
            return
        }
        guard let getInfo else {
            done(nil)
            return
        }
        let block: @convention(block) (CFDictionary?) -> Void = { info in
            let track = info.flatMap(NowTrack.init(info:))
            DispatchQueue.main.async { done(track) }
        }
        getInfo(DispatchQueue.main, block as AnyObject)
    }

    /// 현재 시스템에서 재생 중인 외부 미디어를 일시정지한다.
    static func pause() {
        if #available(macOS 15.4, *) {
            DispatchQueue.global(qos: .userInitiated).async {
                SystemNowPlayingScript.pause()
            }
            return
        }
        _ = sendCommand?(1, nil)
    }

    private typealias InfoFunction = @convention(c) (DispatchQueue, AnyObject) -> Void
    private typealias CommandFunction = @convention(c) (UInt32, CFDictionary?) -> UInt8

    private static let getInfo: InfoFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
        return unsafeBitCast(symbol, to: InfoFunction.self)
    }()

    private static let sendCommand: CommandFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: CommandFunction.self)
    }()
}

extension NowTrack {
    fileprivate init?(info: CFDictionary) {
        let dict = info as NSDictionary
        func text(_ key: String) -> String {
            if let value = dict[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let names = dict[key] as? [String] {
                return names.joined(separator: ", ")
            }
            return ""
        }
        func number(_ key: String) -> Double? {
            (dict[key] as? NSNumber)?.doubleValue
        }

        title = text("kMRMediaRemoteNowPlayingInfoTitle")
        artist = text("kMRMediaRemoteNowPlayingInfoArtist")
        album = text("kMRMediaRemoteNowPlayingInfoAlbum")
        guard !title.isEmpty else { return nil }

        var duration = number("kMRMediaRemoteNowPlayingInfoDuration")
        if let value = duration, value > 10_000 { duration = value / 1000 }
        var elapsed = number("kMRMediaRemoteNowPlayingInfoElapsedTime") ?? 0
        if let duration, elapsed > duration * 5, elapsed > 10_000 { elapsed /= 1000 }
        let rate = number("kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? 1
        if let stamp = Self.stamp(dict["kMRMediaRemoteNowPlayingInfoTimestamp"]) {
            let delta = Date().timeIntervalSince(stamp)
            if delta >= -1, delta < 6 * 60 * 60 {
                elapsed += max(rate, 0) * max(delta, 0)
            }
        }
        self.duration = duration
        self.elapsed = max(0, elapsed)
        self.rate = rate
    }

    /// 재생 시각은 Date 이거나, 2001년 기준·1970년 기준 초 숫자로 온다.
    private static func stamp(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        if raw > 1_500_000_000 { return Date(timeIntervalSince1970: raw) }
        if raw > 500_000_000 { return Date(timeIntervalSinceReferenceDate: raw) }
        return nil
    }
}

/// `/usr/bin/osascript` 는 지금 곡을 읽을 수 있는 시스템 프로세스다. 제목·가수·위치만 받아 온다.
private enum SystemNowPlayingScript {
    static func track() -> NowTrack? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            if let data = script.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            try input.fileHandleForWriting.close()
        } catch {
            return nil
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.track()
    }

    static func pause() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            if let data = pauseScript.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            try input.fileHandleForWriting.close()
        } catch {
            return
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
        }
    }

    private struct Payload: Decodable {
        var title: String
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var rate: Double?
        var timestamp: Double?
        var bundle: String?
        var parent: String?

        func track() -> NowTrack? {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !isClaudeFM else { return nil }
            var duration = duration
            if let value = duration, value > 10_000 { duration = value / 1000 }
            var elapsed = elapsed ?? 0
            if let duration, elapsed > duration * 5, elapsed > 10_000 { elapsed /= 1000 }
            let rate = rate ?? 1
            if let timestamp {
                let delta = Date().timeIntervalSince1970 - timestamp
                if delta >= -1, delta < 6 * 60 * 60 {
                    elapsed += max(rate, 0) * max(delta, 0)
                }
            }
            return NowTrack(
                title: title,
                artist: artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                album: album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                duration: duration,
                elapsed: max(0, elapsed),
                rate: rate
            )
        }

        /// 우리 라이브 플레이어가 지금 곡 자리를 잡고 있으면 가사 대상이 아니다.
        private var isClaudeFM: Bool {
            [bundle, parent].compactMap { $0?.lowercased() }.contains { $0.contains("claude-fm") }
        }
    }

    private static let script = """
    function run() {
      var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework');
      if (!bundle || !bundle.load) return '';
      var request = $.NSClassFromString('MRNowPlayingRequest');
      if (!request) return '';
      var item = request.localNowPlayingItem;
      if (!item || !item.nowPlayingInfo) return '';
      var info = item.nowPlayingInfo;
      function field(key) {
        var value = info.valueForKey(key);
        if (!value) return null;
        var js = value.js;
        if (Array.isArray(js)) return js.join(', ');
        return js;
      }
      var title = field('kMRMediaRemoteNowPlayingInfoTitle');
      if (!title) return '';
      var path = request.localNowPlayingPlayerPath;
      var client = path ? path.client : null;
      function nameOf(value) {
        if (!value) return '';
        var js = value.js;
        return js ? String(js) : '';
      }
      var stamp = field('kMRMediaRemoteNowPlayingInfoTimestamp');
      var timestamp = null;
      if (stamp && stamp.getTime) timestamp = stamp.getTime() / 1000;
      return JSON.stringify({
        title: String(title),
        artist: String(field('kMRMediaRemoteNowPlayingInfoArtist') || ''),
        album: String(field('kMRMediaRemoteNowPlayingInfoAlbum') || ''),
        duration: field('kMRMediaRemoteNowPlayingInfoDuration'),
        elapsed: field('kMRMediaRemoteNowPlayingInfoElapsedTime') || 0,
        rate: field('kMRMediaRemoteNowPlayingInfoPlaybackRate'),
        timestamp: timestamp,
        bundle: nameOf(client ? client.bundleIdentifier : null),
        parent: nameOf(client ? client.parentApplicationBundleIdentifier : null)
      });
    }
    """

    private static let pauseScript = """
    function run() {
      ObjC.import('Foundation');
      var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework');
      if (!bundle || !bundle.load) return '';
      var request = $.NSClassFromString('MRNowPlayingRequest');
      if (!request) return '';
      var path = request.localNowPlayingPlayerPath;
      var client = path ? path.client : null;
      function nameOf(value) {
        if (!value) return '';
        var js = value.js;
        return js ? String(js).toLowerCase() : '';
      }
      var b = nameOf(client ? client.bundleIdentifier : null);
      var p = nameOf(client ? client.parentApplicationBundleIdentifier : null);
      if (b.indexOf('claude-fm') >= 0 || p.indexOf('claude-fm') >= 0) return '';
      ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
      $.MRMediaRemoteSendCommand(1, $());
      $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.2));
      return '';
    }
    """
}
