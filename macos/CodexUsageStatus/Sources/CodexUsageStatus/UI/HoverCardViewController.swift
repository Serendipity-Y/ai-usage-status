import AppKit

@MainActor
final class HoverCardViewController: NSViewController {
    static let cardWidth: CGFloat = 648
    static let columnWidth: CGFloat = 302
    static let columnGap: CGFloat = 12
    static let size = NSSize(width: cardWidth, height: 320)

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    private let outerHorizontalPadding: CGFloat = 16
    private let outerVerticalPadding: CGFloat = 14

    private let codexResetTitle = NSTextField(labelWithString: "可用重置")
    private let codexResetValue = NSTextField(labelWithString: "暂未提供")
    private let codexRowViews = [QuotaRowView(), QuotaRowView()]
    private let codexStatus = NSTextField(labelWithString: "")

    private let geminiBadge = NSTextField(labelWithString: "未配置")
    private let geminiRowViews = (0..<5).map { _ in QuotaRowView() }
    private let geminiEmptyHint = NSTextField(labelWithString: "")
    private let geminiStatus = NSTextField(labelWithString: "")

    private let extraToolRowViews = [CreditToolRowView(), CreditToolRowView(), CreditToolRowView()]

    private let refresh = NSTextField(labelWithString: "等待首次刷新")

    private var rootStack: NSStackView!

    override func loadView() {
        let card = HoverCardView(frame: NSRect(origin: .zero, size: Self.size))
        card.onEnter = { [weak self] in self?.onEnter?() }
        card.onExit = { [weak self] in self?.onExit?() }
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 10
        view = card

        let geminiCard = makeGeminiSection()
        let codexCard = makeCodexSection()
        let extraToolsCard = makeExtraToolsSection()

        let rightColumn = NSStackView(views: [codexCard, extraToolsCard])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 12
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        for child in rightColumn.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true
        }

        let columnsContainer = NSView()
        columnsContainer.translatesAutoresizingMaskIntoConstraints = false
        columnsContainer.addSubview(geminiCard)
        columnsContainer.addSubview(rightColumn)

        let geminiStretch = geminiCard.bottomAnchor.constraint(equalTo: columnsContainer.bottomAnchor)
        geminiStretch.priority = .defaultHigh
        let rightStretch = rightColumn.bottomAnchor.constraint(equalTo: columnsContainer.bottomAnchor)
        rightStretch.priority = .defaultHigh

        NSLayoutConstraint.activate([
            geminiCard.leadingAnchor.constraint(equalTo: columnsContainer.leadingAnchor),
            geminiCard.topAnchor.constraint(equalTo: columnsContainer.topAnchor),
            geminiCard.bottomAnchor.constraint(lessThanOrEqualTo: columnsContainer.bottomAnchor),
            geminiCard.widthAnchor.constraint(equalToConstant: Self.columnWidth),
            geminiStretch,

            rightColumn.leadingAnchor.constraint(equalTo: geminiCard.trailingAnchor, constant: Self.columnGap),
            rightColumn.trailingAnchor.constraint(equalTo: columnsContainer.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: columnsContainer.topAnchor),
            rightColumn.bottomAnchor.constraint(lessThanOrEqualTo: columnsContainer.bottomAnchor),
            rightColumn.widthAnchor.constraint(equalToConstant: Self.columnWidth),
            rightStretch,
        ])

        style(refresh, size: 11.5, weight: .medium, color: NSColor(calibratedWhite: 0.32, alpha: 1))
        refresh.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let footerRow = horizontalRow(
            makeLabel("下次数据刷新", size: 11.5, weight: .regular, color: NSColor(calibratedWhite: 0.45, alpha: 1)),
            refresh
        )

