import Foundation

struct RateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCredits?
}

struct RateLimitResetCredits: Decodable, Sendable {
    let availableCount: Int?
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: TimeInterval?
}

struct UsageSummary: Sendable {
    let planType: String?
    let fiveHour: UsageWindow
    let weekly: UsageWindow
    let availableResetCount: Int?

    init(response: RateLimitsResponse) throws {
        let snapshot = response.rateLimitsByLimitId?["codex"]
            ?? response.rateLimits
            ?? response.rateLimitsByLimitId?.values.first

        guard let snapshot else {
            throw FetchError.invalidOutput
        }

        guard snapshot.primary != nil || snapshot.secondary != nil else { throw FetchError.invalidOutput }
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        func resolve(minutes: Double, legacy: RateLimitWindow?) -> UsageWindow {
            let matched = windows.first { approximately($0.windowDurationMins, minutes) }
            return UsageWindow(matched ?? (legacy?.windowDurationMins == nil ? legacy : nil))
        }
        planType = snapshot.planType
        fiveHour = resolve(minutes: 300, legacy: snapshot.primary)
        weekly = resolve(minutes: 10080, legacy: snapshot.secondary)
        availableResetCount = response.rateLimitResetCredits?.availableCount.flatMap { $0 >= 0 ? $0 : nil }
    }

    var menuTitle: String {
        "5h \(fiveHour.percentText) 7d \(weekly.percentText)"
    }

    var verboseTitle: String {
        "Codex usage: 5-hour \(fiveHour.percentText) · weekly \(weekly.percentText)"
    }

    func tooltip(formatter: DateFormatter) -> String {
        let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        return "Codex usage\n5-hour remaining: \(fiveHour.percentText) · resets \(fiveHourReset)\nWeekly remaining: \(weekly.percentText) · resets \(weeklyReset)"
    }
}

struct UsageWindow: Sendable {
    let remainingPercent: Int?
    let resetsAt: Date?

    var percentText: String { remainingPercent.map { "\($0)%" } ?? "--" }

    init(_ window: RateLimitWindow?) {
        remainingPercent = window?.usedPercent.map { Int((100 - min(100, max(0, $0))).rounded()) }
        resetsAt = window?.resetsAt.map { Date(timeIntervalSince1970: $0) }
    }

    func displayText(formatter: DateFormatter) -> String {
        guard let resetsAt else {
            return "\(percentText) remaining, reset unknown"
        }
        return "\(percentText) remaining, resets \(formatter.string(from: resetsAt))"
    }
}

private func approximately(_ value: Double?, _ target: Double) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - target) <= 1
}
