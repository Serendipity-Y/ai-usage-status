import Foundation
import Testing
@testable import CodexUsageStatus

private func usage(_ resetJSON: String = "") throws -> UsageSummary {
    let json = """
    {"rateLimits":{"limitId":"codex","primary":{"usedPercent":30,"windowDurationMins":300,"resetsAt":1790766046},
    "secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1791113000}}\(resetJSON)}
    """
    return try UsageSummary(response: JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8)))
}

@Test func usesAuthoritativeAvailableCount() throws {
    // Detail rows may be capped; their length must not replace availableCount.
    let value = try usage(",\"rateLimitResetCredits\":{\"availableCount\":4,\"credits\":[{\"id\":\"one\"}]}")
    #expect(value.availableResetCount == 4)
}

@Test func missingCountRemainsUnknown() throws {
    for raw in ["", ",\"rateLimitResetCredits\":null", ",\"rateLimitResetCredits\":{\"availableCount\":null}",
                ",\"rateLimitResetCredits\":{\"availableCount\":-1}"] {
        let value = try usage(raw)
        #expect(value.availableResetCount == nil)
        #expect(HoverPresentation(usage: value, nextRefreshDate: nil, lastRefreshDate: nil,
            isRefreshing: false, refreshFailed: false).resetCredits == "暂未提供")
    }
}

@Test func zeroCountIsNotUnknown() throws {
    let value = try usage(",\"rateLimitResetCredits\":{\"availableCount\":0}")
    #expect(HoverPresentation(usage: value, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false).resetCredits == "0 次")
}

@Test func scheduledRefreshAndQuotaResetRemainDistinct() throws {
    let now = Date(timeIntervalSince1970: 1790758800) // 2026-09-30 17:00 China time
    let card = HoverPresentation(usage: try usage(), nextRefreshDate: now.addingTimeInterval(120), lastRefreshDate: now,
        isRefreshing: false, refreshFailed: false, now: now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    #expect(card.nextRefresh == "17:02:00")
    #expect(card.fiveHourReset == "今天 19:00")
    #expect(card.weeklyReset == "10月4日 19:23")
}

@Test func refreshAndFailureShowAccurateState() throws {
    let now = Date(timeIntervalSince1970: 1790758800)
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let loading = HoverPresentation(usage: nil, nextRefreshDate: now, lastRefreshDate: nil,
        isRefreshing: true, refreshFailed: false, now: now, timeZone: zone)
    #expect(loading.nextRefresh == "正在刷新…")
    #expect(loading.resetCredits == "暂未提供")
    let failed = HoverPresentation(usage: try usage(",\"rateLimitResetCredits\":{\"availableCount\":4}"),
        nextRefreshDate: now.addingTimeInterval(300), lastRefreshDate: now.addingTimeInterval(-120),
        isRefreshing: false, refreshFailed: true, now: now, timeZone: zone)
    #expect(failed.nextRefresh == "17:05:00")
    #expect(failed.isStale)
    #expect(failed.status == "更新失败 · 上次记录")
    #expect(failed.resetCredits == "4 次")
    #expect(failed.updatedAt == "更新于 16:58:00")
}

@Test func failureExplainsCauseAndAgeWithoutDiscardingLastUsage() throws {
    let now = Date(timeIntervalSince1970: 1790758800)
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let stale = HoverPresentation(usage: try usage(), nextRefreshDate: now.addingTimeInterval(60),
        lastRefreshDate: now.addingTimeInterval(-120), isRefreshing: false, refreshFailed: true,
        now: now, timeZone: zone, failureDescription: FetchError.timeout.briefDescription)
    #expect(stale.status == "读取超时 · 上次成功 16:58")
    #expect(stale.fiveHourReset == "今天 19:00")
    #expect(stale.nextRefresh == "17:01:00")
    let empty = HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: true, failureDescription: "读取超时")
    #expect(empty.status == "读取超时 · 暂无数据")
}

@Test func failureRetriesBackOffWithoutGoingBelowOneMinute() {
    #expect((1...5).map { AppConfig.retryInterval(afterFailures: $0) } == [60, 120, 300, 300, 300])
    #expect(AppConfig.retryInterval(afterFailures: 1) >= AppConfig.minimumRefreshInterval)
}

@Test func keepsIncompleteAndLegacyCodexWindowsInTheirOwnSlots() throws {
    func title(_ fields: String) throws -> String {
        let data = Data(("{\"rateLimits\":{" + fields + "}}").utf8)
        return try UsageSummary(response: JSONDecoder().decode(RateLimitsResponse.self, from: data)).menuTitle
    }
    #expect(try title(#""secondary":{"windowDurationMins":10080,"usedPercent":23}"#) == "5h -- 7d 77%")
    #expect(try title(#""primary":{"windowDurationMins":300},"secondary":{"usedPercent":0}"#) == "5h -- 7d 100%")
    #expect(try title(#""primary":{"usedPercent":100},"secondary":{"usedPercent":0}"#) == "5h 0% 7d 100%")
    #expect(try title(#""primary":{"windowDurationMins":10080,"usedPercent":100},"secondary":{"windowDurationMins":300,"usedPercent":0}"#) == "5h 100% 7d 0%")
    #expect(try title(#""primary":{"windowDurationMins":1440,"usedPercent":50}"#) == "5h -- 7d --")
}

@Test func roundsCodexRemainingAfterSubtraction() throws {
    let pairs = [(0.5, 100), (22.5, 78), (99.5, 1), (100.0, 0), (0.0, 100)]
    for (used, remaining) in pairs {
        let window = UsageWindow(RateLimitWindow(usedPercent: used, windowDurationMins: 300, resetsAt: nil))
        #expect(window.remainingPercent == remaining)
    }
}
