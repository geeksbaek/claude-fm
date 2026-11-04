import CoreAudio
import Foundation
import os

/// 컴퓨터에서 재생 중인 소리를 사적인 프로세스 탭으로 받아 대역 에너지만 넘긴다.
/// 평소에는 음소거하지 않아서 들리던 소리는 그대로 들리고, 샘플은 저장하지 않는다.
/// 무대를 TV 로 보내는 동안에만 소리를 그대로 TV 로 넘기고(`setSink`), 이 Mac 에서는 끈다(`muted`).
final class SystemAudioTap: @unchecked Sendable {
    struct Chunk {
        var low: Double
        var high: Double
        var full: Double
        var dt: Double
        /// 옥타브 대역 여덟 개의 진폭 제곱 평균. 무대 전광판에 쓴다.
        var bands: SIMD8<Double> = .zero
    }

    /// 메인 큐에서 호출된다.
    var onChunk: ((Chunk) -> Void)?

    private let bucket = OSAllocatedUnfairLock(initialState: Bucket())
    private let running = OSAllocatedUnfairLock(initialState: false)
    /// TV 로 넘길 PCM 을 받을 곳. 탭 콜백에서 읽는다.
    private let sink = OSAllocatedUnfairLock<StageAudioRing?>(initialState: nil)
    private let rate = OSAllocatedUnfairLock<Double?>(initialState: nil)
    private var filters = BandSplit(sampleRate: 48_000)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    /// 탭이 받는 동안 이 Mac 의 소리를 끈다. 세션 큐에서만 바꾼다.
    private var muted = false
    private let debug = ProcessInfo.processInfo.environment["CLAUDE_FM_DEBUG"] != nil
    /// 장치 시작은 메인 스레드를 붙잡는다. 권한 창이나 이전 탭 정리가 메인을 기다리면 메뉴바가 안 뜬다.
    private let session = DispatchQueue(label: "io.github.geeksbaek.claude-fm.rhythm")

    private static let aggregateUID = "io.github.geeksbaek.claude-fm.rhythm"

    /// 탭을 (다시) 연다. `muted` 를 주면 그 방식으로 바꿔 연다. 주지 않으면 지난번 방식 그대로.
    @available(macOS 14.2, *)
    func start(muted: Bool? = nil) {
        // 탭 콜백이 처음 시각을 바꿀 때 시계 눈금을 구하느라 멈추지 않게 미리 구해 둔다.
        _ = HostClock.secondsPerTick
        session.async {
            if let muted { self.muted = muted }
            self.open()
        }
    }

    /// TV 로 보낼 PCM 을 받을 곳을 단다. nil 이면 뗀다.
    func setSink(_ ring: StageAudioRing?) {
        sink.withLock { $0 = ring }
    }

    /// 지금 탭의 표본율. 탭이 열려 있지 않으면 nil.
    var sampleRate: Double? { rate.withLock { $0 } }

    @available(macOS 14.2, *)
    func stop() {
        session.sync { self.close() }
    }

