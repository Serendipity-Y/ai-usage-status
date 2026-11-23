import Foundation

struct QuotaRowPresentation: Equatable, Sendable {
    let label: String
    let percent: Int?
    let percentText: String
    let resetText: String
    let showsProgressBar: Bool

    init(label: String, percent: Int?, resetText: String, valueText: String? = nil, showsProgressBar: Bool = true) {
        self.label = label
        self.percent = percent
        self.percentText = valueText ?? percent.map { "\($0)%" } ?? "--"
        self.resetText = resetText
        self.showsProgressBar = showsProgressBar
    }
}

struct GeminiHoverPresentation: Equatable, Sendable {
    let badgeText: String
    let isBadgeWarning: Bool
    let rows: [QuotaRowPresentation]
    let emptyHint: String?
    let status: String?
}

struct HoverPresentation {
    let resetCredits: String
    let fiveHourReset: String
    let weeklyReset: String
    let fiveHourPercent: Int?
    let weeklyPercent: Int?
    let codexRows: [QuotaRowPresentation]
    let gemini: GeminiHoverPresentation
    let extraToolRows: [QuotaRowPresentation]
    let nextRefresh: String
    let status: String
    let updatedAt: String
    let isStale: Bool

    init(
        usage: UsageSummary?,
        nextRefreshDate: Date?,
        lastRefreshDate: Date?,
        isRefreshing: Bool,
        refreshFailed: Bool,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        failureDescription: String? = nil,
        geminiUsage: GeminiUsageSummary? = nil,
        geminiLastRefreshDate: Date? = nil,
        geminiError: GeminiFetchError? = .notConfigured
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        func resetTime(_ date: Date?) -> String {
            guard let date else { return "暂未提供" }
            formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "'今天' HH:mm" : "M月d日 HH:mm"
            return formatter.string(from: date)
        }

        func shortTime(_ date: Date) -> String {
            formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
            return formatter.string(from: date)
        }

        resetCredits = usage?.availableResetCount.map { "\($0) 次" } ?? "暂未提供"
        fiveHourReset = resetTime(usage?.fiveHour.resetsAt)
        weeklyReset = resetTime(usage?.weekly.resetsAt)
        fiveHourPercent = usage?.fiveHour.remainingPercent
        weeklyPercent = usage?.weekly.remainingPercent

        codexRows = [
            QuotaRowPresentation(label: "5 小时", percent: fiveHourPercent, resetText: fiveHourReset),
            QuotaRowPresentation(label: "每周", percent: weeklyPercent, resetText: weeklyReset),
        ]

        let geminiRows: [QuotaRowPresentation] = (geminiUsage?.buckets.prefix(5) ?? []).map { bucket in
            QuotaRowPresentation(
                label: bucket.label,
                percent: bucket.remainingPercent,
                resetText: resetTime(bucket.resetsAt)
            )
        }

        let defaultExtraTools: [(id: String, name: String)] = [
            ("workbuddy", "WorkBuddy"),
            ("traecn", "Trae"),
            ("qoder", "Qoder"),
        ]
        let extrasByID = Dictionary(
            uniqueKeysWithValues: (geminiUsage?.extraProviders ?? []).map { ($0.id.lowercased(), $0) }
        )
        extraToolRows = defaultExtraTools.map { spec in
            if let item = extrasByID[spec.id] {
                let subtitle: String
                if let statusText = item.statusText {
                    subtitle = statusText
                } else if let resetsAt = item.resetsAt {
                    subtitle = resetTime(resetsAt)
                } else {
                    subtitle = (item.valueText != nil || item.remainingPercent != nil) ? "已同步" : "暂未获取"
                }
                return QuotaRowPresentation(
                    label: item.name,
                    percent: item.remainingPercent,
                    resetText: subtitle,
                    valueText: item.valueText,
                    showsProgressBar: item.remainingPercent != nil
                )
            }
            return QuotaRowPresentation(
                label: spec.name,
                percent: nil,
                resetText: isRefreshing ? "读取中…" : "待配置签到源",
                showsProgressBar: false
            )
        }

        if let geminiError, geminiError == .notConfigured, geminiRows.isEmpty {
            gemini = GeminiHoverPresentation(
                badgeText: "未配置",
                isBadgeWarning: false,
                rows: [],
                emptyHint: "未配置本地数据源 · 支持 JSON / 命令接入",
                status: nil
            )
        } else if let geminiError, geminiError != .notConfigured {
            let statusText: String
            if let geminiLastRefreshDate {
                statusText = "\(geminiError.briefDescription) · 上次成功 \(shortTime(geminiLastRefreshDate))"
            } else {
                statusText = "\(geminiError.briefDescription) · 暂无数据"
            }
            gemini = GeminiHoverPresentation(
                badgeText: geminiUsage?.plan ?? "读取异常",
                isBadgeWarning: true,
                rows: geminiRows,
                emptyHint: nil,
                status: statusText
            )
        } else if !geminiRows.isEmpty {
            let planText: String
            if let plan = geminiUsage?.plan {
                planText = plan
            } else if let snapshotAt = geminiUsage?.updatedAt {
                planText = "快照 \(shortTime(snapshotAt))"
            } else {
                planText = "已接入"
            }
            gemini = GeminiHoverPresentation(
                badgeText: planText,
                isBadgeWarning: false,
                rows: geminiRows,
                emptyHint: nil,
                status: nil
            )
        } else {
            gemini = GeminiHoverPresentation(
                badgeText: isRefreshing ? "读取中" : "暂无数据",
                isBadgeWarning: false,
                rows: [],
                emptyHint: isRefreshing ? "正在读取 Gemini 额度…" : "暂未取得 Gemini 额度数据",
                status: nil
            )
        }

        formatter.dateFormat = "HH:mm:ss"
        if isRefreshing {
            nextRefresh = "正在刷新…"
        } else if let nextRefreshDate {
            nextRefresh = nextRefreshDate > now ? formatter.string(from: nextRefreshDate) : "即将刷新"
        } else {
            nextRefresh = "等待首次刷新"
        }

        isStale = refreshFailed
        if refreshFailed, let failureDescription {
            if let lastRefreshDate {
                status = "\(failureDescription) · 上次成功 \(shortTime(lastRefreshDate))"
            } else {
                status = "\(failureDescription) · 暂无数据"
            }
        } else {
            status = refreshFailed ? "更新失败 · 上次记录" : (isRefreshing ? "更新中" : "自动更新")
        }

        if let lastRefreshDate {
            formatter.dateFormat = calendar.isDate(lastRefreshDate, inSameDayAs: now) ? "HH:mm:ss" : "M月d日 HH:mm:ss"
            updatedAt = "更新于 \(formatter.string(from: lastRefreshDate))"
        } else {
            updatedAt = "尚未取得额度数据"
        }
    }
}
