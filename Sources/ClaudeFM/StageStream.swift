import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os
import UniformTypeIdentifiers

/// 영상 프레임과 오디오 탭이 같이 쓰는 시계. mach_absolute_time 을 초로 바꾼다.
/// 탭이 넘기는 `mHostTime` 도 같은 눈금이라, 소리와 그림을 한 시간줄에 놓을 수 있다.
enum HostClock {
    static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(max(info.denom, 1)) / 1_000_000_000
    }()

    static func now() -> Double { Double(mach_absolute_time()) * secondsPerTick }

    static func seconds(_ ticks: UInt64) -> Double { Double(ticks) * secondsPerTick }
}

/// 오디오 탭이 넘긴 PCM 을 엔코더가 가져갈 때까지 담아 둔다. 왼쪽·오른쪽을 번갈아 둔 Float32 이다.
/// 탭 콜백(실시간 스레드)에서는 미리 잡아 둔 칸에 복사만 하고, 자리가 없으면 버린다. 메모리를 새로 잡지 않는다.
final class StageAudioRing: @unchecked Sendable {
    /// 콜백 한 번에 들어온 덩어리. `host` 는 첫 칸의 호스트 시각(초)이다.
    struct Chunk: Equatable {
        var host: Double
        var frames: Int
        var rate: Double
    }

    let capacity: Int
    private let chunkCapacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private let chunks: UnsafeMutablePointer<Chunk>
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var readFrame = 0
    private var writeFrame = 0
    private var readChunk = 0
    private var writeChunk = 0
    private var offsetInChunk = 0
    private var lastHost = 0.0
    private var droppedFrames = 0

    init(capacity: Int = 192_000, chunkCapacity: Int = 2_048) {
        let frames = max(4_096, capacity)
        let chunkSlots = max(64, chunkCapacity)
        self.capacity = frames
        self.chunkCapacity = chunkSlots
        samples = .allocate(capacity: frames * 2)
        samples.initialize(repeating: 0, count: frames * 2)
        chunks = .allocate(capacity: chunkSlots)
        chunks.initialize(repeating: Chunk(host: 0, frames: 0, rate: 0), count: chunkSlots)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        samples.deallocate()
        chunks.deallocate()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// 탭 콜백에서 부른다. 섞인 채널(간격 = 채널 수)이든 나뉜 채널(간격 1)이든 왼쪽·오른쪽 시작점과 간격만 넘긴다.
    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, stride: Int, frames: Int, host: Double, rate: Double) {
        guard frames > 0, stride > 0 else { return }
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard capacity - (writeFrame - readFrame) >= frames, writeChunk - readChunk < chunkCapacity else {
            droppedFrames += frames
            return
        }
        var slot = writeFrame % capacity
        var index = 0
        for _ in 0..<frames {
            samples[slot &* 2] = left[index]
            samples[slot &* 2 &+ 1] = right[index]
            index &+= stride
            slot &+= 1
            if slot == capacity { slot = 0 }
        }
        chunks[writeChunk % chunkCapacity] = Chunk(host: host, frames: frames, rate: rate)
        writeFrame += frames
        writeChunk += 1
        lastHost = host + Double(frames) / max(rate, 1)
    }

    /// 쌓인 덩어리 하나(너무 크면 앞부분)를 꺼내 `destination` 에 번갈아 담는다. 비었으면 nil.
    func read(into destination: UnsafeMutablePointer<Float>, maxFrames: Int) -> Chunk? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard readChunk < writeChunk, maxFrames > 0 else { return nil }
        let chunk = chunks[readChunk % chunkCapacity]
        let count = min(chunk.frames - offsetInChunk, maxFrames)
        var slot = readFrame % capacity
        for index in 0..<count {
            destination[index * 2] = samples[slot * 2]
            destination[index * 2 + 1] = samples[slot * 2 + 1]
            slot += 1
            if slot == capacity { slot = 0 }
        }
        let host = chunk.host + Double(offsetInChunk) / max(chunk.rate, 1)
        offsetInChunk += count
        readFrame += count
        if offsetInChunk >= chunk.frames {
            readChunk += 1
            offsetInChunk = 0
        }
        return Chunk(host: host, frames: count, rate: chunk.rate)
    }

    /// 마지막으로 받은 소리의 끝 시각(호스트 초). 탭이 멈췄는지 볼 때 쓴다.
    var lastWriteHost: Double {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return lastHost
    }

    var dropped: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return droppedFrames
    }
}

