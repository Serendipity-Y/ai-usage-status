import Foundation

struct GeminiQuotaPayload: Decodable, Sendable {
    let plan: String?
    let updatedAt: FlexibleTimestamp?
    let buckets: [GeminiQuotaBucketPayload]?
    let extraProviders: [ExternalToolQuotaPayload]?
}

struct ExternalToolQuotaPayload: Decodable, Sendable {
    let id: String
    let name: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let remainingFraction: Double?
    let resetsAt: FlexibleTimestamp?
    let valueText: String?
    let statusText: String?
}

struct GeminiQuotaBucketPayload: Decodable, Sendable {
    let id: String?
    let label: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let remainingFraction: Double?
    let resetsAt: FlexibleTimestamp?
}

struct FlexibleTimestamp: Decodable, Sendable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            // Support both Unix seconds and milliseconds.
            let normalized = seconds > 10_000_000_000 ? seconds / 1000.0 : seconds
            date = Date(timeIntervalSince1970: normalized)
            return
        }
        if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = Double(trimmed) {
                let normalized = seconds > 10_000_000_000 ? seconds / 1000.0 : seconds
                date = Date(timeIntervalSince1970: normalized)
                return
            }
            if let parsed = Self.parseISO8601(trimmed) {
                date = parsed
                return
            }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported timestamp format")
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

struct GeminiUsageBucket: Sendable, Equatable {
    let id: String
    let label: String
    let remainingPercent: Int?
    let resetsAt: Date?

    init(payload: GeminiQuotaBucketPayload, index: Int) {
        let cleanLabel = payload.label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = payload.id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "bucket-\(index)"
        self.label = cleanLabel.isEmpty ? "Gemini" : cleanLabel
        self.resetsAt = payload.resetsAt?.date
        self.remainingPercent = Self.resolvePercent(
            remaining: payload.remainingPercent,
            fraction: payload.remainingFraction,
            used: payload.usedPercent
        )
    }

    static func resolvePercent(remaining: Double?, fraction: Double?, used: Double?) -> Int? {
        if let remaining {
            return clampPercent(remaining)
        } else if let fraction {
            return clampPercent(fraction * 100.0)
        } else if let used {
            return clampPercent(100.0 - used)
        }
        return nil
    }

    private static func clampPercent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }
}

struct ExternalToolQuota: Sendable, Equatable {
    let id: String
    let name: String
    let remainingPercent: Int?
    let resetsAt: Date?
    let valueText: String?
    let statusText: String?

    init(payload: ExternalToolQuotaPayload) {
        self.id = payload.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleanName.isEmpty ? self.id : cleanName
        self.remainingPercent = GeminiUsageBucket.resolvePercent(
            remaining: payload.remainingPercent,
            fraction: payload.remainingFraction,
            used: payload.usedPercent
        )
        self.resetsAt = payload.resetsAt?.date
        self.valueText = payload.valueText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.statusText = payload.statusText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct GeminiUsageSummary: Sendable, Equatable {
    let plan: String?
    let updatedAt: Date?
    let buckets: [GeminiUsageBucket]
    fileprivate(set) var extraProviders: [ExternalToolQuota]

    init(payload: GeminiQuotaPayload) throws {
        let parsedBuckets = (payload.buckets ?? []).enumerated().map { index, item in
            GeminiUsageBucket(payload: item, index: index)
        }
        var parsedExtras: [ExternalToolQuota] = []
        var positions: [String: Int] = [:]
        for item in (payload.extraProviders ?? []).map(ExternalToolQuota.init) {
            let key = item.id.lowercased()
            guard !key.isEmpty else { continue }
            if let index = positions[key] {
                let previous = parsedExtras[index]
                if previous.valueText == nil && previous.remainingPercent == nil &&
                    (item.valueText != nil || item.remainingPercent != nil) {
                    parsedExtras[index] = item
                }
            } else {
                positions[key] = parsedExtras.count
                parsedExtras.append(item)
            }
        }
        guard !parsedBuckets.isEmpty || !parsedExtras.isEmpty else {
            throw GeminiFetchError.invalidOutput
        }
        self.plan = payload.plan?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.updatedAt = payload.updatedAt?.date
        self.buckets = parsedBuckets
        self.extraProviders = parsedExtras
    }

    var antigravityWeeklyRemaining: Int? {
        buckets.first { $0.id == "antigravity-quota-summary-gemini-weekly" }?.remainingPercent
    }

    var antigravityFiveHourRemaining: Int? {
        buckets.first { $0.id == "antigravity-quota-summary-gemini-5h" }?.remainingPercent
    }

    var antigravityBadgeDescription: String {
        let weekly = antigravityWeeklyRemaining.map { "剩余 \($0)%" } ?? "暂无数据"
        let fiveHour = antigravityFiveHourRemaining.map { "剩余 \($0)%" } ?? "暂无数据"
        return "Antigravity 5 小时\(fiveHour) · 每周\(weekly)"
    }

    var cliSummary: String {
        let parts = buckets.prefix(5).map { bucket in
            let pct = bucket.remainingPercent.map { "\($0)%" } ?? "--"
            return "\(bucket.label) \(pct)"
        }
        let extraParts = extraProviders.prefix(4).map { tool in
            let val = tool.valueText ?? tool.remainingPercent.map { "\($0)%" } ?? (tool.statusText ?? "--")
            return "\(tool.name) \(val)"
        }
        return (parts + extraParts).joined(separator: " · ")
    }
}

struct GeminiRefreshState {
    private(set) var usage: GeminiUsageSummary?
    private(set) var quotaReadAt: Date?
    private(set) var error: GeminiFetchError?

    mutating func accept(_ incoming: GeminiUsageSummary, at now: Date = Date()) {
        if incoming.buckets.isEmpty {
            if usage == nil { usage = incoming }
            usage?.extraProviders = incoming.extraProviders
            error = .quotaNotReported
            return
        }
        usage = incoming
        quotaReadAt = incoming.updatedAt ?? now
        error = nil
    }

    mutating func fail(_ failure: GeminiFetchError) {
        error = failure
        if failure == .notConfigured {
            usage = nil
            quotaReadAt = nil
        }
    }
}

enum GeminiFetchError: LocalizedError, Equatable {
    case notConfigured
    case quotaNotReported
    case commandNotFound(String)
    case timeout
    case commandFailed(Int32)
    case fileReadFailed
    case invalidOutput

    var briefDescription: String {
        switch self {
        case .notConfigured: return "未配置数据源"
        case .quotaNotReported: return "本次未返回额度"
        case .commandNotFound: return "未找到采集命令"
        case .timeout: return "读取超时"
        case .commandFailed: return "采集命令执行失败"
        case .fileReadFailed: return "快照文件读取失败"
        case .invalidOutput: return "额度数据格式异常"
        }
    }

    var errorDescription: String? {
        switch self {
        case .quotaNotReported:
            return "The source returned external tool balances only"
        case .notConfigured:
            return "Gemini quota source is not configured"
        case .commandNotFound(let path):
            return "Gemini quota command not found or not executable at \(path)"
        case .timeout:
            return "Gemini quota command did not respond before timeout"
        case .commandFailed(let status):
            return "Gemini quota command exited with status \(status)"
        case .fileReadFailed:
            return "Unable to read local Gemini quota JSON file"
        case .invalidOutput:
            return "Gemini quota source returned unexpected JSON data"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
