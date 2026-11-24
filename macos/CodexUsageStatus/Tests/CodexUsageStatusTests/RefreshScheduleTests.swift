import Foundation
import Testing
@testable import CodexUsageStatus

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
}

@Test @MainActor func sourcesPublishAndRetryIndependently() async throws {
    var suspendedFetch: CheckedContinuation<Bool, Never>?
    var slowCalls = 0
    var fastCalls = 0
    var fastUpdates = 0
    let slow = RefreshSchedule(interval: 120, fetch: {
        slowCalls += 1
        return await withCheckedContinuation { suspendedFetch = $0 }
    }, onChange: {})
    let fast = RefreshSchedule(interval: 0.05, fetch: {
        fastCalls += 1
        return true
    }, onChange: { fastUpdates += 1 })

    slow.refresh()
    fast.refresh()
    slow.refresh()
    try await waitUntil { fastCalls >= 2 && suspendedFetch != nil }
    #expect(slowCalls == 1)
    #expect(slow.isRefreshing)
    #expect(fastUpdates >= 4)

    for (index, delay) in [60, 120, 300].enumerated() {
        suspendedFetch?.resume(returning: false)
        suspendedFetch = nil
        try await waitUntil { !slow.isRefreshing }
        let next = try #require(slow.nextRefreshDate)
        #expect(abs(next.timeIntervalSinceNow - Double(delay)) < 1)
        #expect(slow.consecutiveFailures == index + 1)
        let before = fastCalls
        try await waitUntil { fastCalls > before }
        #expect(fast.consecutiveFailures == 0)
        slow.refresh()
        try await waitUntil { suspendedFetch != nil }
    }

    suspendedFetch?.resume(returning: true)
    try await waitUntil { !slow.isRefreshing }
    #expect(slow.consecutiveFailures == 0)
    let next = try #require(slow.nextRefreshDate)
    #expect(abs(next.timeIntervalSinceNow - 120) < 1)
}
