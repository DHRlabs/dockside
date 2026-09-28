import AppKit

@MainActor
final class BubblePanel: NSPanel {
    static let dockGap: CGFloat = 8
    // Measured on Lance's Mac: AX list top y 1372, Dock plate top y 1377, with 44-point icons.
    static let dockPlateVerticalCalibration: CGFloat = 5
    // Picked to match the corner curvature of the 58-point Tahoe Dock plate.
    static let dockPlateCornerRadius: CGFloat = 15
    fileprivate static let meterGapRatio: CGFloat = 0.25
    fileprivate static let horizontalInsetRatio: CGFloat = 0.28
    // Lance's dark-mode Dock plate calibration: black tint over regular glass.
    static let tintAlpha: CGFloat = 0.55
    // Measured black veil compensating for NSGlassEffectView's brighter black tint.
    static let darkGlassVeilAlpha: CGFloat = 0.70
    // A one-point inner rim, tuned against the Dock's lighter plate edge.
    static let glassRimAlpha: CGFloat = 0.22

    fileprivate struct MeterFonts {
        let name: NSFont
        let percent: NSFont
        let gap: CGFloat
        let lineHeight: CGFloat
    }

    fileprivate static func meterFonts(nameSize: CGFloat, percentSize: CGFloat) -> MeterFonts {
        let name = NSFont.systemFont(ofSize: nameSize, weight: .regular)
        let percent = NSFont.monospacedDigitSystemFont(ofSize: percentSize, weight: .bold)
        let lineHeight = max(fontHeight(name), fontHeight(percent))
        return MeterFonts(name: name, percent: percent, gap: lineHeight * 0.25, lineHeight: lineHeight)
    }

    fileprivate static func meterTitleLineWidth(_ reading: UsageReading, at now: Date,
                                                 fonts: MeterFonts) -> CGFloat {
        let nameWidth = ceil(textSize(reading.label, font: fonts.name).width)
        let percentWidth = ceil(textSize(reading.percentageText(at: now), font: fonts.percent).width)
        guard let reset = reading.resetLine(at: now) else {
            return nameWidth + percentWidth + fonts.gap
        }
        return nameWidth + percentWidth + 2 * fonts.gap + ceil(textSize(reset, font: fonts.name).width)
    }

    fileprivate static func fittedMeterFonts(height: CGFloat, readings: [UsageReading],
                                             meterWidth: CGFloat) -> MeterFonts {
        var nameSize = max(6, height * 0.2)
        var percentSize = max(6, height * 0.22)
        var fonts = meterFonts(nameSize: nameSize, percentSize: percentSize)
        while nameSize > 6 || percentSize > 6 {
            let widestLabel = readings.map { ceil(textSize($0.label, font: fonts.name).width) }.max() ?? 0
            guard widestLabel + ceil(textSize("100%", font: fonts.percent).width) + fonts.gap > meterWidth else {
                break
            }
            nameSize = max(6, nameSize - 0.1)
            percentSize = max(6, percentSize - 0.1)
            fonts = meterFonts(nameSize: nameSize, percentSize: percentSize)
        }
        return fonts
    }

    fileprivate static func meterWidths(height: CGFloat, readings: [UsageReading])
        -> (natural: CGFloat, minimum: CGFloat) {
        let fonts = meterFonts(nameSize: 6, percentSize: 6)
        let nameWidth = readings.map { ceil(textSize($0.label, font: fonts.name).width) }.max() ?? 0
        let minimum = nameWidth + ceil(textSize("100%", font: fonts.percent).width) + fonts.gap
        return (height * 1.6, minimum)
    }

    fileprivate static func meterLayout(height: CGFloat, available: CGFloat, count: Int,
                                        naturalMeterWidth: CGFloat, minimumMeterWidth: CGFloat)
        -> (inset: CGFloat, gap: CGFloat, meterWidth: CGFloat, width: CGFloat)? {
        guard count > 0 else { return nil }
        let inset = height * horizontalInsetRatio
        let gap = height * meterGapRatio
        let meterWidth = min(naturalMeterWidth,
                             max(0, (available - 2 * inset - gap * CGFloat(count - 1)) / CGFloat(count)))
        guard meterWidth >= min(minimumMeterWidth, naturalMeterWidth) else { return nil }
        let width = 2 * inset + CGFloat(count) * meterWidth + CGFloat(count - 1) * gap
        return (inset, gap, meterWidth, min(available, width))
    }

