import AppKit

@MainActor
final class BubblePanel: NSPanel {
    private static let dockGap: CGFloat = 8
    fileprivate static let barWidthRatio: CGFloat = 0.095
    fileprivate static let barGapRatio: CGFloat = 0.09
    fileprivate static let horizontalInsetRatio: CGFloat = 0.12

    private let bubbleView = BubbleView(frame: .zero)
    private var dockFrame: CGRect?
    private var readings: [UsageReading] = []

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
        orderOut(nil)
    }

    func update(_ readings: [UsageReading]) {
        self.readings = readings
        bubbleView.update(readings)
        if let dockFrame { place(leftOf: dockFrame) }
    }

    func place(leftOf dockFrame: CGRect?) {
        guard let dockFrame else {
            self.dockFrame = nil
            orderOut(nil)
            return
        }
        self.dockFrame = dockFrame
        let height = dockFrame.height
        let width = height * (Self.horizontalInsetRatio * 2
            + Self.barWidthRatio * CGFloat(readings.count)
            + Self.barGapRatio * CGFloat(max(0, readings.count - 1)))
        let frame = NSRect(x: dockFrame.minX - Self.dockGap - width,
                           y: dockFrame.minY, width: width, height: height)
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .rightMouseDown, let contentView else { return super.sendEvent(event) }
        let menu = NSMenu()
        let quit = menu.addItem(withTitle: "Quit Dockside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    override func mouseDown(with event: NSEvent) {}
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class BubbleView: NSView {
    private let bars = UsageBarsView(frame: .zero)
    private let backdrop: NSView

    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frameRect)
            glass.style = .regular
            glass.tintColor = NSColor(calibratedWhite: 0, alpha: 0.28)
            glass.contentView = bars
            backdrop = glass
        } else {
            let effect = NSVisualEffectView(frame: frameRect)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.appearance = NSAppearance(named: .vibrantDark)
            effect.wantsLayer = true
            effect.layer?.masksToBounds = true
            effect.addSubview(bars)
            backdrop = effect
        }
        super.init(frame: frameRect)
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        let radius = bounds.height * 0.3
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            backdrop.layer?.cornerRadius = radius
        }
        bars.frame = backdrop.bounds
    }

    func update(_ readings: [UsageReading]) {
        bars.readings = readings
        bars.toolTip = readings.map(\.tooltipLine).joined(separator: "\n")
        bars.needsDisplay = true
    }
}

@MainActor
private final class UsageBarsView: NSView {
    var readings: [UsageReading] = []

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        guard height > 0, !readings.isEmpty else { return }
        let inset = height * BubblePanel.horizontalInsetRatio
        let barWidth = height * BubblePanel.barWidthRatio
        let gap = height * BubblePanel.barGapRatio
        let barHeight = height * 0.64
        let bottom = (height - barHeight) / 2
        let paceLineWidth = max(1, height * 0.016)

        for (index, reading) in readings.enumerated() {
            let rect = NSRect(x: inset + CGFloat(index) * (barWidth + gap), y: bottom,
                              width: barWidth, height: barHeight)
            let track = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            guard let share = reading.share() else {
                NSColor(calibratedWhite: 0.62, alpha: 0.45).setFill()
                track.fill()
                continue
            }

            NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
            track.fill()
            if share > 0 {
                let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * share)
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                fillColor(for: reading.provider, share: share).setFill()
                fill.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            if let pace = reading.pace() {
                let y = rect.minY + rect.height * pace
                let line = NSBezierPath()
                line.lineWidth = paceLineWidth
                line.move(to: NSPoint(x: rect.minX, y: y))
                line.line(to: NSPoint(x: rect.maxX, y: y))
                NSColor(calibratedWhite: 1, alpha: 0.95).setStroke()
                line.stroke()
            }
        }
    }

    private func fillColor(for provider: UsageReading.Provider, share: Double) -> NSColor {
        if 1 - share <= 0.1 { return NSColor(calibratedRed: 1, green: 95 / 255, blue: 86 / 255, alpha: 1) }
        switch provider {
        case .claude: return NSColor(calibratedRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
        case .codex: return NSColor(calibratedRed: 45 / 255, green: 212 / 255, blue: 191 / 255, alpha: 1)
        case .grok: return NSColor(calibratedRed: 201 / 255, green: 212 / 255, blue: 228 / 255, alpha: 1)
        }
    }
}
