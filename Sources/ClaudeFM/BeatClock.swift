import Foundation

/// 오디오 파장에서 읽은 실시간 보컬 필링(외침·속삭임·파장·박자).
struct VocalFeeling: Equatable {
    /// 순간 파장 진폭 (0...1)
    var wave: Double = 0
    /// 소리질러야 하는 부분 / 고음 벨팅 강도 (0...1)
    var shout: Double = 0
    /// 속삭이거나 여리게 부르는 부분 강도 (0...1)
    var whisper: Double = 0
    /// 박자 점프 반동 (0...1)
    var beat: Double = 0
    /// 저음 울림 (0...1)
    var bass: Double = 0
    /// 실시간 흔들림·파장 위상 (초 단위)
    var phase: Double = 0
    /// 마지막 박에서 지난 시간(초). 박을 못 잡았으면 크다. 말풍선 글자 물결과 출렁임에 쓴다.
    var sinceBeat: Double = 10
    /// 지금 분위기.
    var mood = MusicMood.quiet
    /// 옥타브 대역 여덟 개의 세기(0...1). 말풍선 아래 목소리 무늬에 쓴다.
    var bands: [Double] = []

    static let calm = VocalFeeling()
}

/// 짧은 구간의 대역 에너지로 박을 찾는다. 샘플은 받지 않고, 이미 구한 에너지만 본다.
/// 시각은 호출하는 쪽이 같은 시계로 넘긴다.
struct BeatClock {
    /// 전체 대역의 진폭 제곱 평균이 이보다 작으면 무음이다.
    static let audibleEnergy = 8e-6

    private(set) var beatCount = 0
    /// 잔잔한 구간 뒤에 저음과 함께 크게 터진 순간(드롭)을 센다. 가사가 없는 곡의 폭죽에 쓴다.
    private(set) var surgeCount = 0
    private var lastQuiet = -1.0
    private var lastSurge = -1_000.0

    private var prevLow = 0.0
    private var prevHigh = 0.0
    private var prevFull = 0.0
    private var lowFluxAvg = 0.0
    private var highFluxAvg = 0.0
    private var fullFluxAvg = 0.0
    private var lastBeat = -1.0
    /// 다음 박을 셀 기준 시각. 채워 넣은 박 뒤에 늦게 온 진짜 타격으로 옮겨 갈 수 있다.
    private var gridBeat = -1.0
    private var lastBeatPredicted = false
    private var lastLoud = -1.0
    private var danceSince = -1.0
    private var stepRight = false
    private var intervals: [Double] = []
    private var period: Double?
    private var lowEnv = 0.0
    private var highEnv = 0.0
    private var fullEnv = 0.0
    private var vocalAvg = 8e-4
    private var vocalHighAvg = 2.5e-4
    private var waveEnv = 0.0
    private var shoutEnv = 0.0
    private var whisperEnv = 0.0
    private var bassEnv = 0.0
    private(set) var mood = MusicMood.quiet
    private var pendingMood = MusicMood.quiet
    private var pendingSince = -1.0

    /// 박 간격이 안정됐을 때의 빠르기(BPM). 아직 박을 못 잡았으면 nil.
    var tempo: Double? { period.map { 60 / $0 } }

    /// 박 간격(초). 아직 박을 못 잡았으면 nil.
    var beatPeriod: Double? { period }

    /// 지금 박 안에서 얼마나 지났는지(0...1). 박을 못 잡았으면 0.
    func beatPhase(at now: Double) -> Double {
        guard lastBeat >= 0, let period, period > 0 else { return 0 }
        return min(1, max(0, (now - lastBeat) / period))
    }

    /// 사람이 세는 빠르기에 가깝게 반이나 두 배로 접는다.
    static func foldBPM(_ tempo: Double?) -> Int? {
        guard var value = tempo, value.isFinite, value > 0 else { return nil }
        while value < 70 { value *= 2 }
        while value > 180 { value /= 2 }
        return Int(value.rounded())
    }

