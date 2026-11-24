import AppKit
import Testing
@testable import CodexUsageStatus

private func sampleGeminiSummary() throws -> GeminiUsageSummary {
    let json = """
    {
      "plan": "AI Pro",
      "buckets": [
        {"label": "Gemini Pro", "remainingPercent": 82, "resetsAt": 1790766046},
        {"label": "Gemini Flash", "remainingPercent": 96, "resetsAt": 1790766046}
      ]
    }
    """
    return try GeminiUsageFetcher.decodeSummary(from: Data(json.utf8))
}

@Test @MainActor func visiblePopoverResizesForFailureAndRecovery() async throws {
    _ = NSApplication.shared
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: .borderless,
                        backing: .buffered, defer: false)
    let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
    host.contentView = anchor
    host.orderFront(nil)
    let controller = HoverCardViewController()
    let popover = NSPopover()
    popover.animates = false
    popover.contentViewController = controller
    popover.contentSize = HoverCardViewController.size
    defer { popover.close(); host.orderOut(nil) }

    controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false))
    let baselineHeight = controller.preferredContentSize.height
    popover.contentSize = controller.preferredContentSize
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)

    controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: true))
    let failedHeight = controller.preferredContentSize.height
    #expect(failedHeight > baselineHeight)
    popover.contentSize = controller.preferredContentSize
    try await Task.sleep(for: .milliseconds(50))
    #expect(popover.isShown)
    #expect(popover.contentSize.height == failedHeight)
    #expect(controller.view.frame.height == failedHeight)

    controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false))
    popover.contentSize = controller.preferredContentSize
    try await Task.sleep(for: .milliseconds(50))
    #expect(popover.contentSize.height == baselineHeight)
    #expect(controller.view.frame.height == baselineHeight)
}

@Test @MainActor func hoverCardStaysWhiteAndFitsAllSectionsAndFailureLabels() throws {
    let controller = HoverCardViewController()
    controller.update(HoverPresentation(usage: nil, nextRefreshDate: Date().addingTimeInterval(300),
        lastRefreshDate: nil, isRefreshing: false, refreshFailed: true))
    let view = controller.view
    view.appearance = NSAppearance(named: .darkAqua)
    view.layoutSubtreeIfNeeded()
    let color = view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.deviceRGB)
    #expect(color?.redComponent == 1)
    #expect(color?.greenComponent == 1)
    #expect(color?.blueComponent == 1)

    func visibleFields(in node: NSView) -> [NSTextField] {
        guard !node.isHidden else { return [] }
        return node.subviews.flatMap { child -> [NSTextField] in
            if child.isHidden { return [] }
            if let field = child as? NSTextField { return [field] }
            return visibleFields(in: child)
        }
    }

    let labels = visibleFields(in: view)
    #expect(labels.contains { $0.stringValue == "Codex" })
    #expect(labels.contains { $0.stringValue == "Gemini" })
    #expect(labels.contains { $0.stringValue == "更新失败 · 上次记录" })
    #expect(labels.contains { $0.stringValue == "暂未提供" })
    for label in labels {
        let frame = label.convert(label.bounds, to: view)
        #expect(frame.minX >= 0 && frame.maxX <= view.bounds.maxX)
        #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
        #expect(label.frame.width >= label.intrinsicContentSize.width)
    }

    let gemini = try sampleGeminiSummary()
    controller.update(HoverPresentation(
        usage: nil,
        nextRefreshDate: Date().addingTimeInterval(120),
        lastRefreshDate: Date(),
        isRefreshing: false,
        refreshFailed: false,
        geminiUsage: gemini,
        geminiLastRefreshDate: Date(),
        geminiError: nil
    ))
    view.layoutSubtreeIfNeeded()
    let geminiVisible = visibleFields(in: view)
    let visibleText = geminiVisible.map(\.stringValue)
    #expect(visibleText.contains("AI Pro"))
    #expect(visibleText.contains("Gemini Pro"))
    #expect(visibleText.contains("82%"))
    #expect(visibleText.contains("Gemini Flash"))
    #expect(visibleText.contains("96%"))
    #expect(!visibleText.contains("自动更新"))
    for label in geminiVisible {
        let frame = label.convert(label.bounds, to: view)
        #expect(frame.minX >= 0 && frame.maxX <= view.bounds.maxX)
        #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
        #expect(label.frame.width >= label.intrinsicContentSize.width)
    }

    for error in [FetchError.timeout, .authenticationRequired, .invalidOutput, .appServerError(-32000)] {
        controller.update(HoverPresentation(
            usage: nil,
            nextRefreshDate: nil,
            lastRefreshDate: Date().addingTimeInterval(-86400),
            isRefreshing: false,
            refreshFailed: true,
            failureDescription: error.briefDescription,
            geminiUsage: gemini,
            geminiLastRefreshDate: Date().addingTimeInterval(-3600),
            geminiError: .timeout
        ))
        view.layoutSubtreeIfNeeded()
        for label in visibleFields(in: view) {
            let frame = label.convert(label.bounds, to: view)
            #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
            #expect(label.frame.width >= label.intrinsicContentSize.width)
        }
    }
}