// MARK: - 소리 시간줄

/// 탭이 넘긴 소리 덩어리를 영상과 같은 시간줄에 놓는다. 덩어리의 호스트 시각으로 놓일 자리를 구해서,
/// 비면 조용한 칸으로 메우고, 이미 지난 자리면 겹친 만큼 버리고, 조금씩 어긋나면 덩어리마다 한 칸씩 고친다.
/// 그래서 소리는 끊김 없이 이어지고, 장치 시계가 조금 빠르거나 느려도 그림과 벌어지지 않는다.
struct StageAudioTimeline: Equatable {
    struct Placement: Equatable {
        /// 덩어리 앞에 넣을 조용한 칸.
        var silence = 0
        /// 덩어리 앞에서 버릴 칸.
        var skip = 0
        /// 덩어리 첫 칸을 한 번 더 넣는다.
        var repeatFirst = false
    }

    let rate: Double
    /// 시간줄 0 의 호스트 시각.
    let start: Double
    /// 지금까지 놓은 칸 수.
    private(set) var head: Int64 = 0

    init(rate: Double, start: Double) {
        self.rate = rate
        self.start = start
    }

    /// 이만큼(40ms) 넘게 어긋나면 한 번에 메우거나 버린다.
    var jump: Int64 { Int64(rate * 0.04) }
    /// 이만큼(2ms) 넘게 어긋나면 한 칸씩 고친다.
    var nudge: Int64 { Int64(rate * 0.002) }

    func place(host: Double, frames: Int) -> Placement {
        let ideal = Int64(((host - start) * rate).rounded())
        let delta = ideal - head
        if delta > jump { return Placement(silence: Int(delta)) }
        if delta < -jump { return Placement(skip: Int(min(Int64(frames), -delta))) }
        if delta > nudge { return Placement(repeatFirst: true) }
        if delta < -nudge, frames > 1 { return Placement(skip: 1) }
        return Placement()
    }

    mutating func advance(_ frames: Int) {
        head += Int64(frames)
    }

    /// 소리가 `latency` 넘게 늦으면 그 시각까지 조용한 칸으로 채울 수.
    func silenceDue(at host: Double, latency: Double) -> Int {
        let due = Int64(((host - start - latency) * rate).rounded(.down))
        return due > head ? Int(due - head) : 0
    }
}

// MARK: - 엔코더