    mutating func ingest(low: Double, high: Double, full: Double, dt: Double, now: Double) {
        let lowFlux = max(0, low - prevLow)
        let highFlux = max(0, high - prevHigh)
        let fullFlux = max(0, full - prevFull)
        prevLow = low
        prevHigh = high
        prevFull = full

        if full >= Self.audibleEnergy {
            if lastLoud < 0 || now - lastLoud >= 2.2 {
                danceSince = now
            } else if danceSince < 0 {
                danceSince = now
            }
            lastLoud = now
        }

        let since = lastBeat < 0 ? 1_000.0 : now - lastBeat
        // 저음(킥)을 우선하고, 중고음 타격도 받아 베이스가 약한 곡도 따라간다.
        let lowHit = lowFlux > max(lowFluxAvg * 1.65, 5e-7) && low >= 2e-6
        let highHit = highFlux > max(highFluxAvg * 2.1, 1e-6) && high >= 4e-6
        let fullHit = fullFlux > max(fullFluxAvg * 1.9, 3e-6) && full >= 2e-5
        let onset = lowHit || highHit || fullHit
        var hit = onset && since >= 0.18
        var predicted = false
        let sinceGrid = gridBeat < 0 ? 1_000.0 : now - gridBeat
        if !hit, onset, lastBeatPredicted, since < 0.18 {
            // 채워 넣은 박 바로 뒤에 진짜 타격이 오면, 다시 뛰지 않고 다음 박을 셀 기준만 그 타격으로 옮긴다.
            gridBeat = now
            lastBeatPredicted = false
        } else if !hit, let period, full >= Self.audibleEnergy, sinceGrid >= period * 1.02, sinceGrid <= period * 1.14 {
            // 박이 안정되면, 타격이 묻힌 박도 그 간격으로 한 번 더 밟는다. 제 박보다 먼저 밟지 않는다.
            hit = true
            predicted = true
        }

        if hit {
            if lastBeat >= 0, !predicted {
                let interval = now - lastBeat
                if (0.22...1.1).contains(interval) {
                    intervals.append(interval)
                    if intervals.count > 6 { intervals.removeFirst(intervals.count - 6) }
                    period = Self.stablePeriod(intervals)
                }
            }
            lastBeat = now
            gridBeat = now
            lastBeatPredicted = predicted
            stepRight.toggle()
            beatCount += 1
        }

        let follow = 1 - exp(-max(dt, 0) / 0.45)
        lowFluxAvg += follow * (lowFlux - lowFluxAvg)
        highFluxAvg += follow * (highFlux - highFluxAvg)
        fullFluxAvg += follow * (fullFlux - fullFluxAvg)

        // 타격은 바로 올리고, 없으면 0.55초 정도로 내려 분위기가 박마다 떨리지 않게 한다.
        lowEnv = Self.rise(lowEnv, low, dt)
        highEnv = Self.rise(highEnv, high, dt)
        fullEnv = Self.rise(fullEnv, full, dt)

        // 곡 전체의 평균 음량을 천천히 따라가면서, 상대적으로 소리치는 구간과 속삭이는 구간을 잡는다.
        if full >= Self.audibleEnergy {
            let avgFollow = 1 - exp(-max(dt, 0) / 4.2)
            vocalAvg += avgFollow * (full - vocalAvg)
            vocalHighAvg += avgFollow * (high - vocalHighAvg)
        }
        let rms = sqrt(max(0, full))
        let highRms = sqrt(max(0, high))
        let lowRms = sqrt(max(0, low))
        let avgRms = sqrt(max(Self.audibleEnergy * 4, vocalAvg))
        let avgHighRms = sqrt(max(Self.audibleEnergy * 1.5, vocalHighAvg))

        let targetWave = full >= Self.audibleEnergy
            ? min(1.0, max(0, rms / max(avgRms * 1.55, 0.014)))
            : 0.0
        waveEnv = Self.smooth(waveEnv, targetWave, dt: dt, attack: 0.035, release: 0.14)

        let targetBass = full >= Self.audibleEnergy
            ? min(1.0, max(0, lowRms / max(avgRms * 1.3, 0.012)))
            : 0.0
        bassEnv = Self.smooth(bassEnv, targetBass, dt: dt, attack: 0.04, release: 0.18)

        var targetShout = 0.0
        var targetWhisper = 0.0
        if full >= Self.audibleEnergy {
            let relFull = rms / max(avgRms, 0.008)
            let relHigh = highRms / max(avgHighRms, 0.004)
            let surge = max(relFull, relHigh * 1.08)
            if (surge > 1.18 && full >= Self.audibleEnergy * 4) || rms >= 0.052 {
                let relComponent = max(0, (surge - 1.15) / 0.72)
                let absComponent = max(0, (rms - 0.045) * 6.5)
                targetShout = min(1.0, max(relComponent, absComponent))
            } else if relFull < 0.76 || rms < 0.016 {
                let relQuiet = 1.0 - min(1.0, max(0, (relFull - 0.24) / 0.52))
                let absQuiet = 1.0 - min(1.0, max(0, (rms - 0.003) / 0.015))
                targetWhisper = min(1.0, max(relQuiet * 0.9, absQuiet * 0.82))
            }
        }
        shoutEnv = Self.smooth(shoutEnv, targetShout, dt: dt, attack: 0.05, release: 0.34)
        whisperEnv = targetShout > 0.15
            ? Self.smooth(whisperEnv, 0, dt: dt, attack: 0.04, release: 0.05)
            : Self.smooth(whisperEnv, targetWhisper, dt: dt, attack: 0.14, release: 0.38)

        let audible = lastLoud >= 0 && now - lastLoud < 1.8
        detectSurge(hit: hit, audible: audible, now: now)
        let next: MusicMood = audible
            ? Self.classify(low: lowEnv, high: highEnv, full: fullEnv, period: period)
            : .quiet
        updateMood(next, now: now)
    }