    @available(macOS 14.2, *)
    private func open() {
        close()
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Claude FM Rhythm"
        description.isPrivate = true
        // TV 로 보내는 동안에는 탭이 받는 동안만 이 Mac 의 소리를 끈다. 탭이 멈추거나 앱이 끝나면 소리는 저절로 돌아온다.
        description.muteBehavior = muted ? .mutedWhenTapped : .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr, newTap != kAudioObjectUnknown else {
            NSLog("[ClaudeFM] process tap failed: \(Self.statusText(tapStatus))")
            return
        }
        tapID = newTap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Claude FM Rhythm",
            kAudioAggregateDeviceUIDKey: Self.aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: 0,
                ],
            ],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate)
        guard aggregateStatus == noErr, newAggregate != kAudioObjectUnknown else {
            NSLog("[ClaudeFM] aggregate device failed: \(Self.statusText(aggregateStatus))")
            AudioHardwareDestroyProcessTap(newTap)
            tapID = kAudioObjectUnknown
            return
        }
        aggregateID = newAggregate

        guard let stream = Self.inputFormat(of: newAggregate) else {
            NSLog("[ClaudeFM] tap has no input format")
            close()
            return
        }
        guard stream.mFormatID == kAudioFormatLinearPCM,
              stream.mBitsPerChannel == 32,
              (stream.mFormatFlags & kAudioFormatFlagIsFloat) != 0 else {
            NSLog("[ClaudeFM] unexpected tap format: \(stream.mSampleRate) Hz \(stream.mBitsPerChannel)-bit flags \(stream.mFormatFlags)")
            close()
            return
        }
        format = stream
        filters = BandSplit(sampleRate: stream.mSampleRate)
        let sampleRate = stream.mSampleRate
        rate.withLock { $0 = sampleRate }
        if debug {
            let interleaved = (stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            NSLog("[ClaudeFM] tap \(stream.mSampleRate) Hz \(stream.mChannelsPerFrame) ch \(interleaved ? "interleaved" : "planar")\(muted ? " muted" : "")")
        }

        var newProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProc, newAggregate, nil) { [weak self] _, input, inputTime, _, _ in
            self?.consume(input, time: inputTime)
        }
        guard procStatus == noErr, let newProc else {
            NSLog("[ClaudeFM] IO proc failed: \(Self.statusText(procStatus))")
            close()
            return
        }
        procID = newProc
        running.withLock { $0 = true }
        let startStatus = AudioDeviceStart(newAggregate, newProc)
        guard startStatus == noErr else {
            NSLog("[ClaudeFM] tap start failed: \(Self.statusText(startStatus))")
            close()
            return
        }
        if debug { NSLog("[ClaudeFM] tap running") }
    }

    @available(macOS 14.2, *)
    private func close() {
        running.withLock { $0 = false }
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        rate.withLock { $0 = nil }
        bucket.withLock { $0 = Bucket() }
    }

    /// 기본 출력 장치로 지금 소리가 나가는 중인지. 탭이 무음일 때 권한 안내를 띄울지 가릴 때 쓴다.
    static func defaultOutputIsRunning() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private func consume(_ input: UnsafePointer<AudioBufferList>, time: UnsafePointer<AudioTimeStamp>) {
        guard running.withLock({ $0 }) else { return }
        forward(input, time: time)
        let (low, high, full, bands, frames) = filters.energies(input, format: format)
        guard frames > 0 else { return }
        let dt = Double(frames) / format.mSampleRate
        let shouldFlush = bucket.withLock { bucket -> Bool in
            bucket.low = max(bucket.low, low)
            bucket.high = max(bucket.high, high)
            bucket.full = max(bucket.full, full)
            bucket.bands = pointwiseMax(bucket.bands, bands)
            bucket.dt += dt
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            // 박의 타격이 평균에 묻히지 않도록, 세기가 튀면 주기를 기다리지 않고 올린다.
            let strike = low > max(bucket.sentLow * 2.5, 2e-6)
            if bucket.armed || (!strike && now &- bucket.lastNotify < 16_000_000) { return false }
            bucket.armed = true
            bucket.lastNotify = now
            return true
        }
        guard shouldFlush else { return }
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    /// TV 로 보내는 동안 받은 소리를 그대로 넘긴다. 입력 시각(호스트 시각)을 같이 붙여 그림과 맞춘다.
    /// 실시간 스레드라 미리 잡아 둔 칸에 복사만 한다.
    private func forward(_ input: UnsafePointer<AudioBufferList>, time: UnsafePointer<AudioTimeStamp>) {
        guard let ring = sink.withLock({ $0 }) else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData, first.mDataByteSize > 0, format.mSampleRate > 0 else { return }
        let stamp = time.pointee
        let host = stamp.mFlags.contains(.hostTimeValid) ? HostClock.seconds(stamp.mHostTime) : HostClock.now()
        let left = UnsafePointer(data.assumingMemoryBound(to: Float.self))
        if (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            var right = left
            if buffers.count > 1, let second = buffers[1].mData, buffers[1].mDataByteSize >= first.mDataByteSize {
                right = UnsafePointer(second.assumingMemoryBound(to: Float.self))
            }
            ring.write(left: left, right: right, stride: 1, frames: frames, host: host, rate: format.mSampleRate)
        } else {
            let stride = max(Int(first.mNumberChannels), 1)
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * stride)
            ring.write(left: left, right: stride > 1 ? left + 1 : left, stride: stride, frames: frames, host: host,
                       rate: format.mSampleRate)
        }
    }

    private func flush() {
        let chunk: Chunk? = bucket.withLock { bucket in
            bucket.armed = false
            guard bucket.dt > 0 else { return nil }
            let chunk = Chunk(low: bucket.low, high: bucket.high, full: bucket.full, dt: bucket.dt, bands: bucket.bands)
            let lastNotify = bucket.lastNotify
            bucket = Bucket()
            bucket.lastNotify = lastNotify
            bucket.sentLow = chunk.low
            return chunk
        }
        if let chunk { onChunk?(chunk) }
    }

    private static func inputFormat(of device: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return nil }
        return format
    }

    private static func statusText(_ status: OSStatus) -> String {
        let code = UInt32(bitPattern: status)
        let bytes = [UInt8(truncatingIfNeeded: code >> 24), UInt8(truncatingIfNeeded: code >> 16),
                     UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        if bytes.allSatisfy({ (32..<127).contains($0) }), let text = String(bytes: bytes, encoding: .ascii) {
            return "\(status) '\(text)'"
        }
        return "\(status)"
    }

    private struct Bucket {
        var low = 0.0
        var high = 0.0
        var full = 0.0
        var dt = 0.0
        var bands = SIMD8<Double>.zero
        var sentLow = 0.0
        var armed = false
        var lastNotify: UInt64 = 0
    }
}

