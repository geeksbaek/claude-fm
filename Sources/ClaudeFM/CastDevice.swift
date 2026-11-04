import Foundation
import Network

/// Bonjour 로 찾은 크롬캐스트 하나.
struct CastDevice: Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let model: String?
    let endpoint: NWEndpoint
}

/// 같은 네트워크의 크롬캐스트(`_googlecast._tcp`)를 찾는다. 메인 큐에서 돌고, 바뀌면 `onChange` 를 부른다.
/// 스피커처럼 화면이 없는 기기는 뺀다.
@MainActor
final class CastDiscovery {
    enum Status: Equatable {
        case idle
        case searching
        /// 로컬 네트워크 권한이 꺼져 있다.
        case denied
        case failed
    }

    static let serviceType = "_googlecast._tcp"

    private(set) var devices: [CastDevice] = []
    private(set) var status = Status.idle
    /// 찾기 시작한 시각. 한참 찾아도 없으면 안내를 바꾼다.
    private(set) var startedAt: TimeInterval?
    var onChange: (() -> Void)?
    private var browser: NWBrowser?

    var isRunning: Bool { browser != nil }

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self, let browser, browser === self.browser else { return }
                self.apply(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            MainActor.assumeIsolated {
                guard let self, let browser, browser === self.browser else { return }
                self.update(results)
            }
        }
        self.browser = browser
        status = .searching
        startedAt = ProcessInfo.processInfo.systemUptime
        browser.start(queue: .main)
        onChange?()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        status = .idle
        startedAt = nil
        onChange?()
    }

    private func apply(_ state: NWBrowser.State) {
        let next: Status
        switch state {
        case .ready, .setup:
            next = .searching
        case .waiting(let error):
            next = Self.isPolicyDenied(error) ? .denied : .searching
        case .failed(let error):
            next = Self.isPolicyDenied(error) ? .denied : .failed
        case .cancelled:
            next = .idle
        @unknown default:
            next = status
        }
        guard next != status else { return }
        status = next
        onChange?()
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: CastDevice] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var txt: [String: String] = [:]
            if case let .bonjour(record) = result.metadata { txt = record.dictionary }
            let record = CastDeviceRecord(serviceName: name, txt: txt)
            guard record.showsVideo, found[record.id] == nil else { continue }
            found[record.id] = CastDevice(id: record.id, name: record.name, model: record.model, endpoint: result.endpoint)
        }
        let sorted = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !sorted.isEmpty, status == .denied { status = .searching }
        guard sorted != devices else { return }
        devices = sorted
        onChange?()
    }

    /// 로컬 네트워크 권한이 없을 때 Bonjour 가 내는 오류(kDNSServiceErr_PolicyDenied).
    nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        if case let .dns(code) = error { return code == -65_570 }
        return false
    }
}
