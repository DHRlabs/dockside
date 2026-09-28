import AppKit

@MainActor
final class BubblePanel: NSPanel {
    static let dockGap: CGFloat = 8
    // Measured on Lance's Mac: AX list top y 1372, Dock plate top y 1377, with 44-point icons.
    static let dockPlateVerticalCalibration: CGFloat = 5
    // Picked to match the corner curvature of the 58-point Tahoe Dock plate.
    static let dockPlateCornerRadius: CGFloat = 15
    fileprivate static let meterWidthRatio: CGFloat = 1.6
    fileprivate static let meterGapRatio: CGFloat = 0.25
    fileprivate static let horizontalInsetRatio: CGFloat = 0.28
    // Lance's dark-mode Dock plate calibration: black tint over regular glass.
    static let tintAlpha: CGFloat = 0.55
    // Measured black veil compensating for NSGlassEffectView's brighter black tint.
    static let darkGlassVeilAlpha: CGFloat = 0.70
    // A one-point inner rim, tuned against the Dock's lighter plate edge.
    static let glassRimAlpha: CGFloat = 0.22

    fileprivate static func meterLayout(height: CGFloat, available: CGFloat, count: Int)
        -> (inset: CGFloat, gap: CGFloat, meterWidth: CGFloat, width: CGFloat)? {
        guard count > 0 else { return nil }
        let inset = height * horizontalInsetRatio
        let gap = height * meterGapRatio
        let meterWidth = min(height * meterWidthRatio,
                             max(0, (available - 2 * inset - gap * CGFloat(count - 1)) / CGFloat(count)))
        guard meterWidth > 0 else { return nil }
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
        guard let layout = Self.meterLayout(height: height, available: available, count: count) else {
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
        let size = hoverCard.size(for: readings.count)
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
        guard let layout = BubblePanel.meterLayout(height: height, available: bounds.width, count: count) else {
            return
        }
        let inset = layout.inset
        let gap = layout.gap
        let meterWidth = layout.meterWidth
        let now = Date()
        let preferredSize = height * 0.21
        let titleSize = readings.map {
            fittedTitleSize($0.label, "100%", width: meterWidth, preferred: preferredSize)
        }.min() ?? preferredSize
        let labelFont = NSFont.systemFont(ofSize: titleSize, weight: .medium)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: titleSize, weight: .medium)
        let resetFont = NSFont.systemFont(ofSize: max(10, height * 0.17), weight: .regular, width: .condensed)
        let resetHeight = fontHeight(resetFont)
        let spacing = max(1, height * 0.035)
        let barHeight = min(6, height * 0.105)
        let fits = readings.map { reading in
            reading.resetLine(at: now).map { textSize($0, font: resetFont).width <= meterWidth } ?? false
        }
        let reserveLine3 = fits.contains(true)

        for (index, reading) in readings.enumerated() {
            let x = inset + CGFloat(index) * (meterWidth + gap)
            let percent = reading.percentageText(at: now)
            let percentWidth = textSize(percent, font: percentFont).width
            let labelRect = NSRect(x: x, y: 0,
                                   width: max(0, meterWidth - percentWidth - 3), height: fontHeight(labelFont))
            let percentRect = NSRect(x: x + meterWidth - percentWidth, y: 0,
                                     width: percentWidth, height: fontHeight(percentFont))
            let titleHeight = max(fontHeight(labelFont), fontHeight(percentFont))
            let blockHeight = titleHeight + spacing + barHeight + (reserveLine3 ? spacing + resetHeight : 0)
            let bottom = (height - blockHeight) / 2
            let barY = bottom + (reserveLine3 ? resetHeight + spacing : 0)

            if fits[index], let reset = reading.resetLine(at: now) {
                drawText(reset, in: NSRect(x: x, y: bottom, width: meterWidth, height: resetHeight),
                         font: resetFont, color: .secondaryLabelColor)
            }
            drawMeter(reading, in: NSRect(x: x, y: barY, width: meterWidth, height: barHeight),
                      at: now, isDark: isDarkAppearance)
            drawText(reading.label, in: labelRect.offsetBy(dx: 0, dy: barY + spacing + barHeight),
                     font: labelFont, color: .labelColor)
            drawText(percent, in: percentRect.offsetBy(dx: 0, dy: barY + spacing + barHeight),
                     font: percentFont, color: .labelColor, alignment: .right)
        }
    }

    private func fittedTitleSize(_ label: String, _ percent: String, width: CGFloat, preferred: CGFloat) -> CGFloat {
        var size = preferred
        while size > 6 {
            let labelFont = NSFont.systemFont(ofSize: size, weight: .medium)
            let percentFont = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            if textSize(label, font: labelFont).width + textSize(percent, font: percentFont).width + 3 <= width {
                break
            }
            size *= 0.9
        }
        return max(6, size)
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

    func size(for readingCount: Int) -> NSSize {
        NSSize(width: Self.width, height: 24 + Self.rowHeight * CGFloat(max(1, readingCount)))
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
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let now = Date()

        for (index, reading) in readings.enumerated() {
            let top = bounds.maxY - padding - CGFloat(index) * rowHeight
            let percent = reading.percentageText(at: now)
            let percentWidth = textSize(percent, font: percentFont).width
            let titleY = top - fontHeight(titleFont)
            drawText(reading.label,
                     in: NSRect(x: padding, y: titleY, width: max(0, bounds.width - padding * 2 - percentWidth - 4),
                                height: fontHeight(titleFont)),
                     font: titleFont, color: .labelColor)
            drawText(percent,
                     in: NSRect(x: bounds.maxX - padding - percentWidth, y: titleY,
                                width: percentWidth, height: fontHeight(percentFont)),
                     font: percentFont, color: .labelColor, alignment: .right)
            drawMeter(reading,
                      in: NSRect(x: padding, y: top - 23, width: bounds.width - padding * 2, height: 5),
                      at: now, isDark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
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
private func drawMeter(_ reading: UsageReading, in rect: NSRect, at now: Date, isDark: Bool) {
    guard rect.width > 0, rect.height > 0 else { return }
    let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    guard let share = reading.share(at: now) else {
        NSColor.gray.withAlphaComponent(0.55).setFill()
        track.fill()
        return
    }

    NSColor.labelColor.withAlphaComponent(0.12).setFill()
    track.fill()
    if share > 0 {
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * share, height: rect.height)
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        fillColor(for: reading.provider, isDark: isDark).setFill()
        fill.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    if let pace = reading.pace(at: now) {
        let tick = NSRect(x: rect.minX + rect.width * pace - 0.5, y: rect.minY - 2,
                          width: 1, height: rect.height + 4)
        NSColor.textBackgroundColor.setFill()
        NSRect(x: tick.minX - 1, y: rect.minY, width: 3, height: rect.height).fill()
        NSColor.labelColor.setFill()
        tick.fill()
    }
}

private func fillColor(for provider: UsageReading.Provider, isDark: Bool) -> NSColor {
    switch provider {
    case .claude: return NSColor(srgbRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
    case .codex:
        return isDark
            ? NSColor(srgbRed: 185 / 255, green: 166 / 255, blue: 1, alpha: 1)
            : NSColor(srgbRed: 146 / 255, green: 123 / 255, blue: 225 / 255, alpha: 1)
    case .grok: return .labelColor
    }
}