@Test @MainActor func geminiChatCardRendersAboveAntigravityCardWithoutClipping() throws {
    let controller = HoverCardViewController()
    let now = Date(timeIntervalSince1970: 1795512000)
    let chat = GeminiChatQuota(
        current: .init(used: 4, reset: nil, resetsAt: now.addingTimeInterval(3600)),
        weekly: .init(used: 1, reset: nil, resetsAt: now.addingTimeInterval(86400 * 5)),
        readAt: now,
        pageUpdate: nil,
        source: "chrome"
    )
    let agJSON = """
    {"plan":"Antigravity","buckets":[
      {"id":"antigravity-quota-summary-gemini-5h","label":"5 小时","remainingPercent":80,"resetsAt":1795526700},
      {"id":"antigravity-quota-summary-gemini-weekly","label":"每周","remainingPercent":92,"resetsAt":1796100300},
      {"id":"antigravity-quota-summary-gemini-argon-wtu-weekly","label":"Argon 每周","remainingPercent":90,"resetsAt":1796100300}
    ]}
    """
    let ag = try GeminiUsageFetcher.decodeSummary(from: Data(agJSON.utf8))
    controller.update(HoverPresentation(
        usage: nil,
        nextRefreshDate: now.addingTimeInterval(120),
        lastRefreshDate: now,
        isRefreshing: false,
        refreshFailed: false,
        now: now,
        geminiUsage: ag,
        geminiLastRefreshDate: now,
        geminiError: nil,
        chatQuota: chat,
        chatUnavailable: nil
    ))
    let view = controller.view
    view.layoutSubtreeIfNeeded()

    func visibleFields(in node: NSView) -> [NSTextField] {
        guard !node.isHidden else { return [] }
        return node.subviews.flatMap { child -> [NSTextField] in
            if child.isHidden { return [] }
            if let field = child as? NSTextField { return [field] }
            return visibleFields(in: child)
        }
    }

    let fields = visibleFields(in: view)
    let geminiHeader = try #require(fields.first { $0.stringValue == "Gemini" })
    let agHeader = try #require(fields.first { $0.stringValue == "Antigravity" })
    let geminiFrame = geminiHeader.convert(geminiHeader.bounds, to: view)
    let agFrame = agHeader.convert(agHeader.bounds, to: view)
    // AppKit default coordinate origin is bottom-left, so higher minY means visually above.
    #expect(geminiFrame.minY > agFrame.minY)
    for field in fields {
        let frame = field.convert(field.bounds, to: view)
        #expect(frame.minX >= 0 && frame.maxX <= view.bounds.maxX)
        #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
        #expect(field.frame.width >= field.intrinsicContentSize.width)
    }
}
