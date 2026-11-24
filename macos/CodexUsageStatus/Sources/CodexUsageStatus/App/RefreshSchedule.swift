import Foundation

/// All state and timer callbacks belong to the main run loop, one instance per source.
@MainActor
final class RefreshSchedule {
    private let interval: TimeInterval
    private let fetch: @MainActor () async -> Bool
    private let onChange: @MainActor () -> Void
    private var timer: Timer?
    private(set) var isRefreshing = false
    private(set) var consecutiveFailures = 0
    var nextRefreshDate: Date? { timer?.fireDate }

    init(interval: TimeInterval, fetch: @escaping @MainActor () async -> Bool,
         onChange: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.fetch = fetch
        self.onChange = onChange
    }

    func refresh() {
        guard !isRefreshing else { return }
        timer?.invalidate()
        timer = nil
        isRefreshing = true
        onChange()

        Task {
            let succeeded = await fetch()
            consecutiveFailures = succeeded ? 0 : consecutiveFailures + 1
            let delay = succeeded ? interval : AppConfig.retryInterval(afterFailures: consecutiveFailures)
            let scheduled = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            scheduled.fireDate = Date(timeIntervalSinceNow: delay)
            isRefreshing = false
            timer = scheduled
            RunLoop.main.add(scheduled, forMode: .common)
            onChange()
        }
    }
}
