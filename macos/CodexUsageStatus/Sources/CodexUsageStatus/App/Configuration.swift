import Foundation

enum AppConfig {
    static var defaultCodexPath: String {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? candidates[0]
    }
    static var defaultGeminiQuotaFilePath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CodexUsageStatus/gemini-quota.json").path
    }
    static var defaultGeminiQuotaCommandPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CodexUsageStatus/bin/fetch-gemini-quota.py").path
    }
    static let minimumRefreshInterval: TimeInterval = 60
    static let defaultRefreshInterval: TimeInterval = 120
    static let errorRetryInterval: TimeInterval = 300
    static let appServerTimeout: DispatchTimeInterval = .seconds(20)
    static let geminiFetchTimeout: DispatchTimeInterval = .seconds(25)

    static func retryInterval(afterFailures count: Int) -> TimeInterval {
        [60, 120, errorRetryInterval][min(max(count - 1, 0), 2)]
    }
}

func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? AppConfig.defaultRefreshInterval
    return max(AppConfig.minimumRefreshInterval, requested)
}
