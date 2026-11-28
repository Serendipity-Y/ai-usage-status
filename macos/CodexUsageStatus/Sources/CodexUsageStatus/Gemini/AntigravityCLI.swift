import Foundation

/// Reads the documented JSON output of a separately installed CodexBar CLI.
enum AntigravityCLI {
    private struct Report: Decodable {
        let provider: String?
        let source: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let updatedAt: FlexibleTimestamp?
        let extraRateWindows: [Entry]?
    }

    private struct Entry: Decodable {
        let id: String
        let title: String?
        let usageKnown: Bool?
        let window: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let remainingPercent: Double?
        let resetsAt: FlexibleTimestamp?
    }

    static func decode(_ data: Data) throws -> GeminiUsageSummary {
        let reports = try? JSONDecoder().decode([Report].self, from: data)
        guard let usage = reports?.first(where: { $0.provider == "antigravity" && $0.source != "offline" && $0.usage != nil })?.usage else {
            throw GeminiFetchError.invalidOutput
        }
        let labels = ["antigravity-quota-summary-gemini-5h": "5 小时",
                      "antigravity-quota-summary-gemini-weekly": "每周",
                      "antigravity-quota-summary-gemini-argon-wtu-weekly": "Argon 每周",
                      "antigravity-quota-summary-3p-5h": "Claude/GPT 5H",
                      "antigravity-quota-summary-3p-weekly": "Claude/GPT 每周"]
        let buckets = (usage.extraRateWindows ?? []).compactMap { entry -> GeminiQuotaBucketPayload? in
            guard entry.id.hasPrefix("antigravity-quota-summary-") else { return nil }
            let window = entry.usageKnown == false ? nil : entry.window
            return GeminiQuotaBucketPayload(id: entry.id, label: labels[entry.id] ?? entry.title ?? entry.id,
                remainingPercent: window?.remainingPercent, usedPercent: window?.usedPercent,
                remainingFraction: nil, resetsAt: window?.resetsAt)
        }
        return try GeminiUsageSummary(payload: GeminiQuotaPayload(plan: "Antigravity", updatedAt: usage.updatedAt,
            buckets: buckets, extraProviders: nil))
    }
}
