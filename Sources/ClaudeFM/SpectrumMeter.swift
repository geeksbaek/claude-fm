import Foundation

/// 옥타브 대역 여덟 개(63 Hz … 8 kHz)의 세기를 무대 전광판에 맞게 0...1 로 맞춘다.
/// 가장 큰 대역을 천천히 따라가며 바닥을 정해서, 곡 전체 음량과 상관없이 모양이 살아 있게 한다.
struct SpectrumMeter {
    static let bandCount = 8
    static let centers: [Double] = [63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]
    /// 바닥에서 꼭대기까지의 폭(dB).
    static let range = 40.0

    private(set) var levels = [Double](repeating: 0, count: bandCount)
    private var peakDB = -60.0
    private var lastUpdate = -1.0

    mutating func ingest(_ energies: [Double], dt: Double, now: Double, audible: Bool) {
        guard energies.count == Self.bandCount else { return }
        let step = max(dt, 0)
        let decibels = energies.map { 10 * log10(max($0, 1e-12)) }
        let loudest = decibels.max() ?? -120
        if audible {
            peakDB = max(loudest, peakDB - 4.5 * step)
        }
        let floor = peakDB - Self.range
        for index in 0..<Self.bandCount {
            let target = audible ? min(1, max(0, (decibels[index] - floor) / Self.range)) : 0
            let tau = target > levels[index] ? 0.025 : 0.22
            levels[index] += (1 - exp(-step / tau)) * (target - levels[index])
        }
        lastUpdate = now
    }

    /// 소리 콜백이 끊기면 마지막 모양을 서서히 내린다.
    func levels(at now: Double) -> [Double] {
        guard lastUpdate >= 0 else { return [Double](repeating: 0, count: Self.bandCount) }
        let idle = max(0, now - lastUpdate - 0.05)
        let fade = exp(-idle / 0.25)
        return levels.map { $0 * fade }
    }
}
