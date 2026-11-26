import AppKit
import Foundation
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let compactRingItem = NSMenuItem(title: BadgeStyle.compactRing.menuTitle, action: #selector(selectCompactRingStyle), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")

    private lazy var codexSchedule = RefreshSchedule(interval: refreshInterval,
        fetch: { [unowned self] in await refreshCodex() }, onChange: { [unowned self] in refreshStateChanged() })
    private lazy var geminiSchedule = RefreshSchedule(interval: refreshInterval,
        fetch: { [unowned self] in await refreshGemini() }, onChange: { [unowned self] in refreshStateChanged() })
    private let refreshLog = Logger(subsystem: "io.github.codexusagestatus", category: "refresh")
    private let refreshInterval = configuredRefreshInterval()
    private var badgeStyle = BadgeStyle.load()
    private let hasGeminiChat = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GeminiChatPane.bundleID) != nil
        || FileManager.default.fileExists(atPath: GeminiChatQuota.chromeNativeHostManifestURL.path)
        || FileManager.default.fileExists(atPath: GeminiChatQuota.chromeCacheURL.path)
    private var chatQuota = GeminiChatQuota.cached()
    private var chatUnavailable: String? = "等待读取 Gemini 额度"
    private lazy var chatSchedule = RefreshSchedule(interval: refreshInterval,
        fetch: { [unowned self] in await refreshChat() }, onChange: { [unowned self] in refreshStateChanged() })
    private var lastUsage: UsageSummary?
    private var lastRefreshDate: Date?
    private var lastError: Error?
    private var lastGeminiUsage: GeminiUsageSummary?
    private var lastGeminiRefreshDate: Date?
    private var lastGeminiError: GeminiFetchError?
    private var buttonTrackingArea: NSTrackingArea?
    private var hoverShowWork: DispatchWorkItem?
    private var hoverHideWork: DispatchWorkItem?
    private var menuIsOpen = false
    private var previewShown = false
    private lazy var hoverCard: HoverCardViewController = {
        let card = HoverCardViewController()
        card.onEnter = { [weak self] in self?.hoverHideWork?.cancel() }
        card.onExit = { [weak self] in self?.scheduleHoverClose() }
        return card
    }()
    private lazy var hoverPopover: NSPopover = {
        let popover = NSPopover()
        popover.contentViewController = hoverCard
        popover.contentSize = HoverCardViewController.size
        popover.appearance = NSAppearance(named: .aqua)
        popover.behavior = .applicationDefined
        popover.animates = false
        return popover
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--show-hover") {
            FileHandle.standardOutput.write(Data("UI launch callback received\n".utf8))
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = nil
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            button.addTrackingArea(area)
            buttonTrackingArea = area
        }
        renderCurrentBadge()

        refreshItem.target = self
        menu.addItem(refreshItem)

        doubleRingItem.target = self
        largeReadoutItem.target = self
        compactRingItem.target = self
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
        displayStyleMenu.addItem(compactRingItem)
        displayStyleItem.submenu = displayStyleMenu
        menu.addItem(displayStyleItem)
        updateStyleMenuState()

        if hasGeminiChat && !AXIsProcessTrusted() {
            let access = NSMenuItem(title: "授权读取 Gemini 聊天额度…", action: #selector(requestChatAccess), keyEquivalent: "")
            access.target = self
            menu.addItem(access)
        }
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        refresh()
    }

    @objc(mouseEntered:) private func statusMouseEntered(_ event: NSEvent) {
        hoverHideWork?.cancel()
        hoverShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showHoverPopover() }
        hoverShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc(mouseExited:) private func statusMouseExited(_ event: NSEvent) {
        hoverShowWork?.cancel()
        scheduleHoverClose()
    }

    private func scheduleHoverClose() {
        hoverHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hoverPopover.close() }
        hoverHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func showHoverPopover() {
        guard !menuIsOpen, let button = statusItem.button, button.window != nil else { return }
        if hasGeminiChat, case .fresh(let latest) = GeminiChatQuota.readChromeReport() {
            chatQuota = latest
            chatUnavailable = nil
            try? latest.save()
        }
        updateHoverCard()
        hoverPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if CommandLine.arguments.contains("--show-hover") {
            FileHandle.standardOutput.write(Data("Hover visible: \(hoverPopover.isShown)\n".utf8))
            if let path = ProcessInfo.processInfo.environment["CODEX_USAGE_PREVIEW_PNG"] {
                hoverCard.view.layoutSubtreeIfNeeded()
                if let bitmap = hoverCard.view.bitmapImageRepForCachingDisplay(in: hoverCard.view.bounds) {
                    hoverCard.view.cacheDisplay(in: hoverCard.view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        hoverShowWork?.cancel()
        hoverHideWork?.cancel()
        hoverPopover.close()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func updateHoverCard() {
        hoverCard.update(HoverPresentation(
            usage: lastUsage,
            nextRefreshDate: [codexSchedule.nextRefreshDate, geminiSchedule.nextRefreshDate, hasGeminiChat ? chatSchedule.nextRefreshDate : nil].compactMap { $0 }.min(),
            lastRefreshDate: lastRefreshDate,
            isRefreshing: codexSchedule.isRefreshing,
            refreshFailed: lastError != nil,
            failureDescription: (lastError as? FetchError)?.briefDescription ?? "读取失败",
            geminiUsage: lastGeminiUsage,
            geminiLastRefreshDate: lastGeminiRefreshDate,
            geminiError: lastGeminiError,
            geminiIsRefreshing: geminiSchedule.isRefreshing,
            chatQuota: hasGeminiChat ? chatQuota : nil,
            chatUnavailable: hasGeminiChat ? chatUnavailable : nil
        ))
        hoverPopover.contentSize = hoverCard.preferredContentSize
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func selectDoubleRingStyle() {
        setBadgeStyle(.doubleRing)
    }

    @objc private func selectLargeReadoutStyle() {
        setBadgeStyle(.largeReadout)
    }

    @objc private func selectCompactRingStyle() {
        setBadgeStyle(.compactRing)
    }

    @objc private func showSettings() {
        let status: String
        if let lastError {
            status = "Last refresh failed: \(lastError.localizedDescription)"
        } else if let lastUsage {
            status = lastUsage.verboseTitle
        } else {
            status = "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { dateFormatter.string(from: $0) } ?? "Never"
        let geminiSource = GeminiUsageFetcher.resolvedSource().displayDescription
        let geminiStatus: String
        if let lastGeminiUsage {
            geminiStatus = lastGeminiUsage.cliSummary
        } else if let lastGeminiError {
            geminiStatus = lastGeminiError.briefDescription
        } else {
            geminiStatus = "Waiting for first refresh"
        }
        let message = """
        \(status)
        Gemini: \(geminiStatus)

        Display style: \(badgeStyle.menuTitle)
        Refresh interval: \(Int(refreshInterval)) seconds
        Failure retry: 60 / 120 / \(Int(AppConfig.errorRetryInterval)) seconds
        Last refresh: \(lastRefresh)
        Codex source: local Codex app-server
        Gemini source: \(geminiSource)
        """

        let alert = NSAlert()
        alert.messageText = "Codex Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setBadgeStyle(_ style: BadgeStyle) {
        guard badgeStyle != style else {
            return
        }
        badgeStyle = style
        badgeStyle.save()
        updateStyleMenuState()
        renderCurrentBadge()
    }

    private func updateStyleMenuState() {
        doubleRingItem.state = badgeStyle == .doubleRing ? .on : .off
        largeReadoutItem.state = badgeStyle == .largeReadout ? .on : .off
        compactRingItem.state = badgeStyle == .compactRing ? .on : .off
    }

    private func refresh() {
        codexSchedule.refresh()
        geminiSchedule.refresh()
        if hasGeminiChat { chatSchedule.refresh() }
    }

    @objc private func requestChatAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        chatSchedule.refresh()
    }

    private func refreshChat() async -> Bool {
        let reading = await Task.detached(priority: .utility) { GeminiChatPane.readBest() }.value
        switch reading {
        case .snapshot(let snapshot):
            chatQuota = snapshot
            chatUnavailable = nil
            try? snapshot.save()
        case .unavailable(let reason):
            if let cached = GeminiChatQuota.cached(),
               chatQuota == nil || cached.readAt > (chatQuota?.readAt ?? .distantPast) {
                chatQuota = cached
            }
            chatUnavailable = reason
        }
        return true
    }

    private func refreshCodex() async -> Bool {
        do {
            let usage = try await CodexUsageFetcher.fetch()
            if codexSchedule.consecutiveFailures > 0 {
                refreshLog.notice("Usage refresh recovered after \(self.codexSchedule.consecutiveFailures) failures")
            }
            lastUsage = usage
            lastRefreshDate = Date()
            lastError = nil
            return true
        } catch {
            let retry = AppConfig.retryInterval(afterFailures: codexSchedule.consecutiveFailures + 1)
            let reason = (error as? FetchError)?.briefDescription ?? "读取失败"
            refreshLog.error("Usage refresh failed: \(reason, privacy: .public); retry in \(Int(retry)) seconds")
            if let fetchError = error as? FetchError, case .appServerError(let code) = fetchError {
                if let code {
                    refreshLog.error("RPC error code: \(code)")
                } else {
                    refreshLog.error("RPC error code: unknown")
                }
            }
            lastError = error
            return false
        }
    }

    private func refreshGemini() async -> Bool {
        defer { renderCurrentBadge() }
        do {
            lastGeminiUsage = try await GeminiUsageFetcher.fetch()
            lastGeminiRefreshDate = Date()
            lastGeminiError = nil
            return true
        } catch {
            let failure = error as? GeminiFetchError ?? .invalidOutput
            lastGeminiError = failure
            if failure == .notConfigured {
                lastGeminiUsage = nil
                lastGeminiRefreshDate = nil
                return true // Poll at the normal interval for a newly configured optional source.
            }
            refreshLog.error("Gemini usage refresh failed: \(failure.briefDescription, privacy: .public)")
            return false
        }
    }

    private func refreshStateChanged() {
        let bothBusy = codexSchedule.isRefreshing && geminiSchedule.isRefreshing
        refreshItem.isEnabled = !bothBusy
        refreshItem.title = bothBusy ? "Refreshing..." : "Refresh"
        updateHoverCard()
        if CommandLine.arguments.contains("--show-hover"), !previewShown,
           codexSchedule.nextRefreshDate != nil, geminiSchedule.nextRefreshDate != nil,
           !hasGeminiChat || chatSchedule.nextRefreshDate != nil {
            previewShown = true
            showHoverPopover()
        }
    }

    private func renderCurrentBadge() {
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        if let button = statusItem.button {
            button.title = ""
            button.toolTip = nil

            if let lastGeminiError {
                button.image = UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel("Antigravity 额度更新失败：\(lastGeminiError.briefDescription)")
            } else if let lastGeminiUsage {
                button.image = UsageBadgeRenderer.image(for: lastGeminiUsage, style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel(lastGeminiUsage.antigravityBadgeDescription)
            } else {
                button.image = UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel("Antigravity 每周额度正在读取")
            }
        }
    }
}