    private let bubbleView = BubbleView()
    private let hoverCard = HoverCardPanel()
    private var dockFrame: CGRect?
    private var readings: [UsageReading] = []
    private var openTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var glassSettingsTimer: Timer?
    var onGlassAppearanceRefresh: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = bubbleView
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        bubbleView.onHover = { [weak self] inside in self?.bubbleHoverChanged(inside) }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshGlassAppearance() } }
        // ponytail: 2-second glass preference latency; use a per-key notification if one becomes public.
        glassSettingsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshGlassAppearance()
            }
        }
        orderOut(nil)
    }

    func update(_ readings: [UsageReading]) {
        self.readings = readings
        bubbleView.update(readings)
        hoverCard.update(readings)
        if let dockFrame { place(leftOf: dockFrame) }
    }

    func place(leftOf dockFrame: CGRect?) {
        guard let dockFrame, let screen = screen(for: dockFrame) else {
            self.dockFrame = nil
            orderOut(nil)
            hideHoverCard()
            return
        }
        self.dockFrame = dockFrame
        let count = max(1, readings.count)
        let height = dockFrame.height
        let available = dockFrame.minX - Self.dockGap - screen.frame.minX
        let widths = Self.meterWidths(height: height, readings: readings)
        guard let layout = Self.meterLayout(height: height, available: available, count: count,
                                            naturalMeterWidth: widths.natural,
                                            minimumMeterWidth: widths.minimum) else {
            orderOut(nil)
            hideHoverCard()
            return
        }

        let frame = NSRect(x: dockFrame.minX - Self.dockGap - layout.width,
                           y: max(screen.frame.minY, dockFrame.minY - Self.dockPlateVerticalCalibration),
                           width: layout.width, height: height)
        setFrame(frame, display: true)
        orderFrontRegardless()
        if hoverCard.isVisible { placeHoverCard(on: screen) }
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .rightMouseDown, let contentView else { return super.sendEvent(event) }
        DocksideContextMenu.popUp(with: event, for: contentView)
    }

    override func mouseDown(with event: NSEvent) {}
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    private func bubbleHoverChanged(_ inside: Bool) {
        if inside {
            openTimer?.invalidate()
            guard !hoverCard.isVisible else { return }
            openTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.showHoverCard() }
            }
        } else {
            hideHoverCard()
        }
    }

    private func showHoverCard() {
        guard isVisible, let dockFrame, let screen = screen(for: dockFrame) else { return }
        placeHoverCard(on: screen)
        hoverCard.show()
    }

    private func placeHoverCard(on screen: NSScreen) {
        let size = hoverCard.size(for: readings)
        let width = min(size.width, screen.frame.width)
        let height = min(size.height, screen.frame.height)
        let x = min(max(frame.minX, screen.frame.minX), screen.frame.maxX - width)
        let y = min(frame.maxY + 8, screen.frame.maxY - height)
        hoverCard.setFrame(NSRect(x: x, y: max(screen.frame.minY, y), width: width, height: height), display: true)
    }

    private func hideHoverCard() {
        openTimer?.invalidate()
        openTimer = nil
        hoverCard.hide()
    }

    private func refreshGlassAppearance() {
        bubbleView.refreshGlassAppearance()
        hoverCard.refreshGlassAppearance()
        onGlassAppearanceRefresh?()
    }
}

@MainActor
private final class BubbleView: NSView {
    private let meters: UsageMetersView
    private let backdrop: GlassBackdropView
    var onHover: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        let meters = UsageMetersView(frame: .zero)
        self.meters = meters
        backdrop = GlassBackdropView(contentView: meters, cornerRadius: BubblePanel.dockPlateCornerRadius)
        super.init(frame: frameRect)
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    func update(_ readings: [UsageReading]) {
        meters.readings = readings
        meters.needsDisplay = true
    }

    func refreshGlassAppearance() { backdrop.refreshAppearance() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        meters.needsDisplay = true
    }
}

