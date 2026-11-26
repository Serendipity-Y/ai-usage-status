import Foundation
import Testing
@testable import CodexUsageStatus

private func withTempDir(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

@Test func decodesFlexibleGeminiQuotaFormats() throws {
    let json = """
    {
      "plan": "AI Pro",
      "updatedAt": "2026-11-23T06:00:00Z",
      "buckets": [
        {"id": "pro", "label": "Gemini Pro", "remainingPercent": 82.4, "resetsAt": 1790766046},
        {"id": "flash", "label": "Gemini Flash", "remainingFraction": 0.96, "resetsAt": "2026-11-23T11:00:00Z"},
        {"id": "ultra", "label": "Gemini Ultra", "usedPercent": 35},
        {"label": "Unknown Bucket"}
      ]
    }
    """
    let summary = try GeminiUsageFetcher.decodeSummary(from: Data(json.utf8))
    #expect(summary.plan == "AI Pro")
    #expect(summary.updatedAt != nil)
    #expect(summary.buckets.count == 4)
    #expect(summary.buckets[0].remainingPercent == 82)
    #expect(summary.buckets[0].resetsAt != nil)
    #expect(summary.buckets[1].remainingPercent == 96)
    #expect(summary.buckets[1].resetsAt != nil)
    #expect(summary.buckets[2].remainingPercent == 65)
    #expect(summary.buckets[3].remainingPercent == nil)
}

@Test func rejectsEmptyGeminiBuckets() {
    let json = #"{"plan":"AI Pro","buckets":[]}"#
    do {
        _ = try GeminiUsageFetcher.decodeSummary(from: Data(json.utf8))
        Issue.record("Expected invalidOutput for empty buckets")
    } catch {
        #expect(error as? GeminiFetchError == .invalidOutput)
    }
}

@Test func fetchesGeminiQuotaFromLocalFile() throws {
    try withTempDir { dir in
        let file = dir.appendingPathComponent("gemini-quota.json")
        let json = #"{"plan":"Antigravity","buckets":[{"label":"Gemini Pro","remainingPercent":74}]}"#
        try json.write(to: file, atomically: true, encoding: .utf8)

        let summary = try GeminiUsageFetcher.fetchSync(source: .file(file.path))
        #expect(summary.plan == "Antigravity")
        #expect(summary.buckets.first?.remainingPercent == 74)
    }
}

@Test func fetchesGeminiQuotaFromLocalCommandAndDrainsStderr() throws {
    try withTempDir { dir in
        let script = dir.appendingPathComponent("gemini-quota.sh")
        let body = """
        #!/bin/bash
        head -c 131072 /dev/zero >&2
        echo '{"plan":"AI Pro","buckets":[{"label":"Gemini Pro","remainingPercent":88}]}'
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let summary = try GeminiUsageFetcher.fetchSync(source: .command(script.path), timeout: .seconds(4))
        #expect(summary.plan == "AI Pro")
        #expect(summary.buckets.first?.remainingPercent == 88)
    }
}

@Test func geminiCommandErrorsAndTimeoutAreBounded() throws {
    try withTempDir { dir in
        let failScript = dir.appendingPathComponent("fail.sh")
        try "#!/bin/bash\nexit 3\n".write(to: failScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failScript.path)

        do {
            _ = try GeminiUsageFetcher.fetchSync(source: .command(failScript.path), timeout: .seconds(2))
            Issue.record("Expected commandFailed")
        } catch {
            #expect(error as? GeminiFetchError == .commandFailed(3))
        }

        let slowScript = dir.appendingPathComponent("slow.sh")
        try "#!/bin/bash\nexec /bin/sleep 10\n".write(to: slowScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slowScript.path)

        let start = Date()
        do {
            _ = try GeminiUsageFetcher.fetchSync(source: .command(slowScript.path), timeout: .milliseconds(150))
            Issue.record("Expected timeout")
        } catch {
            #expect(error as? GeminiFetchError == .timeout)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }
}

@Test func hoverPresentationFormatsGeminiStates() throws {
    let now = Date(timeIntervalSince1970: 1790758800)
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let json = #"{"plan":"AI Pro","buckets":[{"label":"Gemini Pro","remainingPercent":82,"resetsAt":1790766046},{"label":"Gemini Flash","remainingPercent":96,"resetsAt":1790766046}]}"#
    let gemini = try GeminiUsageFetcher.decodeSummary(from: Data(json.utf8))

    let unconfigured = HoverPresentation(
        usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false, now: now, timeZone: zone,
        geminiUsage: nil, geminiLastRefreshDate: nil, geminiError: .notConfigured
    )
    #expect(unconfigured.gemini.badgeText == "未配置")
    #expect(unconfigured.gemini.rows.isEmpty)
    #expect(unconfigured.gemini.emptyHint != nil)

    let active = HoverPresentation(
        usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false, now: now, timeZone: zone,
        geminiUsage: gemini, geminiLastRefreshDate: now, geminiError: nil
    )
    #expect(active.gemini.badgeText == "AI Pro")
    #expect(active.gemini.rows.count == 2)
    #expect(active.gemini.rows[0].percentText == "82%")
    #expect(active.gemini.rows[0].resetText == "今天 19:00")
    #expect(active.gemini.status == nil)

    let failedWithCache = HoverPresentation(
        usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false, now: now, timeZone: zone,
        geminiUsage: gemini, geminiLastRefreshDate: now.addingTimeInterval(-120), geminiError: .timeout
    )
    #expect(failedWithCache.gemini.isBadgeWarning)
    #expect(failedWithCache.gemini.rows.count == 2)
    #expect(failedWithCache.gemini.status == "读取超时 · 上次成功 16:58")
}

@Test func argonKeepsItsSlotWhenOmittedAndShowsRealZeroWhenReturned() throws {
    let prefix = "antigravity-quota-summary-"
    let common = ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"]
    func rows(_ ids: [String]) throws -> [QuotaRowPresentation] {
        let buckets = ids.map { id in
            ["id": prefix + id, "label": id == "gemini-argon-wtu-weekly" ? "Argon 每周" : id,
             "remainingPercent": 0] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: ["buckets": buckets])
        let snapshot = try GeminiUsageFetcher.decodeSummary(from: data)
        return HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
            isRefreshing: false, refreshFailed: false, geminiUsage: snapshot, geminiError: nil).gemini.rows
    }

    let missing = try rows(common)
    #expect(missing.map(\.label) == ["gemini-5h", "gemini-weekly", "Argon 每周", "3p-5h", "3p-weekly"])
    #expect(missing[2].percent == nil && missing[2].percentText == "—")
    #expect(missing[2].resetText == "— · 本次未返回" && !missing[2].showsProgressBar)
    var complete = common
    complete.insert("gemini-argon-wtu-weekly", at: 2)
    let restored = try rows(complete)
    #expect(restored.count == 5 && restored[2].label == "Argon 每周")
    #expect(restored[2].percentText == "0%" && restored[2].showsProgressBar)
    #expect(try rows(common + ["new-window"]).last?.label == "new-window")
}

@Test func menuBarUsesAntigravityWindowsByID() throws {
    let buckets = """
        {"id":"antigravity-quota-summary-3p-weekly","label":"每周","remainingPercent":99},
        {"id":"antigravity-quota-summary-gemini-argon-wtu-weekly","label":"每周","remainingPercent":75},
        {"id":"secondary","label":"每周","remainingPercent":88},
        {"id":"antigravity-quota-summary-gemini-5h","label":"5H","usedPercent":7.7}
        """
    func summary(_ rows: String) throws -> GeminiUsageSummary {
        try GeminiUsageFetcher.decodeSummary(from: Data("{\"buckets\":[\(rows)]}".utf8))
    }
    let missing = try summary(buckets)
    #expect(missing.antigravityWeeklyRemaining == nil)
    #expect(missing.antigravityFiveHourRemaining == 92)
    let exhausted = try summary(buckets + #",{"id":"antigravity-quota-summary-gemini-weekly","label":"每周","usedPercent":100}"#)
    #expect(exhausted.antigravityBadgeDescription == "Antigravity 每周剩余 0% · 5 小时剩余 92%")
}