/// 무대 영상과 소리를 1초짜리 fMP4 조각으로 굽는다. 조각은 `StageSegmentStore` 에 쌓여 HLS 로 나간다.
/// H.264 High 1280×720 30fps(1초마다 키프레임, 순서 바꿈 없음)와 AAC-LC 스테레오를 한 시간줄에 놓는다.
final class StageStreamEncoder: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    struct Settings: Equatable {
        var width = 1_280
        var height = 720
        var frameRate: Int32 = 30
        var videoBitRate = 4_500_000
        var audioBitRate = 160_000
        var sampleRate = 48_000.0
        var segmentSeconds = 1.0
        /// 실제 시간으로 들어오는지. 검사에서는 끄고, 엔코더가 받을 수 있을 때까지 기다려 넣는다.
        var realTime = true
    }

    enum Failure: Error, Equatable {
        case unsupported(String)
        case writer(String)
    }

    /// 모든 조각 시각에 더하는 앞자리. AAC 앞머리 때문에 시각이 0 아래로 내려가지 않게 한다.
    static let timeOffset = CMTime(value: 10, timescale: 1)
    /// 소리가 이만큼 넘게 안 오면 조용한 칸으로 시간을 채운다.
    static let audioLatency = 0.15

    let settings: Settings
    let store: StageSegmentStore
    let ring: StageAudioRing
    /// 굽다가 멈췄을 때. 엔코더 큐에서 한 번 부른다.
    var onFailure: ((String) -> Void)?

    private let queue = DispatchQueue(label: "io.github.geeksbaek.claude-fm.stream.encoder")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioFormat: CMAudioFormatDescription?
    private var pool: CVPixelBufferPool?
    private var timeline = StageAudioTimeline(rate: 48_000, start: 0)
    private var startHost = 0.0
    private var lastFrameIndex: Int64 = -1
    private var pumpTimer: DispatchSourceTimer?
    private var state = State.idle
    private let pendingLock = OSAllocatedUnfairLock(initialState: 0)

    private static let readCapacity = 4_096
    private static let resampleCapacity = 4_096 * 8
    private let stagingCapacity: Int
    private let readBuffer: UnsafeMutablePointer<Float>
    private let resampleBuffer: UnsafeMutablePointer<Float>
    private let staging: UnsafeMutablePointer<Float>
    private var staged = 0
    private var stagedStart: Int64 = 0

    private(set) var framesAppended = 0
    private(set) var framesDropped = 0
    private(set) var audioFramesAppended: Int64 = 0

    private enum State {
        case idle, writing, finishing, finished, failed
    }

    init(settings: Settings = Settings(), store: StageSegmentStore, ring: StageAudioRing) {
        self.settings = settings
        self.store = store
        self.ring = ring
        let stagingFrames = max(4_096, Int(settings.sampleRate / 2))
        stagingCapacity = stagingFrames
        readBuffer = .allocate(capacity: Self.readCapacity * 2)
        resampleBuffer = .allocate(capacity: Self.resampleCapacity * 2)
        staging = .allocate(capacity: stagingFrames * 2)
        super.init()
    }

    deinit {
        pumpTimer?.cancel()
        readBuffer.deallocate()
        resampleBuffer.deallocate()
        staging.deallocate()
    }

    /// 픽셀 버퍼를 꺼낼 웅덩이. `start` 가 돌아온 뒤로는 바뀌지 않는다.
    var pixelBufferPool: CVPixelBufferPool? { pool }

    /// 아직 엔코더 큐에 들어가지 않은 프레임 수. 밀리면 그리는 쪽이 한 장 쉰다.
    var pendingFrames: Int { pendingLock.withLock { $0 } }

    /// 넣은 프레임, 버린 프레임, 넣은 소리 칸 수.
    var stats: (frames: Int, dropped: Int, audioFrames: Int64) {
        queue.sync { (framesAppended, framesDropped, audioFramesAppended) }
    }

    /// 아직 굽는 중인지.
    var isWriting: Bool {
        queue.sync { state == .writing && writer?.status == .writing }
    }

    var videoSettings: [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.videoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoMaxKeyFrameIntervalKey: Int(settings.frameRate),
                AVVideoMaxKeyFrameIntervalDurationKey: settings.segmentSeconds,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: Int(settings.frameRate),
            ] as [String: Any],
        ]
    }

    var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: settings.audioBitRate,
        ]
    }

    var pixelBufferAttributes: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: settings.width,
            kCVPixelBufferHeightKey as String: settings.height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
    }

    /// 굽기를 시작한다. `host` 가 시간줄 0 이다.
    func start(at host: Double) throws {
        try queue.sync { try begin(at: host) }
    }

    private func begin(at host: Double) throws {
        guard state == .idle else { return }
        let writer = AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue) ?? .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: settings.segmentSeconds, preferredTimescale: 1_000)
        writer.initialSegmentStartTime = Self.timeOffset
        writer.delegate = self

        let videoSettings = self.videoSettings
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw Failure.unsupported("video settings")
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = settings.realTime
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: pixelBufferAttributes)
        guard writer.canAdd(video) else { throw Failure.unsupported("video input") }
        writer.add(video)

        var description = AudioStreamBasicDescription(
            mSampleRate: settings.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else {
            throw Failure.unsupported("audio format")
        }
        let audioSettings = self.audioSettings
        guard writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
            throw Failure.unsupported("audio settings")
        }
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: format)
        audio.expectsMediaDataInRealTime = settings.realTime
        guard writer.canAdd(audio) else { throw Failure.unsupported("audio input") }
        writer.add(audio)

        guard writer.startWriting() else {
            throw Failure.writer(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: Self.timeOffset)

        self.writer = writer
        videoInput = video
        audioInput = audio
        self.adaptor = adaptor
        audioFormat = format
        pool = adaptor.pixelBufferPool ?? makePool()
        startHost = host
        timeline = StageAudioTimeline(rate: settings.sampleRate, start: host)
        staged = 0
        stagedStart = 0
        lastFrameIndex = -1
        state = .writing

        if settings.realTime {
            // 그림이 잠깐 밀려도 소리는 따로 꾸준히 넣는다.
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.02, repeating: .milliseconds(20), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.pump(until: HostClock.now()) }
            timer.resume()
            pumpTimer = timer
        }
    }

    private func makePool() -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        _ = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes as CFDictionary, &pool)
        return pool
    }

    /// 프레임 하나를 넣는다. `host` 는 그 장면을 그린 호스트 시각이고, 30fps 눈금에 맞춰 시각을 붙인다.
    func appendVideo(_ buffer: CVPixelBuffer, at host: Double) {
        pendingLock.withLock { $0 += 1 }
        queue.async {
            self.pendingLock.withLock { $0 -= 1 }
            self.writeVideo(buffer, at: host)
        }
    }

    /// 넣어 둔 일이 다 끝날 때까지 기다린다. 검사에서 쓴다.
    func drain() {
        queue.sync {}
    }

    /// 탭이 담아 둔 소리를 `host` 시각까지 시간줄에 놓는다. 실제 시간에서는 타이머가 부른다.
    func pumpAudio(until host: Double) {
        queue.async { self.pump(until: host) }
    }

    private func writeVideo(_ buffer: CVPixelBuffer, at host: Double) {
        guard state == .writing, let video = videoInput, let adaptor else { return }
        guard writer?.status == .writing else { return fail() }
        pump(until: host)
        guard state == .writing else { return }
        let index = Int64(((host - startHost) * Double(settings.frameRate)).rounded())
        guard index > lastFrameIndex, index >= 0 else { return }
        if !video.isReadyForMoreMediaData {
            guard !settings.realTime, waitUntilReady(video) else {
                framesDropped += 1
                return
            }
        }
        let time = CMTimeAdd(Self.timeOffset, CMTime(value: index, timescale: settings.frameRate))
        if adaptor.append(buffer, withPresentationTime: time) {
            lastFrameIndex = index
            framesAppended += 1
        } else {
            fail()
        }
    }

    private func waitUntilReady(_ input: AVAssetWriterInput) -> Bool {
        var waited = 0.0
        while !input.isReadyForMoreMediaData, waited < 5, state == .writing || state == .finishing {
            usleep(2_000)
            waited += 0.002
        }
        return input.isReadyForMoreMediaData
    }

    private func pump(until host: Double) {
        guard state == .writing || state == .finishing else { return }
        let rate = settings.sampleRate
        while let chunk = ring.read(into: readBuffer, maxFrames: Self.readCapacity) {
            var source = UnsafePointer(readBuffer)
            var frames = chunk.frames
            if abs(chunk.rate - rate) > 0.5, chunk.rate > 0 {
                frames = Self.resample(readBuffer, frames: chunk.frames, from: chunk.rate, to: rate,
                                       into: resampleBuffer, capacity: Self.resampleCapacity)
                source = UnsafePointer(resampleBuffer)
            }
            guard frames > 0 else { continue }
            let placement = timeline.place(host: chunk.host, frames: frames)
            if placement.silence > 0 { stageSilence(placement.silence) }
            if placement.repeatFirst { stage(source, count: 1) }
            let skip = min(placement.skip, frames)
            if frames > skip { stage(source + skip * 2, count: frames - skip) }
        }
        let due = timeline.silenceDue(at: host, latency: Self.audioLatency)
        if due > 0 { stageSilence(due) }
        flushStaged()
    }

    private func stage(_ source: UnsafePointer<Float>, count: Int) {
        var offset = 0
        while offset < count, state == .writing || state == .finishing {
            if staged == stagingCapacity { flushStaged(force: true) }
            let take = min(count - offset, stagingCapacity - staged)
            guard take > 0 else { return }
            (staging + staged * 2).update(from: source + offset * 2, count: take * 2)
            staged += take
            offset += take
            timeline.advance(take)
        }
    }

    private func stageSilence(_ count: Int) {
        var left = count
        while left > 0, state == .writing || state == .finishing {
            if staged == stagingCapacity { flushStaged(force: true) }
            let take = min(left, stagingCapacity - staged)
            guard take > 0 else { return }
            (staging + staged * 2).update(repeating: 0, count: take * 2)
            staged += take
            left -= take
            timeline.advance(take)
        }
    }

    /// 모아 둔 소리를 넣는다. 엔코더가 아직 받을 수 없으면 다음으로 미루고, 칸이 다 찼는데도 못 받으면 버린다.
    private func flushStaged(force: Bool = false) {
        guard staged > 0, let audio = audioInput, let format = audioFormat else { return }
        guard writer?.status == .writing else { return fail() }
        if !audio.isReadyForMoreMediaData {
            let ready = !settings.realTime && waitUntilReady(audio)
            if !ready {
                guard force else { return }
                stagedStart += Int64(staged)
                staged = 0
                return
            }
        }
        let frames = staged
        let bytes = frames * 2 * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block,
              CMBlockBufferAssureBlockMemory(block) == kCMBlockBufferNoErr,
              CMBlockBufferReplaceDataBytes(with: staging, blockBuffer: block, offsetIntoDestination: 0,
                                            dataLength: bytes) == kCMBlockBufferNoErr else { return fail() }
        let time = CMTimeAdd(Self.timeOffset, CMTime(value: stagedStart, timescale: CMTimeScale(settings.sampleRate.rounded())))
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                                                                   formatDescription: format, sampleCount: frames,
                                                                   presentationTimeStamp: time, packetDescriptions: nil,
                                                                   sampleBufferOut: &sample) == noErr,
              let sample else { return fail() }
        guard audio.append(sample) else { return fail() }
        stagedStart += Int64(frames)
        audioFramesAppended += Int64(frames)
        staged = 0
    }

    /// 표본율이 다른 덩어리를 선형 보간으로 맞춘다. 장치를 바꿔 표본율이 달라졌을 때만 쓴다.
    static func resample(_ input: UnsafePointer<Float>, frames: Int, from: Double, to: Double,
                         into output: UnsafeMutablePointer<Float>, capacity: Int) -> Int {
        guard frames > 1, from > 0, to > 0 else { return 0 }
        let count = min(capacity, Int((Double(frames) * to / from).rounded()))
        let step = from / to
        for index in 0..<count {
            let position = Double(index) * step
            let lower = min(frames - 1, Int(position))
            let upper = min(frames - 1, lower + 1)
            let t = Float(position - Double(lower))
            output[index * 2] = input[lower * 2] + (input[upper * 2] - input[lower * 2]) * t
            output[index * 2 + 1] = input[lower * 2 + 1] + (input[upper * 2 + 1] - input[lower * 2 + 1]) * t
        }
        return count
    }

    /// 남은 소리를 넣고 마지막 조각까지 내보낸다. 끝나면 엔코더 큐에서 `completion` 을 부른다.
    func finish(completion: (() -> Void)? = nil) {
        queue.async {
            self.pumpTimer?.cancel()
            self.pumpTimer = nil
            guard self.state == .writing, let writer = self.writer, writer.status == .writing else {
                completion?()
                return
            }
            self.state = .finishing
            // 그림을 먼저 닫아야 엔코더가 남은 소리를 기다림 없이 받는다.
            self.videoInput?.markAsFinished()
            self.pump(until: self.startHost + Double(self.lastFrameIndex + 1) / Double(self.settings.frameRate) + Self.audioLatency)
            self.flushStaged()
            guard self.state == .finishing, writer.status == .writing else {
                completion?()
                return
            }
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                self.queue.async {
                    if self.state == .finishing { self.state = .finished }
                    completion?()
                }
            }
        }
    }

    private func fail() {
        guard state == .writing || state == .finishing else { return }
        state = .failed
        staged = 0
        pumpTimer?.cancel()
        pumpTimer = nil
        let message = writer?.error?.localizedDescription ?? "writer"
        if writer?.status == .writing { writer?.cancelWriting() }
        onFailure?(message)
    }

    // MARK: AVAssetWriterDelegate

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType,
                     segmentReport: AVAssetSegmentReport?) {
        switch segmentType {
        case .initialization:
            store.setInitialization(segmentData)
        case .separable:
            let reports = segmentReport?.trackReports ?? []
            let timing = reports.first { $0.mediaType == .video } ?? reports.first
            let seconds = timing.map { CMTimeGetSeconds($0.duration) } ?? settings.segmentSeconds
            store.append(segmentData, duration: seconds.isFinite && seconds > 0 ? seconds : settings.segmentSeconds)
        @unknown default:
            break
        }
    }
}