@MainActor
private final class UsageMetersView: NSView {
    var readings: [UsageReading] = []
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        let count = readings.count
        let now = Date()
        let widths = BubblePanel.meterWidths(height: height, readings: readings)
        guard let layout = BubblePanel.meterLayout(
            height: height, available: bounds.width, count: count,
            naturalMeterWidth: widths.natural, minimumMeterWidth: widths.minimum) else {
            return
        }
        let inset = layout.inset
        let gap = layout.gap
        let meterWidth = layout.meterWidth
        let fonts = BubblePanel.fittedMeterFonts(height: height, readings: readings,
                                                 meterWidth: meterWidth)
        let barGap = height * 0.06
        let barHeight = height * 0.08
        let resetFont = NSFont.systemFont(ofSize: max(6, height * 9 / 58))
        let resetHeight = fontHeight(resetFont)
        let resetGap = height * 4 / 58
        let blockHeight = resetHeight + resetGap + barHeight + barGap + fonts.lineHeight
        let resetY = (height - blockHeight) / 2
        let barY = resetY + resetHeight + resetGap
        let lineY = barY + barHeight + barGap

        for (index, reading) in readings.enumerated() {
            let x = inset + CGFloat(index) * (meterWidth + gap)
            drawMeterTitleLine(reading, at: now,
                               in: NSRect(x: x, y: lineY, width: meterWidth, height: fonts.lineHeight),
                               fonts: fonts, showReset: false,
                               isDark: isDarkAppearance)
            drawMeter(reading, in: NSRect(x: x, y: barY, width: meterWidth, height: barHeight),
                      at: now, dockHeight: height, isDark: isDarkAppearance)
            if let reset = reading.resetLine(at: now) {
                drawText(reset, in: NSRect(x: x, y: resetY, width: meterWidth, height: resetHeight),
                         font: resetFont, color: meterTertiaryLabelColor(isDark: isDarkAppearance))
            }
        }
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
private final class HoverCardPanel: NSPanel {
    private static let width: CGFloat = 260
    fileprivate static let rowHeight: CGFloat = 48
    private let cardView: HoverCardView

    init() {
        let cardView = HoverCardView()
        self.cardView = cardView
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 1),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = cardView
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        orderOut(nil)
    }

    func size(for readings: [UsageReading]) -> NSSize {
        let fonts = BubblePanel.meterFonts(nameSize: 12, percentSize: 13)
        let now = Date()
        let naturalWidth = readings.map {
            BubblePanel.meterTitleLineWidth($0, at: now, fonts: fonts)
        }.max() ?? 0
        return NSSize(width: max(Self.width, ceil(naturalWidth) + 24),
                      height: 24 + Self.rowHeight * CGFloat(max(1, readings.count)))
    }

    func update(_ readings: [UsageReading]) { cardView.update(readings) }
    func refreshGlassAppearance() { cardView.refreshGlassAppearance() }

    func show() {
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
private final class HoverCardView: NSView {
    private let rows: HoverCardRowsView
    private let backdrop: GlassBackdropView

    override init(frame frameRect: NSRect) {
        let rows = HoverCardRowsView(frame: .zero)
        self.rows = rows
        backdrop = GlassBackdropView(contentView: rows, cornerRadius: 14)
        super.init(frame: frameRect)
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
    }

    func update(_ readings: [UsageReading]) {
        rows.readings = readings
        rows.needsDisplay = true
    }

    func refreshGlassAppearance() { backdrop.refreshAppearance() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rows.needsDisplay = true
    }
}

@MainActor
private final class HoverCardRowsView: NSView {
    var readings: [UsageReading] = []
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let padding: CGFloat = 12
        let rowHeight = HoverCardPanel.rowHeight
        let fonts = BubblePanel.meterFonts(nameSize: 12, percentSize: 13)
        let barGap: CGFloat = 3.5
        let barHeight: CGFloat = 4.5
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let now = Date()

        for (index, reading) in readings.enumerated() {
            let top = bounds.maxY - padding - CGFloat(index) * rowHeight
            let lineY = top - fonts.lineHeight
            drawMeterTitleLine(reading, at: now,
                               in: NSRect(x: padding, y: lineY, width: bounds.width - padding * 2,
                                          height: fonts.lineHeight),
                               fonts: fonts, showReset: true,
                               isDark: isDark)
            drawMeter(reading,
                      in: NSRect(x: padding, y: lineY - barGap - barHeight,
                                 width: bounds.width - padding * 2, height: barHeight),
                      at: now, dockHeight: 58, isDark: isDark)
            if let verdict = reading.verdictLine(at: now) {
                drawText(verdict,
                         in: NSRect(x: padding, y: top - rowHeight + 3,
                                    width: bounds.width - padding * 2, height: 14),
                         font: NSFont.systemFont(ofSize: 11), color: .secondaryLabelColor)
            }
            if index + 1 < readings.count {
                let divider = NSBezierPath()
                divider.lineWidth = 0.5
                divider.move(to: NSPoint(x: padding, y: top - rowHeight))
                divider.line(to: NSPoint(x: bounds.maxX - padding, y: top - rowHeight))
                NSColor.separatorColor.setStroke()
                divider.stroke()
            }
        }
    }
}

@MainActor
final class GlassBackdropView: NSView {
    private let content: NSView
    private let glassView: NSView?
    private let glassContent = NSView()
    private let legacyView = NSVisualEffectView(frame: .zero)
    private let opaqueView: OpaqueBackdropView
    private let cornerRadius: CGFloat
    private var activeBackdrop: NSView?
    private var lastTintedSetting: Bool?
    private var lastIsDark: Bool?
    private var lastReduceTransparency: Bool?