    /// 숨을 죽인 구간(평소보다 작은 소리)이 몇 초 안에 있었고, 박과 함께 저음이 크게 들어오면 드롭으로 본다.
    /// 춤춘 지 20초는 지나야 하고, 한 번 터지면 40초는 쉰다.
    private mutating func detectSurge(hit: Bool, audible: Bool, now: Double) {
        guard audible else { return }
        if waveEnv < 0.32 { lastQuiet = now }
        guard hit, shoutEnv > 0.62, bassEnv > 0.55, lastQuiet >= 0, now - lastQuiet < 6,
              danceSince >= 0, now - danceSince > 20, now - lastSurge > 40 else { return }
        lastSurge = now
        surgeCount += 1
    }

    func pose(at now: Double) -> DancePose {
        // 콜백이 끊겨도, 마지막으로 들은 시각이 지나면 분위기를 끈다.
        let shown = lastLoud >= 0 && now - lastLoud < 1.8 ? mood : .quiet
        let duration = (shown != .quiet && danceSince >= 0) ? max(0, now - danceSince) : 0
        let style = shown != .quiet
            ? Self.selectDanceStyle(duration: duration, beatCount: beatCount, mood: shown, now: now)
            : .bounce
        guard lastBeat >= 0 else {
            return DancePose(active: shown != .quiet, mood: shown, style: style, danceTime: duration)
        }
        let sinceBeat = now - lastBeat
        let sinceLoud = lastLoud < 0 ? 1_000 : now - lastLoud
        // 소리가 끊기면 곧 멈추고, 박 사이가 너무 길어도 점프만 멈추되 춤 동작과 미러볼은 유지한다.
        guard sinceBeat >= 0, sinceBeat < 1.35, sinceLoud < 0.6 else {
            return DancePose(active: sinceLoud < 0.8 && shown != .quiet, mood: shown, style: style, danceTime: duration)
        }
        return DancePose(
            active: true,
            hop: exp(-sinceBeat / hopTau),
            stepRight: stepRight,
            mood: shown,
            style: style,
            danceTime: duration
        )
    }

