import Foundation
import Testing
@testable import CodexUsageStatus

@Test func chatPaneExtractsUsedPercentAndResetFromSeparateSections() throws {
    let text = ["更新时间：刚刚", "当前用量", "已使用 4%", "重置时间：21:25",
                "每周限额", "已使用 1%", "重置时间：12月 112:25", "使用 AI 点数", "已使用 100%"]
    // Accessibility strings can be UTF-16 backed. Slice the same string that supplied the range.
    let quota = try #require(GeminiChatQuota.parse(text.map { ($0 as NSString) as String }))
    #expect(quota.current.reset == "21:25")
    #expect(quota.weekly.reset == "12月1日 12:25")
    let buckets = ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"].map {
        ["id": "antigravity-quota-summary-" + $0, "label": $0, "usedPercent": 5] as [String: Any]
    }
    let usage = try GeminiUsageFetcher.decodeSummary(from: JSONSerialization.data(withJSONObject: ["buckets": buckets]))
    let p = HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil, isRefreshing: false,
        refreshFailed: false, geminiUsage: usage, geminiError: nil, chatQuota: quota, chatUnavailable: "请打开用量限额页")
    #expect(p.gemini.rows.map(\.label) == ["gemini-5h", "gemini-weekly", "Argon 每周"])
    #expect(p.chatRows.map(\.percent) == [96, 99])
    #expect(p.chatNote?.contains("请打开用量限额页") == true)
}

@Test func chatPaneHandlesBoundaryValuesAndIncompleteSections() throws {
    let text = ["Current Usage", "0% used", "Resets at 9:25 PM", "Weekly limit", "100% used"]
    let quota = try #require(GeminiChatQuota.parse(text))
    #expect(quota.current.used == 0 && quota.weekly.used == 100 && quota.weekly.reset == nil)
    #expect(GeminiChatQuota.parse(["Current usage", "Weekly limit", "1% used"]) == nil)
    #expect(GeminiChatQuota.parse(["当前用量", "已使用 104%", "每周限额", "已使用 1%"]) == nil)
}

@Test func chromeExtensionReportParsesFreshAndStaleAndFormatsResets() throws {
    let now = Date(timeIntervalSince1970: 1795512000) // 2026-11-24 17:20 +08:00
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let freshJSON = """
    {"observedAt":1795511940,"current":{"used":4,"resetsAt":1795526700},"weekly":{"used":1,"resetsAt":1796100300}}
    """
    let freshState = GeminiChatQuota.parseChromeReport(from: Data(freshJSON.utf8), now: now)
    guard case .fresh(let quota) = freshState else {
        Issue.record("Expected fresh Chrome report")
        return
    }
    #expect(quota.isFromChrome)
    #expect(quota.current.used == 4 && quota.weekly.used == 1)

    let presentation = HoverPresentation(
        usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false, now: now, timeZone: zone,
        geminiUsage: nil, geminiError: .notConfigured,
        chatQuota: quota, chatUnavailable: nil
    )
    #expect(presentation.chatBadgeText == "Chrome 17:19")
    #expect(!presentation.isChatBadgeWarning)
    #expect(presentation.chatNote == nil)
    #expect(presentation.chatRows.map(\.percent) == [96, 99])
    #expect(presentation.chatRows[0].resetText == "今天 21:25")
    #expect(presentation.chatRows[1].resetText == "12月1日 12:45")

    let staleState = GeminiChatQuota.parseChromeReport(
        from: Data(freshJSON.utf8),
        now: now.addingTimeInterval(20 * 60)
    )
    guard case .stale = staleState else {
        Issue.record("Expected stale Chrome report after 20 minutes")
        return
    }
}

@Test func chromeBridgeTakesPriorityOverAccessibilityPane() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("gemini-chat-chrome.json")
    let now = Date(timeIntervalSince1970: 1795512000)
    let json = #"{"observedAt":1795511970,"current":{"used":12,"resetsAt":1795526700},"weekly":{"used":5,"resetsAt":1796100300}}"#
    try json.write(to: file, atomically: true, encoding: .utf8)

    var paneCalled = false
    let reading = GeminiChatPane.readBest(chromeURL: file, now: now) {
        paneCalled = true
        return .unavailable("should not be called")
    }
    #expect(!paneCalled)
    guard case .snapshot(let snapshot) = reading else {
        Issue.record("Expected Chrome snapshot")
        return
    }
    #expect(snapshot.isFromChrome)
    #expect(snapshot.current.used == 12 && snapshot.weekly.used == 5)
}

@Test func duplicateChromeSnapshotsDoNotRewriteOrRollBackCache() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("snapshot.json")
    let window = GeminiChatQuota.Window(used: 23, reset: nil)
    func sample(_ seconds: Double) -> GeminiChatQuota {
        GeminiChatQuota(current: window, weekly: window, readAt: Date(timeIntervalSince1970: seconds),
                        pageUpdate: nil, source: "chrome")
    }
    try sample(200).save(to: file)
    let marker = Date(timeIntervalSince1970: 500)
    try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: file.path)
    try sample(200).save(to: file)
    try sample(100).save(to: file)
    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect(attrs[.modificationDate] as? Date == marker)
    try sample(300).save(to: file)
    let saved = try JSONDecoder().decode(GeminiChatQuota.self, from: Data(contentsOf: file))
    #expect(saved == sample(300))
}

@Test func chromeClockSkewBoundaryAndFallback() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("chrome.json")
    let saved = dir.appendingPathComponent("last-read.json")
    let now = Date(timeIntervalSince1970: 1000)
    func report(_ time: Int) -> Data {
        Data("{\"observedAt\":\(time),\"current\":{\"used\":4},\"weekly\":{\"used\":1}}".utf8)
    }
    guard case .fresh = GeminiChatQuota.parseChromeReport(from: report(1010), now: now) else {
        Issue.record("Ten seconds of clock skew should be accepted")
        return
    }
    let bad = report(1011)
    #expect(GeminiChatQuota.parseChromeReport(from: bad, now: now) == .missing)
    try bad.write(to: file)
    let window = GeminiChatQuota.Window(used: 1, reset: nil)
    let pane = GeminiChatQuota(current: window, weekly: window, readAt: now, pageUpdate: nil, source: "pane")
    let reading = GeminiChatPane.readBest(chromeURL: file, now: now) { .snapshot(pane) }
    guard case .snapshot(let value) = reading else { Issue.record("Expected pane fallback"); return }
    #expect(value == pane)
    let future = GeminiChatQuota(current: window, weekly: window, readAt: now.addingTimeInterval(86400),
                                 pageUpdate: nil, source: "chrome")
    try JSONEncoder().encode(future).write(to: saved)
    #expect(GeminiChatQuota.cached(now: now, chromeURL: file, savedURL: saved) == nil)
}