    init(contentView: NSView, cornerRadius: CGFloat) {
        content = contentView
        self.cornerRadius = cornerRadius
        opaqueView = OpaqueBackdropView(cornerRadius: cornerRadius)
        if #available(macOS 26.0, *) {
            glassView = NSGlassEffectView(frame: .zero)
        } else {
            glassView = nil
        }
        super.init(frame: .zero)
        if let glassView {
            glassContent.wantsLayer = true
            glassContent.layer?.cornerRadius = cornerRadius
            glassContent.layer?.masksToBounds = true
            addSubview(glassView)
        }
        legacyView.material = .hudWindow
        legacyView.blendingMode = .behindWindow
        legacyView.state = .active
        legacyView.wantsLayer = true
        legacyView.layer?.masksToBounds = true
        legacyView.layer?.cornerRadius = cornerRadius
        addSubview(legacyView)
        addSubview(opaqueView)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glassView?.frame = bounds
        glassContent.frame = bounds
        legacyView.frame = bounds
        opaqueView.frame = bounds
        content.frame = (activeBackdrop === glassView ? glassContent.bounds : activeBackdrop?.bounds) ?? bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        content.needsDisplay = true
    }

    func refreshAppearance() {
        let isTinted = UserDefaults.standard.bool(forKey: "NSGlassDiffusionSetting")
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        guard isTinted != lastTintedSetting || isDark != lastIsDark ||
              reduceTransparency != lastReduceTransparency else { return }
        lastTintedSetting = isTinted
        lastIsDark = isDark
        lastReduceTransparency = reduceTransparency

        let chosen: NSView
        if reduceTransparency {
            chosen = opaqueView
        } else if #available(macOS 26.0, *), let glassView {
            chosen = glassView
            configureGlass(glassView, isTinted: isTinted, isDark: isDark)
        } else {
            chosen = legacyView
        }

        if activeBackdrop !== chosen {
            if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
                glass.contentView = nil
            }
            content.removeFromSuperview()
            if #available(macOS 26.0, *), let glass = chosen as? NSGlassEffectView {
                glassContent.addSubview(content)
                glass.contentView = glassContent
            } else {
                chosen.addSubview(content)
            }
            activeBackdrop = chosen
        }
        glassView?.isHidden = glassView !== chosen
        legacyView.isHidden = legacyView !== chosen
        opaqueView.isHidden = opaqueView !== chosen
        needsLayout = true
        opaqueView.needsDisplay = true
    }

    @available(macOS 26.0, *)
    private func configureGlass(_ view: NSView, isTinted: Bool, isDark: Bool) {
        guard let view = view as? NSGlassEffectView else { return }
        view.style = isTinted ? .regular : .clear
        view.tintColor = isTinted ? (isDark
            ? NSColor.black.withAlphaComponent(BubblePanel.tintAlpha)
            : NSColor.white.withAlphaComponent(BubblePanel.tintAlpha)) : nil
        view.cornerRadius = cornerRadius
        view.wantsLayer = true
        glassContent.layer?.backgroundColor = !isTinted || !isDark ? nil
            : NSColor.black.withAlphaComponent(BubblePanel.darkGlassVeilAlpha).cgColor
        glassContent.layer?.borderWidth = isTinted ? 1 : 0
        glassContent.layer?.borderColor = NSColor.white.withAlphaComponent(BubblePanel.glassRimAlpha).cgColor
    }
}