    /// 춤추는 시간이 길어질수록 더 다채로운 안무(만세·웨이브·문워크·턴·디스코 피버)를 해금해 순환한다.
    static func selectDanceStyle(duration: Double, beatCount: Int, mood: MusicMood, now: Double) -> DanceStyle {
        let phrase = max(beatCount / 6, Int(duration / 3.2))
        if duration < 4.0 {
            return .bounce
        } else if duration < 9.0 {
            let pool: [DanceStyle] = [.bounce, .handsUp, .waveTilt]
            return pool[phrase % pool.count]
        } else if duration < 16.0 {
            let pool: [DanceStyle] = [.handsUp, .waveTilt, .moonwalk, .bounce, .discoFever]
            return pool[phrase % pool.count]
        } else {
            let pool: [DanceStyle] = mood == .calm
                ? [.waveTilt, .moonwalk, .bounce, .discoFever]
                : [.discoFever, .handsUp, .moonwalk, .spinJump, .waveTilt, .bounce]
            return pool[phrase % pool.count]
        }
    }

    /// 말풍선에 실시간으로 반영할 보컬 필링(파장·외침·속삭임·박자).
    func feeling(at now: Double) -> VocalFeeling {
        let sinceLoud = lastLoud < 0 ? 1_000.0 : max(0, now - lastLoud)
        guard sinceLoud < 1.2 else { return .calm }
        let fade = sinceLoud < 0.35 ? 1.0 : exp(-(sinceLoud - 0.35) / 0.35)
        let sinceBeat = lastBeat < 0 ? 1_000.0 : max(0, now - lastBeat)
        let beatHop = sinceBeat < 1.0 ? exp(-sinceBeat / hopTau) : 0.0
        return VocalFeeling(
            wave: min(1.0, waveEnv * fade),
            shout: min(1.0, shoutEnv * fade),
            whisper: min(1.0, whisperEnv * fade),
            beat: min(1.0, beatHop * fade),
            bass: min(1.0, bassEnv * fade),
            phase: now,
            sinceBeat: sinceBeat,
            mood: mood
        )
    }

    private static func smooth(_ current: Double, _ target: Double, dt: Double, attack: Double, release: Double) -> Double {
        let tau = target >= current ? attack : release
        let alpha = 1 - exp(-max(dt, 0) / max(tau, 0.005))
        return current + alpha * (target - current)
    }

    /// 저음·고음·세기·박 간격. 빠르면 들썩임, 저음이 크면 울림, 고음이 크면 밝음, 작고 느리면 잔잔함.
    static func classify(low: Double, high: Double, full: Double, period: Double?) -> MusicMood {
        let fast = period.map { $0 < 0.4 } ?? false
        let slow = period.map { $0 > 0.62 } ?? false
        if fast && full >= 4e-4 { return .drive }
        if low >= high * 2 && low >= 3e-5 { return .bass }
        if high >= low * 1.7 && high >= 3e-5 { return .bright }
        if full >= 4e-3 { return .drive }
        if slow || full < 2.5e-4 { return .calm }
        return .groove
    }

    /// 잔잔함은 짧게 뜨고, 저음은 눌림이 길고, 빠름은 톡 튄다.
    private var hopTau: Double {
        switch mood {
        case .calm: return 0.2
        case .bass: return 0.18
        case .drive: return 0.08
        default: return 0.14
        }
    }

    private static func rise(_ env: Double, _ value: Double, _ dt: Double) -> Double {
        if value >= env { return value }
        return env * exp(-max(dt, 0) / 0.55)
    }

    private mutating func updateMood(_ next: MusicMood, now: Double) {
        if next == mood {
            pendingMood = next
            return
        }
        // 무음에서 나오거나 무음으로 돌아갈 때는 바로 바꾼다.
        if next == .quiet || mood == .quiet {
            mood = next
            pendingMood = next
            pendingSince = now
            return
        }
        if next != pendingMood {
            pendingMood = next
            pendingSince = now
            return
        }
        if now - pendingSince >= 0.75 { mood = next }
    }

    private static func stablePeriod(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let mid = sorted[sorted.count / 2]
        guard mid > 0.22, sorted.last! - sorted.first! < mid * 0.2 else { return nil }
        return mid
    }
}
