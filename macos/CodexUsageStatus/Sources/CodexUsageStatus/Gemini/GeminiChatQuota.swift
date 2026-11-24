import AppKit
import ApplicationServices

/// A snapshot of Gemini chat usage limits, from either the Chrome extension bridge
/// (`gemini-chat-chrome.json`) or the native macOS Gemini Usage Limits pane.
struct GeminiChatQuota: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        let used: Int
        let reset: String?
        let resetsAt: Date?

        init(used: Int, reset: String?, resetsAt: Date? = nil) {
            self.used = used
            self.reset = reset
            self.resetsAt = resetsAt
        }
    }

    let current: Window
    let weekly: Window
    let readAt: Date
    let pageUpdate: String?
    let source: String?

    init(current: Window, weekly: Window, readAt: Date, pageUpdate: String?, source: String? = nil) {
        self.current = current
        self.weekly = weekly
        self.readAt = readAt
        self.pageUpdate = pageUpdate
        self.source = source
    }

    var isFromChrome: Bool {
        source == "chrome"
    }

    static func parse(_ lines: [String], at now: Date = Date()) -> Self? {
        let currentTitles = ["当前用量", "Current usage"]
        let weeklyTitles = ["每周限额", "Weekly limit", "Weekly usage"]
        func heading(_ text: String, in titles: [String]) -> Bool {
            titles.contains { text.caseInsensitiveCompare($0) == .orderedSame }
        }
        guard let currentIndex = lines.firstIndex(where: { heading($0, in: currentTitles) }),
              let weeklyIndex = lines.firstIndex(where: { heading($0, in: weeklyTitles) }), currentIndex < weeklyIndex else { return nil }
        func window(_ values: ArraySlice<String>) -> Window? {
            var used: Int?
            var reset: String?
            for value in values {
                let text = value.lowercased()
                if text.range(of: #"^(已使用\s*\d{1,3}\s*%|\d{1,3}\s*%\s*used|used\s*\d{1,3}\s*%)$"#, options: .regularExpression) != nil {
                    used = Int(text.filter(\.isNumber))
                }
                if let split = value.range(of: #"^(重置时间\s*[:：]|resets?(\s+at|\s+on)?\s*[:：]?)\s*"#, options: [.regularExpression, .caseInsensitive]) {
                    let raw = String(value[split.upperBound...])
                    // Gemini's zh-CN UI can concatenate the day and 24-hour clock (“12月 112:25”).
                    reset = raw.replacingOccurrences(of: #"^(\d{1,2})月\s*(\d{1,2})日?\s*(\d{2}:\d{2})$"#,
                        with: "$1月$2日 $3", options: .regularExpression)
                }
            }
            guard let used, (0...100).contains(used) else { return nil }
            return Window(used: used, reset: reset)
        }
        let end = lines[(weeklyIndex + 1)...].firstIndex { heading($0, in: ["使用 AI 点数", "Use AI credits", "AI credits", "高级设置", "Advanced settings"]) } ?? lines.endIndex
        guard let current = window(lines[(currentIndex + 1)..<weeklyIndex]), let weekly = window(lines[(weeklyIndex + 1)..<end]) else { return nil }
        return Self(current: current, weekly: weekly, readAt: now,
                    pageUpdate: lines.first { $0.hasPrefix("更新时间") || $0.lowercased().hasPrefix("last updated") },
                    source: "pane")
    }

    private struct ChromeReportPayload: Decodable {
        struct Pool: Decodable {
            let used: Int
            let resetsAt: Double?
        }
        let observedAt: Double
        let current: Pool
        let weekly: Pool
    }

    enum ChromeReportState: Equatable, Sendable {
        case fresh(GeminiChatQuota)
        case stale(GeminiChatQuota)
        case missing
    }

    static let chromeFreshnessWindow: TimeInterval = 15 * 60

    static var chromeCacheURL: URL {
        if let override = ProcessInfo.processInfo.environment["GEMINI_CHAT_CHROME_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexUsageStatus/gemini-chat-chrome.json")
    }

    static var chromeNativeHostManifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Google/Chrome/NativeMessagingHosts/io.github.codexusagestatus.gemini_chat.json")
    }

    static func parseChromeReport(
        from data: Data,
        now: Date = Date(),
        maxAge: TimeInterval = chromeFreshnessWindow
    ) -> ChromeReportState {
        guard let payload = try? JSONDecoder().decode(ChromeReportPayload.self, from: data),
              (0...100).contains(payload.current.used),
              (0...100).contains(payload.weekly.used),
              payload.observedAt.isFinite else {
            return .missing
        }
        let observed = Date(timeIntervalSince1970: payload.observedAt)
        let currentReset = payload.current.resetsAt.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        let weeklyReset = payload.weekly.resetsAt.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        let quota = GeminiChatQuota(
            current: Window(used: payload.current.used, reset: nil, resetsAt: currentReset),
            weekly: Window(used: payload.weekly.used, reset: nil, resetsAt: weeklyReset),
            readAt: observed,
            pageUpdate: nil,
            source: "chrome"
        )
        let age = now.timeIntervalSince(observed)
        return age <= maxAge ? .fresh(quota) : .stale(quota)
    }

    static func readChromeReport(
        at url: URL = chromeCacheURL,
        now: Date = Date(),
        maxAge: TimeInterval = chromeFreshnessWindow
    ) -> ChromeReportState {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        return parseChromeReport(from: data, now: now, maxAge: maxAge)
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexUsageStatus/gemini-chat-last-read.json")
    }

    static func cached() -> Self? {
        let chrome: Self?
        switch readChromeReport() {
        case .fresh(let q), .stale(let q):
            chrome = q
        case .missing:
            chrome = nil
        }
        let saved: Self?
        if let data = try? Data(contentsOf: cacheURL),
           let value = try? JSONDecoder().decode(Self.self, from: data),
           (0...100).contains(value.current.used), (0...100).contains(value.weekly.used) {
            saved = value
        } else {
            saved = nil
        }
        switch (chrome, saved) {
        case let (c?, s?):
            return c.readAt >= s.readAt ? c : s
        case let (c?, nil):
            return c
        case let (nil, s?):
            return s
        case (nil, nil):
            return nil
        }
    }

    func save() throws {
        let url = Self.cacheURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

enum GeminiChatPane {
    static let bundleID = "com.google.GeminiMacOS"
    enum Reading: Sendable {
        case snapshot(GeminiChatQuota)
        case unavailable(String)
    }

    static func readBest(
        chromeURL: URL = GeminiChatQuota.chromeCacheURL,
        now: Date = Date(),
        paneReader: () -> Reading = { read() }
    ) -> Reading {
        let chromeState = GeminiChatQuota.readChromeReport(at: chromeURL, now: now)
        if case .fresh(let snapshot) = chromeState {
            return .snapshot(snapshot)
        }
        let paneReading = paneReader()
        if case .snapshot = paneReading {
            return paneReading
        }
        if case .stale = chromeState {
            return .unavailable("Chrome 已暂停同步")
        }
        if FileManager.default.fileExists(atPath: GeminiChatQuota.chromeNativeHostManifestURL.path) {
            return .unavailable("请在 Chrome 加载扩展")
        }
        return paneReading
    }

    static func read() -> Reading {
        guard AXIsProcessTrusted() else { return .unavailable("需辅助功能权限") }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .unavailable("Gemini 未运行")
        }
        func attribute(_ node: AXUIElement, _ key: String) -> AnyObject? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success else { return nil }
            return value
        }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        let windows = attribute(app, "AXWindows") as? [AXUIElement] ?? []
        guard let pane = windows.first(where: {
            let title = attribute($0, "AXTitle") as? String ?? ""
            return ["用量限额", "Usage limits"].contains { title.caseInsensitiveCompare($0) == .orderedSame }
        }) else { return .unavailable("请打开用量限额页") }

        func snapshot() -> GeminiChatQuota? {
            var lines: [String] = []
            func collect(_ node: AXUIElement, depth: Int) {
                guard depth < 16, let role = attribute(node, "AXRole") as? String else { return }
                if role == "AXStaticText" {
                    if let text = attribute(node, "AXValue") as? String { lines.append(text) }
                } else if ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea"].contains(role) {
                    for child in attribute(node, "AXChildren") as? [AXUIElement] ?? [] { collect(child, depth: depth + 1) }
                }
            }
            collect(pane, depth: 0)
            return GeminiChatQuota.parse(lines)
        }

        guard let initial = snapshot() else { return .unavailable("页面数据未就绪") }
        // Reload only the named control inside the Usage Limits toolbar. Never navigate or activate Gemini.
        let toolbar = (attribute(pane, "AXChildren") as? [AXUIElement])?.first {
            attribute($0, "AXRole") as? String == "AXToolbar"
        }
        func reloadButton(in node: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 4 else { return nil }
            if attribute(node, "AXRole") as? String == "AXButton" {
                let names = ["AXTitle", "AXDescription", "AXHelp"].compactMap { attribute(node, $0) as? String }
                if names.contains(where: { ["重新加载", "刷新", "reload", "refresh"].contains($0.lowercased()) }) { return node }
            }
            for child in attribute(node, "AXChildren") as? [AXUIElement] ?? [] {
                if let found = reloadButton(in: child, depth: depth + 1) { return found }
            }
            return nil
        }
        if let age = initial.pageUpdate, !age.contains("刚刚"), !age.lowercased().contains("just now"),
           let toolbar, let button = reloadButton(in: toolbar, depth: 0),
           AXUIElementPerformAction(button, "AXPress" as CFString) == .success {
            for _ in 0..<6 {
                Thread.sleep(forTimeInterval: 0.3)
                if let updated = snapshot(), updated.pageUpdate != age { return .snapshot(updated) }
            }
        }
        return .snapshot(initial)
    }
}