@MainActor
private final class OpaqueBackdropView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private func textSize(_ text: String, font: NSFont) -> NSSize {
    (text as NSString).size(withAttributes: [.font: font])
}

private func fontHeight(_ font: NSFont) -> CGFloat {
    font.ascender - font.descender + font.leading
}

private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor,
                      alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(in: rect,
                            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

@MainActor
private func drawMeterTitleLine(_ reading: UsageReading, at now: Date, in rect: NSRect,
                                fonts: BubblePanel.MeterFonts,
                                showReset: Bool,
                                isDark: Bool) {
    let nameWidth = ceil(textSize(reading.label, font: fonts.name).width)
    let percent = reading.percentageText(at: now)
    let percentWidth = ceil(textSize(percent, font: fonts.percent).width)
    let gap = fonts.gap
    let baselineOffset = fonts.percent.ascender - fonts.name.ascender
    let percentX = rect.maxX - percentWidth
    let nameColor = meterSecondaryLabelColor(isDark: isDark)
    drawText(reading.label,
             in: NSRect(x: rect.minX, y: rect.minY - baselineOffset,
                        width: nameWidth, height: rect.height),
             font: fonts.name, color: nameColor)
    drawText(percent,
             in: NSRect(x: percentX, y: rect.minY, width: percentWidth, height: rect.height),
             font: fonts.percent,
             color: reading.share(at: now) == nil ? meterTertiaryLabelColor(isDark: isDark) : nameColor,
             alignment: .right)

    if showReset, let reset = reading.resetLine(at: now) {
        let resetX = rect.minX + nameWidth + gap
        let resetWidth = percentX - resetX - gap
        if resetWidth >= textSize(reset, font: fonts.name).width {
            drawText(reset,
                     in: NSRect(x: resetX, y: rect.minY - baselineOffset,
                                width: resetWidth, height: rect.height),
                     font: fonts.name, color: meterTertiaryLabelColor(isDark: isDark))
        }
    }
}

@MainActor
private func drawMeter(_ reading: UsageReading, in rect: NSRect, at now: Date,
                       dockHeight: CGFloat, isDark: Bool) {
    guard rect.width > 0, rect.height > 0 else { return }
    let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    meterTrackColor(isDark: isDark).setFill()
    track.fill()
    guard let share = reading.share(at: now) else { return }

    if share > 0 {
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * share, height: rect.height)
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        fillColor(for: reading.provider).setFill()
        fill.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    if let pace = reading.pace(at: now) {
        let tickWidth = max(1.5, dockHeight * 2 / 58)
        let tickExtension = dockHeight * 3 / 58
        let tick = NSRect(x: rect.minX + rect.width * pace - tickWidth / 2,
                          y: rect.minY - tickExtension,
                          width: tickWidth, height: rect.height + 2 * tickExtension)
        if case .grok = reading.provider {
            (isDark ? NSColor.black : NSColor.white).withAlphaComponent(0.65).setFill()
            NSRect(x: tick.minX - 0.75, y: rect.minY, width: tick.width + 1.5, height: rect.height).fill()
        }
        (isDark ? NSColor.white : NSColor.labelColor).setFill()
        tick.fill()
    }
}

private func fillColor(for provider: UsageReading.Provider) -> NSColor {
    switch provider {
    case .claude: return NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1)
    case .codex: return NSColor(srgbRed: 63.0 / 255, green: 191.0 / 255, blue: 178.0 / 255, alpha: 1)
    case .grok: return .labelColor
    }
}

private func meterSecondaryLabelColor(isDark: Bool) -> NSColor {
    isDark
        ? NSColor(srgbRed: 179.0 / 255, green: 191.0 / 255, blue: 208.0 / 255, alpha: 1)
        : .secondaryLabelColor
}

private func meterTertiaryLabelColor(isDark: Bool) -> NSColor {
    isDark
        ? NSColor(srgbRed: 132.0 / 255, green: 146.0 / 255, blue: 166.0 / 255, alpha: 1)
        : .tertiaryLabelColor
}

private func meterTrackColor(isDark: Bool) -> NSColor {
    isDark
        ? NSColor(srgbRed: 44.0 / 255, green: 54.0 / 255, blue: 72.0 / 255, alpha: 1)
        : .quaternaryLabelColor
}