        let stack = NSStackView(views: [columnsContainer, footerRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootStack = stack

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: outerHorizontalPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -outerHorizontalPadding),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: outerVerticalPadding),
            stack.widthAnchor.constraint(equalToConstant: Self.cardWidth - outerHorizontalPadding * 2),
        ])
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func update(_ presentation: HoverPresentation) {
        _ = view

        codexResetValue.stringValue = presentation.resetCredits
        codexResetValue.textColor = presentation.resetCredits == "暂未提供"
            ? NSColor(calibratedWhite: 0.50, alpha: 1)
            : NSColor(calibratedWhite: 0.13, alpha: 1)

        for (index, rowView) in codexRowViews.enumerated() {
            if index < presentation.codexRows.count {
                rowView.isHidden = false
                rowView.update(presentation.codexRows[index])
            } else {
                rowView.isHidden = true
            }
        }

        codexStatus.stringValue = presentation.isStale ? presentation.status : ""
        codexStatus.isHidden = !presentation.isStale
        codexStatus.textColor = Self.warningColor

        geminiBadge.stringValue = presentation.gemini.badgeText
        geminiBadge.textColor = presentation.gemini.isBadgeWarning
            ? Self.warningColor
            : NSColor(calibratedWhite: 0.44, alpha: 1)

        for (index, rowView) in geminiRowViews.enumerated() {
            if index < presentation.gemini.rows.count {
                rowView.isHidden = false
                rowView.update(presentation.gemini.rows[index])
            } else {
                rowView.isHidden = true
            }
        }

        if let hint = presentation.gemini.emptyHint, !hint.isEmpty {
            geminiEmptyHint.stringValue = hint
            geminiEmptyHint.isHidden = false
        } else {
            geminiEmptyHint.stringValue = ""
            geminiEmptyHint.isHidden = true
        }

        if let status = presentation.gemini.status, !status.isEmpty {
            geminiStatus.stringValue = status
            geminiStatus.isHidden = false
            geminiStatus.textColor = Self.warningColor
        } else {
            geminiStatus.stringValue = ""
            geminiStatus.isHidden = true
        }

        for (index, rowView) in extraToolRowViews.enumerated() {
            if index < presentation.extraToolRows.count {
                rowView.isHidden = false
                rowView.update(presentation.extraToolRows[index])
            } else {
                rowView.isHidden = true
            }
        }

        refresh.stringValue = presentation.nextRefresh

        view.layoutSubtreeIfNeeded()
        let contentHeight = ceil(rootStack.fittingSize.height + outerVerticalPadding * 2)
        preferredContentSize = NSSize(width: Self.cardWidth, height: max(180, contentHeight))

        // A visible popover owns its content frame. Resizing it here can reset
        // preferredContentSize to the old window height and clip dynamic rows.
        if view.window == nil {
            view.setFrameSize(preferredContentSize)
        }
    }

    private func makeCodexSection() -> NSView {
        let title = makeLabel("Codex", size: 12.5, weight: .semibold, color: NSColor(calibratedWhite: 0.12, alpha: 1))
        style(codexResetTitle, size: 11.5, weight: .regular, color: NSColor(calibratedWhite: 0.45, alpha: 1))
        style(codexResetValue, size: 12.5, weight: .semibold, color: NSColor(calibratedWhite: 0.13, alpha: 1))
        codexResetValue.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)

        let resetPair = NSStackView(views: [codexResetTitle, codexResetValue])
        resetPair.orientation = .horizontal
        resetPair.alignment = .firstBaseline
        resetPair.spacing = 4

        let header = horizontalRow(title, resetPair)

        style(codexStatus, size: 10.5, weight: .regular, color: Self.warningColor)
        codexStatus.isHidden = true

        return makeSectionCard(views: [header] + codexRowViews + [codexStatus], spacing: 12, verticalPadding: 12).0
    }

    private func makeExtraToolsSection() -> NSView {
        let title = makeLabel("其他工具", size: 12.5, weight: .semibold, color: NSColor(calibratedWhite: 0.12, alpha: 1))
        let subtitle = makeLabel("剩余积分", size: 11, weight: .regular, color: NSColor(calibratedWhite: 0.48, alpha: 1))
        let header = horizontalRow(title, subtitle)
        return makeSectionCard(views: [header] + extraToolRowViews, spacing: 12, verticalPadding: 12).0
    }

    private func makeGeminiSection() -> NSView {
        let title = makeLabel("Gemini", size: 12.5, weight: .semibold, color: NSColor(calibratedWhite: 0.12, alpha: 1))
        style(geminiBadge, size: 11, weight: .medium, color: NSColor(calibratedWhite: 0.44, alpha: 1))
        let header = horizontalRow(title, geminiBadge)

        style(geminiEmptyHint, size: 11, weight: .regular, color: NSColor(calibratedWhite: 0.46, alpha: 1))
        geminiEmptyHint.isHidden = true

        style(geminiStatus, size: 10.5, weight: .regular, color: Self.warningColor)
        geminiStatus.isHidden = true

        for row in geminiRowViews {
            row.isHidden = true
        }

        return makeSectionCard(views: [header] + geminiRowViews + [geminiEmptyHint, geminiStatus], spacing: 17.5, verticalPadding: 12).0
    }

    private func makeSectionCard(views: [NSView], spacing: CGFloat, verticalPadding: CGFloat) -> (NSView, NSStackView) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.968, alpha: 1).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(calibratedWhite: 0.90, alpha: 1).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalPadding),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -verticalPadding),
        ])
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return (container, stack)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        style(field, size: size, weight: weight, color: color)
        return field
    }

    private func style(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color ?? NSColor(calibratedWhite: 0.13, alpha: 1)
        field.lineBreakMode = .byClipping
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func horizontalRow(_ left: NSView, _ right: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [left, spacer, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private static let warningColor = NSColor(calibratedRed: 0.65, green: 0.32, blue: 0.05, alpha: 1)
}

@MainActor
private final class QuotaRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "--")
    private let resetLabel = NSTextField(labelWithString: "暂未提供")
    private let progressBar = QuotaProgressBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(_ row: QuotaRowPresentation) {
        titleLabel.stringValue = row.label
        percentLabel.stringValue = row.percentText
        resetLabel.stringValue = row.resetText
        percentLabel.textColor = Self.percentTextColor(for: row.percent)
        progressBar.percent = row.percent
        progressBar.isHidden = !row.showsProgressBar
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right
        percentLabel.textColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        percentLabel.lineBreakMode = .byClipping
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        resetLabel.alignment = .right
        resetLabel.textColor = NSColor(calibratedWhite: 0.46, alpha: 1)
        resetLabel.lineBreakMode = .byClipping
        resetLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topLine = NSStackView(views: [titleLabel, spacer, percentLabel, resetLabel])
        topLine.orientation = .horizontal
        topLine.alignment = .firstBaseline
        topLine.spacing = 6

        let stack = NSStackView(views: [topLine, progressBar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            topLine.widthAnchor.constraint(equalTo: stack.widthAnchor),
            percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
            resetLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    private static func percentTextColor(for percent: Int?) -> NSColor {
        guard let percent else {
            return NSColor(calibratedWhite: 0.50, alpha: 1)
        }
        switch percent {
        case 50...100:
            return NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.24, alpha: 1)
        case 20..<50:
            return NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.04, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.75, green: 0.16, blue: 0.16, alpha: 1)
        }
    }
}

@MainActor
private final class CreditToolRowView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "--")
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(_ row: QuotaRowPresentation) {
        nameLabel.stringValue = row.label
        valueLabel.stringValue = row.percentText
        statusLabel.stringValue = row.resetText
        if row.percentText != "--" {
            valueLabel.textColor = NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.24, alpha: 1)
        } else {
            valueLabel.textColor = NSColor(calibratedWhite: 0.50, alpha: 1)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = NSColor(calibratedWhite: 0.22, alpha: 1)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.textColor = NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.24, alpha: 1)
        valueLabel.lineBreakMode = .byClipping
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.alignment = .right
        statusLabel.textColor = NSColor(calibratedWhite: 0.48, alpha: 1)
        statusLabel.lineBreakMode = .byClipping
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [nameLabel, valueLabel, statusLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 72),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            statusLabel.widthAnchor.constraint(equalToConstant: 92),
        ])
    }
}

@MainActor
private final class QuotaProgressBarView: NSView {
    var percent: Int? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor(calibratedWhite: 0.87, alpha: 1).setFill()
        track.fill()

        guard let percent else { return }
        let clamped = max(0, min(100, percent))
        guard clamped > 0 else { return }

        let fillWidth = max(bounds.height, bounds.width * CGFloat(clamped) / 100.0)
        let fillRect = NSRect(x: 0, y: 0, width: min(bounds.width, fillWidth), height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        Self.fillColor(for: clamped).setFill()
        fill.fill()
    }

    private static func fillColor(for percent: Int) -> NSColor {
        switch percent {
        case 50...100:
            return NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.36, alpha: 0.92)
        case 20..<50:
            return NSColor(calibratedRed: 0.90, green: 0.54, blue: 0.10, alpha: 0.92)
        default:
            return NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.22, alpha: 0.92)
        }
    }
}

@MainActor
private final class HoverCardView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