/// 모노로 섞은 뒤 킥 대역과 심벌 대역, 옥타브 대역 여덟 개의 에너지를 구한다. IO 콜백 안에서만 상태를 갱신한다.
private struct BandSplit {
    private var lowpass: Biquad
    private var highpass: Biquad
    private var octaves: [Biquad]

    init(sampleRate: Double) {
        let rate = max(sampleRate, 8_000)
        lowpass = Biquad.lowpass(frequency: 140, q: 0.707, sampleRate: rate)
        highpass = Biquad.highpass(frequency: 2_000, q: 0.707, sampleRate: rate)
        // 나이퀴스트에 너무 가까운 대역은 표본율에 맞춰 낮춘다.
        octaves = SpectrumMeter.centers.map { center in
            Biquad.bandpass(frequency: min(center, rate * 0.42), q: 1.41, sampleRate: rate)
        }
    }

    mutating func energies(_ input: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> (Double, Double, Double, SIMD8<Double>, Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mData != nil, first.mDataByteSize > 0 else { return (0, 0, 0, .zero, 0) }
        let channels = Int(format.mChannelsPerFrame)
        guard channels > 0 else { return (0, 0, 0, .zero, 0) }
        let planar = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let frames: Int
        if planar {
            frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        } else {
            frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(Int(first.mNumberChannels), 1))
        }
        guard frames > 0 else { return (0, 0, 0, .zero, 0) }

        var lowSum = 0.0, highSum = 0.0, fullSum = 0.0
        var bandSums = SIMD8<Double>.zero
        let bandCount = min(octaves.count, 8)
        func consume(_ sample: Double) {
            let low = lowpass.process(sample)
            let high = highpass.process(sample)
            lowSum += low * low
            highSum += high * high
            fullSum += sample * sample
            for band in 0..<bandCount {
                let value = octaves[band].process(sample)
                bandSums[band] += value * value
            }
        }

        if planar {
            let count = min(buffers.count, channels)
            for frame in 0..<frames {
                var sum = 0.0
                for channel in 0..<count {
                    guard let data = buffers[channel].mData else { continue }
                    sum += Double(data.assumingMemoryBound(to: Float.self)[frame])
                }
                consume(sum / Double(count))
            }
        } else if let data = first.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            let stride = max(Int(first.mNumberChannels), 1)
            for frame in 0..<frames {
                var sum = 0.0
                for channel in 0..<stride { sum += Double(samples[frame * stride + channel]) }
                consume(sum / Double(stride))
            }
        }

        let scale = 1 / Double(frames)
        return (lowSum * scale, highSum * scale, fullSum * scale, bandSums * scale, frames)
    }
}

private struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = 0.0, z2 = 0.0

    static func lowpass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        coefficients(frequency: frequency, q: q, sampleRate: sampleRate, lowpass: true)
    }

    static func highpass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        coefficients(frequency: frequency, q: q, sampleRate: sampleRate, lowpass: false)
    }

    /// 가운데 주파수에서 이득이 1 인 대역 통과.
    static func bandpass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        var filter = Biquad()
        filter.b0 = alpha / a0
        filter.b1 = 0
        filter.b2 = -alpha / a0
        filter.a1 = (-2 * cos(w0)) / a0
        filter.a2 = (1 - alpha) / a0
        return filter
    }

    private static func coefficients(frequency: Double, q: Double, sampleRate: Double, lowpass: Bool) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        var filter = Biquad()
        if lowpass {
            filter.b0 = ((1 - cosw) / 2) / a0
            filter.b1 = (1 - cosw) / a0
            filter.b2 = ((1 - cosw) / 2) / a0
        } else {
            filter.b0 = ((1 + cosw) / 2) / a0
            filter.b1 = (-(1 + cosw)) / a0
            filter.b2 = ((1 + cosw) / 2) / a0
        }
        filter.a1 = (-2 * cosw) / a0
        filter.a2 = (1 - alpha) / a0
        return filter
    }

    mutating func process(_ sample: Double) -> Double {
        let output = b0 * sample + z1
        z1 = b1 * sample - a1 * output + z2
        z2 = b2 * sample - a2 * output
        return output
    }
}
