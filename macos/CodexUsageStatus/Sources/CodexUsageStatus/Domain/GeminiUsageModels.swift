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
        min(100, max(0, Int(value.rounded())))
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
    let extraProviders: [ExternalToolQuota]

    init(payload: GeminiQuotaPayload) throws {
        let parsedBuckets = (payload.buckets ?? []).enumerated().map { index, item in
            GeminiUsageBucket(payload: item, index: index)
        }
        let parsedExtras = (payload.extraProviders ?? []).map(ExternalToolQuota.init)
        guard !parsedBuckets.isEmpty || !parsedExtras.isEmpty else {
            throw GeminiFetchError.invalidOutput
        }
        self.plan = payload.plan?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.updatedAt = payload.updatedAt?.date
        self.buckets = parsedBuckets
        self.extraProviders = parsedExtras
    }

    var cliSummary: String {
        let parts = buckets.prefix(5).map { bucket in
            let pct = bucket.remainingPercent.map { "\($0)%" } ?? "--"
            return "\(bucket.label) \(pct)"
        }
        let extraParts = extraProviders.prefix(3).map { tool in
            let val = tool.valueText ?? tool.remainingPercent.map { "\($0)%" } ?? (tool.statusText ?? "--")
            return "\(tool.name) \(val)"
        }
        return (parts + extraParts).joined(separator: " · ")
    }
}

enum GeminiFetchError: LocalizedError, Equatable {
    case notConfigured
    case commandNotFound(String)
    case timeout
    case commandFailed(Int32)
    case fileReadFailed
    case invalidOutput

    var briefDescription: String {
        switch self {
        case .notConfigured: return "未配置数据源"
        case .commandNotFound: return "未找到采集命令"
        case .timeout: return "读取超时"
        case .commandFailed: return "采集命令执行失败"
        case .fileReadFailed: return "快照文件读取失败"
        case .invalidOutput: return "额度数据格式异常"
        }
    }

    var errorDescription: String? {
        switch self {
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
