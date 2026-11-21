import AppKit

@MainActor
final class SystemStatsView: NSView {
    private var reading: SystemStatsReading?
    private var theme: DocksideTheme = .glass
    private var compact = false
    private var cometTimer: Timer?
    private var lastCometFrame: TimeInterval?
    // Each pinned meter, keyed by its label: when it became pinned and how far its comet has swept.
    private var overloads: [String: (pinnedSince: TimeInterval, phase: Double)] = [:]
    // Swap in use over installed RAM, capped at 1; nil while nothing is swapped out.
    private var swapHeat: Double?
    private var swapPhase = 0.0
    private let hoverPanel = MeterHoverPanel()
    private var hoveredMeter: String?
    private var hoverTimer: Timer?

    // A meter counts as pinned only while it shows 100% (98 or 99% is not pinned).
    private static let pinnedPercent = 99.5
    // The comet starts only after a meter has stayed pinned this long, so a brief touch does nothing.
    private static let engageAfter = 15.0
    // Seconds of comet before it reaches full red and full speed (3 minutes).
    private static let fullHeatAfter = 180.0
    // A sweep cycle starts slow and shortens as the meter stays pinned. Each sweep takes the first
    // part of its cycle; the rest is a short pause before the next one.
    private static let coolCycle = 2.0
    private static let hotCycle = 0.7
    private static let cometSweepShare = 0.7
    // How many dashes the fading tail covers behind the bright head.
    private static let cometTrail = 3.5
    // The whole arc heats from its own color through yellow and orange to red.
    private static let heatColors = [
        NSColor(srgbRed: 1, green: 0.86, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 1),
        NSColor(srgbRed: 1, green: 0.2, blue: 0.15, alpha: 1)
    ]
    // How far toward white the light riding the arc is, so it reads as a hot spot on any arc color.
    private static let lightWhiteness: CGFloat = 0.7
    // RAM never reads much past 85% (macOS compresses and swaps instead of giving up its file cache), so the
    // RAM arc past this point is the swap zone. While memory is swapped out it lights up, colored by how
    // much: yellow with a little swap, through orange, to red once swap equals the installed RAM.
    private static let swapZoneStart = 0.85
    private static let swapGradient = NSGradient(colors: heatColors)
    // A steady glow on the swap zone, so it reads as lit even when its color is close to RAM's own orange.
    private static let swapGlow: CGFloat = 0.6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("CPU, GPU, RAM, and average CPU temperature")
        updateAccessibilityValue()
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func width(for height: CGFloat) -> CGFloat {
        width(for: height, compact: compact)
    }

    func width(for height: CGFloat, compact: Bool) -> CGFloat {
        guard height > 0 else { return 0 }
        switch (theme, compact) {
        case (.glass, false), (.ticks, false): return height * 4.59
        case (.glass, true), (.ticks, true): return height * 3.94
        case (.pixel, false): return height * 5.19
        case (.pixel, true): return height * 4.30
        }
    }

    func update(_ reading: SystemStatsReading) {
        self.reading = reading
        let now = ProcessInfo.processInfo.systemUptime
        let installed = Double(ProcessInfo.processInfo.physicalMemory)
        swapHeat = reading.swapUsedBytes.flatMap { $0 > 0 && installed > 0 ? min(1, Double($0) / installed) : nil }
        for (label, pinned) in [("CPU", Self.isPinned(reading.cpuPercent)), ("GPU", Self.isPinned(reading.gpuPercent))] {
            if !pinned {
                overloads[label] = nil
            } else if overloads[label] == nil {
                overloads[label] = (pinnedSince: now, phase: 0)
            }
        }
        updateAccessibilityValue()
        updateCometTimer()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCometTimer()
    }

    private static func isPinned(_ value: Double?) -> Bool {
        guard let value, value.isFinite else { return false }
        return value >= pinnedPercent
    }

    // How hot a meter's comet runs, 0 when it first starts to 1 at full red and speed; nil while the
    // meter is not pinned or has not stayed pinned long enough.
    private func heat(_ label: String, now: TimeInterval) -> Double? {
        guard let overload = overloads[label] else { return nil }
        let pinnedFor = now - overload.pinnedSince
        guard pinnedFor >= Self.engageAfter else { return nil }
        return min(1, (pinnedFor - Self.engageAfter) / Self.fullHeatAfter)
    }

    // Ticks about 30 times a second only while a meter is pinned or memory is swapped out, and the view
    // is in a window.
    private func updateCometTimer() {
        if !overloads.isEmpty || swapHeat != nil, window != nil {
            guard cometTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advanceComets() }
            }
            RunLoop.main.add(timer, forMode: .common)
            cometTimer = timer
        } else {
            cometTimer?.invalidate()
            cometTimer = nil
            lastCometFrame = nil
        }
    }

    // Moves each running comet along by the time since the last tick, faster as it heats up.
    private func advanceComets() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastCometFrame.map { min(0.1, now - $0) } ?? 0
        lastCometFrame = now
        var running = false
        for (label, overload) in overloads {
            guard let heat = heat(label, now: now) else { continue }
            running = true
            let cycle = Self.coolCycle + (Self.hotCycle - Self.coolCycle) * heat
            overloads[label]?.phase = (overload.phase + elapsed / cycle).truncatingRemainder(dividingBy: 1)
        }
        if swapHeat != nil {
            running = true
            swapPhase = (swapPhase + elapsed / Self.coolCycle).truncatingRemainder(dividingBy: 1)
        }
        if running, window?.isVisible == true { needsDisplay = true }
    }

    // A running comet on a meter: the color the whole arc takes, the color of the light riding it, and
    // where the light's head sits in the meter's own units (nil between sweeps). nil when no comet runs.
    // `lead` lets the head fade in just before the first dash.
    private func comet(_ label: String, accent: NSColor, span: Double, trail: Double,
                       lead: Double) -> (arc: NSColor, light: NSColor, head: Double?)? {
        guard let heat = heat(label, now: ProcessInfo.processInfo.systemUptime),
              let phase = overloads[label]?.phase else { return nil }
        let arc = NSGradient(colors: [accent] + Self.heatColors)?.interpolatedColor(atLocation: CGFloat(heat)) ?? accent
        let light = arc.blended(withFraction: Self.lightWhiteness, of: .white) ?? .white
        let head = phase < Self.cometSweepShare
            ? -lead + phase / Self.cometSweepShare * (span + trail + lead) : nil
        return (arc, light, head)
    }

    // The lit swap zone on the RAM arc: its color, its light, and where the light's head sits in zone units
    // from 0 to `span` (nil between sweeps). nil while nothing is swapped out.
    private func swapZone(span: Double, trail: Double, lead: Double) -> (color: NSColor, light: NSColor, head: Double?)? {
        guard let swapHeat else { return nil }
        let color = Self.swapGradient?.interpolatedColor(atLocation: CGFloat(swapHeat)) ?? Self.heatColors[0]
        let light = color.blended(withFraction: Self.lightWhiteness, of: .white) ?? .white
        let head = swapPhase < Self.cometSweepShare
            ? -lead + swapPhase / Self.cometSweepShare * (span + trail + lead) : nil
        return (color, light, head)
    }

    // The first dash of a meter that sits past the start of the swap zone.
    private static func firstSwapDash(count: Int) -> Int {
        (0..<count).first { Double($0) / Double(count - 1) > swapZoneStart } ?? count
    }

    // Full brightness at the head, over half a dash ahead of it, and a tail that drops off quickly
    // behind it and then lingers faintly, like a comet.
    private func cometIntensity(index: Int, head: Double?) -> CGFloat {
        guard let head else { return 0 }
        let behind = head - Double(index)
        if behind < 0 { return CGFloat(max(0, 1 + behind * 2)) }
        return CGFloat(pow(max(0, 1 - behind / Self.cometTrail), 1.6))
    }

    private func cometBlend(_ base: NSColor, toward color: NSColor?, intensity: CGFloat) -> NSColor {
        guard let color, intensity > 0 else { return base }
        return base.blended(withFraction: intensity, of: color) ?? base
    }

    private func withCometGlow(_ intensity: CGFloat, color: NSColor, draw: () -> Void) {
        guard intensity > 0 else { draw(); return }
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent(0.85 * intensity)
        glow.shadowBlurRadius = 4 * intensity
        glow.shadowOffset = .zero
        glow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    func setTheme(_ theme: DocksideTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        needsDisplay = true
    }

    func setCompact(_ compact: Bool) {
        guard self.compact != compact else { return }
        self.compact = compact
        needsDisplay = true
    }

    // Where the CPU, GPU and RAM meters sit in the current theme and size: their shared width and centers.
    private func usageMeterLayout(height: CGFloat) -> (width: CGFloat, cpu: CGFloat, gpu: CGFloat, ram: CGFloat) {
        if theme == .pixel {
            return (height * (compact ? 0.80 : 0.96),
                    bounds.minX + height * (compact ? 0.58 : 0.69),
                    bounds.minX + height * (compact ? 1.60 : 1.92),
                    bounds.minX + height * (compact ? 2.62 : 3.15))
        }
        return (compact ? min(height * 0.84, 46) : height * 0.92,
                bounds.minX + height * (compact ? 0.68 : 0.70),
                bounds.minX + height * (compact ? 1.62 : 1.80),
                bounds.minX + height * (compact ? 2.56 : 2.90))
    }

    // Hovering a CPU, GPU or RAM meter shows a small card above it naming the app using the most of it.
    override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hover(at: nil) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { hover(at: nil) }
    }

    private func meter(at point: NSPoint) -> (label: String, centerX: CGFloat)? {
        let meters = usageMeterLayout(height: bounds.height)
        return [("CPU", meters.cpu), ("GPU", meters.gpu), ("RAM", meters.ram)]
            .first { abs($0.1 - point.x) <= meters.width / 2 }
            .map { (label: $0.0, centerX: $0.1) }
    }

    private func hover(at point: NSPoint?) {
        let target = point.flatMap(meter(at:))
        guard target?.label != hoveredMeter else { return }
        hoveredMeter = target?.label
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverPanel.orderOut(nil)
        guard let target else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showHover(target.label, centerX: target.centerX) }
        }
    }

    // The process list takes a few tenths of a second, so it is read off the main thread; the card shows
    // only if the same meter is still hovered when the answer comes back.
    private func showHover(_ label: String, centerX: CGFloat) {
        guard hoveredMeter == label, window?.isVisible == true else { return }
        let gpu = reading?.topGPUApp
        let swap = reading?.swapUsedBytes
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Self.topAppText(label, gpu: gpu, swap: swap)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.hoveredMeter == label, let window = self.window, window.isVisible else { return }
                let anchor = window.convertPoint(toScreen: self.convert(NSPoint(x: centerX, y: self.bounds.maxY), to: nil))
                self.hoverPanel.show(text, centeredAbove: anchor)
            }
        }
    }

    nonisolated static func topAppText(_ label: String, gpu: (name: String, percent: Double)?, swap: UInt64?) -> String {
        switch label {
        case "GPU":
            guard let top = gpu else { return "Top GPU: none right now" }
            return "Top GPU: \(top.name) (\(Int(top.percent.rounded()))%)"
        case "CPU":
            guard let top = TopProcesses.read().cpu else { return "Top CPU: unavailable" }
            return "Top CPU: \(top.name) (\(Int(top.percent.rounded()))%)"
        default:
            let swapText = swap.map {
                " · Swap \(ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory))"
            } ?? ""
            guard let top = TopProcesses.read().memory else { return "Top RAM: unavailable\(swapText)" }
            let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: top.bytes), countStyle: .memory)
            return "Top RAM: \(top.name) (\(size))\(swapText)"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        guard height > 0, bounds.width > 0 else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = pixelPalette()
        if theme == .pixel {
            drawPixelMeters(height: height, palette: palette, dark: dark)
        } else {
            drawGlassMeters(height: height, palette: palette, dark: dark)
        }
    }

    private func drawGlassMeters(height: CGFloat, palette: (accent: NSColor, warm: NSColor), dark: Bool) {
        let meters = usageMeterLayout(height: height)
        let archWidth = meters.width
        let cpuCenterX = meters.cpu
        let gpuCenterX = meters.gpu
        let ramCenterX = meters.ram
        let temperatureCenterX = bounds.minX + height * (compact ? 3.45 : 3.97)
        let temperatureWidth = height * (compact ? 0.72 : 0.84)

        drawGlassUsageSemicircle(reading?.cpuPercent, label: "CPU", centerX: cpuCenterX,
                                 outerWidth: archWidth, height: height, compact: compact,
                                 accent: palette.accent, dark: dark)
        drawGlassUsageSemicircle(reading?.gpuPercent, label: "GPU", centerX: gpuCenterX,
                                 outerWidth: archWidth, height: height, compact: compact,
                                 accent: palette.accent, dark: dark)
        drawGlassUsageSemicircle(reading?.memoryPercent, label: "RAM", centerX: ramCenterX,
                                 outerWidth: archWidth, height: height, compact: compact,
                                 accent: palette.warm, dark: dark)

        let temperatureTextHeight = height * 0.28
        drawGlassTemperature(reading?.temperatureCelsius,
                             in: NSRect(x: temperatureCenterX - temperatureWidth / 2,
                                        y: height * 0.64 - temperatureTextHeight / 2,
                                        width: temperatureWidth, height: temperatureTextHeight), dark: dark)
        drawGlassTemperatureBar(reading?.temperatureCelsius,
                                in: NSRect(x: temperatureCenterX - temperatureWidth / 2,
                                           y: height * 0.42 - max(3, height * 0.08) / 2,
                                           width: temperatureWidth, height: max(3, height * 0.08)), dark: dark)
        drawGlassLabel("TEMP", centerX: temperatureCenterX, centerY: height * 0.21,
                       width: temperatureWidth, size: glassLabelSize(height: height, compact: compact), dark: dark)
    }

    private func drawGlassUsageSemicircle(_ value: Double?, label: String, centerX: CGFloat,
                                          outerWidth: CGFloat, height: CGFloat, compact: Bool,
                                          accent: NSColor, dark: Bool) {
        let stroke = height * 0.075
        let radius = (outerWidth - stroke) / 2
        let baselineY = height * 0.40
        let center = NSPoint(x: centerX, y: baselineY)
        if theme == .ticks {
            let fraction = value.flatMap { $0.isFinite ? min(1, max(0, $0 / 100)) : nil } ?? 0
            let filled = Int(fraction * 13)
            let tickWidth = outerWidth * 0.044
            let tickRadius = (outerWidth - tickWidth) / 2
            let tickLength = outerWidth * 0.10
            let comet = comet(label, accent: accent, span: 13, trail: Self.cometTrail, lead: 0.5)
            let swapFirst = Self.firstSwapDash(count: 13)
            let swap = label == "RAM" ? swapZone(span: Double(13 - swapFirst), trail: Self.cometTrail, lead: 0.5) : nil
            for index in 0..<13 {
                let angle = Double.pi - Double.pi * Double(index) / 12
                let outer = NSPoint(x: center.x + CGFloat(cos(angle)) * tickRadius,
                                    y: center.y + CGFloat(sin(angle)) * tickRadius)
                let innerRadius = tickRadius - tickLength
                let inner = NSPoint(x: center.x + CGFloat(cos(angle)) * innerRadius,
                                    y: center.y + CGFloat(sin(angle)) * innerRadius)
                let tick = NSBezierPath()
                tick.lineWidth = tickWidth
                tick.lineCapStyle = .round
                tick.move(to: inner)
                tick.line(to: outer)
                let zone = index >= swapFirst ? swap : nil
                let intensity = zone.map { cometIntensity(index: index - swapFirst, head: $0.head) }
                    ?? cometIntensity(index: index, head: comet?.head)
                let base = zone?.color ?? (index < filled ? comet?.arc ?? accent : trackColor(dark: dark))
                let color = cometBlend(base, toward: zone?.light ?? comet?.light, intensity: intensity)
                color.setStroke()
                withCometGlow(zone == nil ? intensity : max(Self.swapGlow, intensity), color: color) { tick.stroke() }
            }
        } else if let value, value.isFinite {
            strokeGlassSemicircle(center: center, radius: radius, width: stroke,
                                  fraction: nil, color: trackColor(dark: dark))
            let fraction = min(1, max(0, value / 100))
            let comet = comet(label, accent: accent, span: 1, trail: 0.3, lead: 0.02)
            if fraction > 0 {
                strokeGlassSemicircle(center: center, radius: radius, width: stroke,
                                      fraction: fraction, color: comet?.arc ?? accent)
            }
            if let comet, let head = comet.head {
                strokeGlassComet(center: center, radius: radius, width: stroke,
                                 head: head, tail: 0.3, color: comet.light)
            }
            let zoneSpan = 1 - Self.swapZoneStart
            if label == "RAM", let zone = swapZone(span: zoneSpan, trail: 0.1, lead: 0.01) {
                withCometGlow(Self.swapGlow, color: zone.color) {
                    strokeGlassArc(center: center, radius: radius, width: stroke,
                                   from: Self.swapZoneStart, to: 1, color: zone.color)
                }
                if let head = zone.head {
                    strokeGlassComet(center: center, radius: radius, width: stroke, head: Self.swapZoneStart + head,
                                     tail: 0.1, color: zone.light, floor: Self.swapZoneStart)
                }
            }
        } else {
            strokeGlassSemicircle(center: center, radius: radius, width: stroke,
                                  fraction: nil, color: trackColor(dark: dark))
        }

        let number = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let text = number.map { "\($0)%" } ?? "--%"
        let baseSize = min(12, height * 0.207)
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .semibold)
        let measuredWidth = ceil(("100%" as NSString).size(withAttributes: [.font: baseFont]).width)
        let fittedSize = baseSize * min(1, outerWidth / max(1, measuredWidth))
        let font = NSFont.systemFont(ofSize: max(8, fittedSize), weight: .semibold)
        let textHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: centerX - outerWidth / 2,
                                   y: height * 0.455 - textHeight / 2,
                                   width: outerWidth, height: textHeight),
                  font: font, color: number == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)

        drawGlassLabel(label, centerX: centerX, centerY: height * 0.21,
                       width: outerWidth, size: glassLabelSize(height: height, compact: compact), dark: dark)
    }

    private func drawGlassTemperature(_ value: Double?, in rect: NSRect, dark: Bool) {
        let degrees = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let text = degrees.map { "\($0)°C" } ?? "--°C"
        let baseSize = min(12, rect.height * 0.75)
        let baseFont = NSFont.systemFont(ofSize: baseSize, weight: .semibold)
        let measuredWidth = ceil(("100°C" as NSString).size(withAttributes: [.font: baseFont]).width)
        let size = baseSize * min(1, rect.width / max(1, measuredWidth))
        let font = NSFont.systemFont(ofSize: max(7.5, size), weight: .semibold)
        let textHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: rect.minX, y: rect.midY - textHeight / 2,
                                   width: rect.width, height: textHeight),
                  font: font, color: degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)
    }

    private func drawGlassTemperatureBar(_ value: Double?, in rect: NSRect, dark: Bool) {
        trackColor(dark: dark).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        guard let value, value.isFinite else { return }
        let fraction = CGFloat(min(1, max(0, value / SystemStatsTemperature.fullScale)))
        guard fraction > 0 else { return }
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
        temperatureColor(value).setFill()
        NSBezierPath(roundedRect: fill, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    private func temperatureColor(_ value: Double) -> NSColor {
        let fraction = CGFloat(min(1, max(0, value / SystemStatsTemperature.fullScale)))
        return NSGradient(colors: [.systemGreen, .systemYellow, .systemRed])?
            .interpolatedColor(atLocation: fraction) ?? .systemGreen
    }

    private func drawGlassLabel(_ text: String, centerX: CGFloat, centerY: CGFloat,
                                width: CGFloat, size: CGFloat, dark: Bool) {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let labelHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: centerX - width / 2, y: centerY - labelHeight / 2,
                                   width: width, height: labelHeight),
                  font: font, color: primaryColor(dark: dark), alignment: .center)
    }

    private func glassLabelSize(height: CGFloat, compact: Bool) -> CGFloat {
        min(compact ? 10 : 11, max(8.5, height * (compact ? 0.172 : 0.19)))
    }

    private func strokeGlassSemicircle(center: NSPoint, radius: CGFloat, width: CGFloat,
                                       fraction: Double?, color: NSColor) {
        let path = NSBezierPath()
        let endAngle: CGFloat
        if let fraction { endAngle = 180 - CGFloat(180 * fraction) }
        else { endAngle = 0 }
        path.move(to: NSPoint(x: center.x - radius, y: center.y))
        path.appendArc(withCenter: center, radius: radius, startAngle: 180,
                       endAngle: endAngle, clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func strokeGlassArc(center: NSPoint, radius: CGFloat, width: CGFloat, from: Double, to: Double,
                                color: NSColor) {
        let startAngle = 180 - CGFloat(180 * from)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + radius * cos(startAngle * .pi / 180),
                              y: center.y + radius * sin(startAngle * .pi / 180)))
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle,
                       endAngle: 180 - CGFloat(180 * to), clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    // A short heat-colored streak riding the arc, brightest at the head and fading back along its tail,
    // never drawn below `floor`.
    private func strokeGlassComet(center: NSPoint, radius: CGFloat, width: CGFloat, head: Double, tail: Double,
                                  color: NSColor, floor: Double = 0) {
        let slices = 8
        for slice in 0..<slices {
            let from = max(floor, head - tail * Double(slices - slice) / Double(slices))
            let to = min(1, head - tail * Double(slices - slice - 1) / Double(slices))
            guard to > from else { continue }
            let intensity = CGFloat(slice + 1) / CGFloat(slices)
            let color = color.withAlphaComponent(intensity)
            let startAngle = 180 - CGFloat(180 * from)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center.x + radius * cos(startAngle * .pi / 180),
                                  y: center.y + radius * sin(startAngle * .pi / 180)))
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle,
                           endAngle: 180 - CGFloat(180 * to), clockwise: true)
            path.lineWidth = width
            path.lineCapStyle = slice == slices - 1 ? .round : .butt
            color.setStroke()
            withCometGlow(intensity, color: color) { path.stroke() }
        }
    }

    private func drawPixelMeters(height: CGFloat, palette: (accent: NSColor, warm: NSColor), dark: Bool) {
        let meters = usageMeterLayout(height: height)
        let archWidth = meters.width
        let cpuCenterX = meters.cpu
        let gpuCenterX = meters.gpu
        let ramCenterX = meters.ram
        let temperatureCenterX = bounds.minX + bounds.width * 0.878
        drawPixelUsageArch(reading?.cpuPercent, label: "CPU", centerX: cpuCenterX,
                           width: archWidth, height: height, accent: palette.accent, dark: dark)
        drawPixelUsageArch(reading?.gpuPercent, label: "GPU", centerX: gpuCenterX,
                           width: archWidth, height: height, accent: palette.accent, dark: dark)
        drawPixelUsageArch(reading?.memoryPercent, label: "RAM", centerX: ramCenterX,
                           width: archWidth, height: height, accent: palette.warm, dark: dark)
        let temperatureWidth = height * (compact ? 0.72 : 0.95)
        let temperatureHeight = height * (compact ? 0.29 : 0.38)
        let degrees = reading?.temperatureCelsius.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        drawPixelTemperature(degrees,
                             in: NSRect(x: temperatureCenterX - temperatureWidth / 2,
                                        y: height * (0.5 - (compact ? 0.145 : 0.19)),
                                        width: temperatureWidth, height: temperatureHeight), dark: dark)
    }

    private func drawPixelUsageArch(_ value: Double?, label: String, centerX: CGFloat,
                                    width: CGFloat, height: CGFloat, accent: NSColor, dark: Bool) {
        let labelFont = meterFont(size: max(5, min(10, height * 0.10)), weight: .medium)
        let labelHeight = fontHeight(labelFont)
        let baseline = NSPoint(x: centerX, y: height * 0.39)
        let side = max(2.2, min(4.5, height * (compact ? 0.064 : 0.069)))
        let fraction = value.flatMap { $0.isFinite ? min(1, max(0, $0 / 100)) : nil } ?? 0
        drawPixelArch(baseline: baseline, radius: (width - side) / 2, side: side,
                      fraction: fraction, label: label, color: accent, dark: dark)

        let number = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let text = number.map { "\($0)%" } ?? "--%"
        let textWidth = width * 0.78
        let baseSize = min(12, height * 0.14)
        let baseFont = meterFont(size: baseSize, weight: .semibold)
        let measuredWidth = ceil(("100%" as NSString).size(withAttributes: [.font: baseFont]).width)
        let fittedSize = baseSize * min(1, textWidth / max(1, measuredWidth))
        let valueFont = meterFont(size: max(6, fittedSize), weight: .semibold)
        let valueHeight = fontHeight(valueFont)
        drawLabel(text, in: NSRect(x: centerX - textWidth / 2, y: height * 0.44 - valueHeight / 2,
                                   width: textWidth, height: valueHeight),
                  font: valueFont, color: number == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)
        drawLabel(label, in: NSRect(x: centerX - width / 2, y: height * 0.17,
                                   width: width, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
    }

    private func drawPixelArch(baseline: NSPoint, radius: CGFloat, side: CGFloat,
                               fraction: Double, label: String, color: NSColor, dark: Bool) {
        let gap: CGFloat = 0.7
        let count = max(8, Int(ceil(Double.pi * Double(radius) / Double(side + gap))))
        let filled = Int((fraction * Double(count)).rounded(.down))
        let comet = comet(label, accent: color, span: Double(count), trail: Self.cometTrail, lead: 0.5)
        let swapFirst = Self.firstSwapDash(count: count)
        let swap = label == "RAM" ? swapZone(span: Double(count - swapFirst), trail: Self.cometTrail, lead: 0.5) : nil
        for index in 0..<count {
            let zone = index >= swapFirst ? swap : nil
            let intensity = zone.map { cometIntensity(index: index - swapFirst, head: $0.head) }
                ?? cometIntensity(index: index, head: comet?.head)
            let angle = Double.pi - Double.pi * Double(index) / Double(count - 1)
            for row in 0..<2 {
                let rowRadius = radius - CGFloat(row) * (side + gap)
                let point = NSPoint(x: baseline.x + CGFloat(cos(angle)) * rowRadius,
                                    y: baseline.y + CGFloat(sin(angle)) * rowRadius)
                let block = NSRect(x: point.x - side / 2, y: point.y - side / 2,
                                   width: side, height: side)
                cometBlend(zone?.color ?? (index < filled ? comet?.arc ?? color : trackColor(dark: dark)),
                           toward: zone?.light ?? comet?.light, intensity: intensity).setFill()
                block.fill()
            }
        }
    }

    private func drawPixelTemperature(_ degrees: Int?, in rect: NSRect, dark: Bool) {
        let digits = degrees.map { String($0) } ?? "--"
        let suffixFont = NSFont.monospacedDigitSystemFont(ofSize: max(5, rect.height * 0.36), weight: .medium)
        let suffix = "°C"
        let suffixWidth = ceil((suffix as NSString).size(withAttributes: [.font: suffixFont]).width)
        let gapRatio: CGFloat = 0.8
        let dotUnits = CGFloat(digits.count) * 6.4 + CGFloat(max(0, digits.count - 1)) * gapRatio
        let heightLimitedDot = rect.height / 9.1
        let widthLimitedDot = max(0.45, (rect.width - suffixWidth - 2) / dotUnits)
        let dot = max(0.45, min(heightLimitedDot, widthLimitedDot))
        let spacing = dot * 0.35
        let glyphWidth = dot * 6.4
        let glyphGap = dot * gapRatio
        let textWidth = CGFloat(digits.count) * glyphWidth + CGFloat(max(0, digits.count - 1)) * glyphGap + suffixWidth + 2
        var x = rect.midX - textWidth / 2
        let gridHeight = dot * 7 + spacing * 6
        let y = rect.midY - gridHeight / 2
        let color = degrees.map { temperatureColor(Double($0)) } ?? tertiaryColor(dark: dark)
        for (index, character) in digits.enumerated() {
            for (row, bits) in (Self.dotGlyphs[character] ?? Self.dotGlyphs["-"] ?? []).enumerated() {
                for column in 0..<5 where bits & (1 << (4 - column)) != 0 {
                    let pixel = NSRect(x: x + CGFloat(column) * (dot + spacing),
                                       y: y + CGFloat(6 - row) * (dot + spacing), width: dot, height: dot)
                    color.setFill()
                    pixel.fill()
                }
            }
            x += glyphWidth
            if index < digits.count - 1 { x += glyphGap }
        }
        drawLabel(suffix, in: NSRect(x: x + 1, y: rect.midY + gridHeight / 2 - fontHeight(suffixFont),
                                      width: suffixWidth, height: fontHeight(suffixFont)),
                  font: suffixFont, color: color)
    }

    private func meterFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if theme == .pixel, let pixel = NSFont(name: "Menlo-Bold", size: size) { return pixel }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private func drawLabel(_ text: String, in rect: NSRect, font: NSFont, color: NSColor,
                           alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect,
                                withAttributes: [.font: font, .foregroundColor: color,
                                                 .paragraphStyle: paragraph])
    }

    private func updateAccessibilityValue() {
        func formatted(_ value: Double?, suffix: String) -> String {
            guard let value, value.isFinite else { return "unavailable" }
            return "\(Int(value.rounded()))\(suffix)"
        }
        setAccessibilityValue("CPU \(formatted(reading?.cpuPercent, suffix: "%")), GPU \(formatted(reading?.gpuPercent, suffix: "%")), RAM \(formatted(reading?.memoryPercent, suffix: "%")), average CPU temperature \(formatted(reading?.temperatureCelsius, suffix: " degrees Celsius"))")
    }

    private static let dotGlyphs: [Character: [UInt8]] = [
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        "3": [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
        "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        "5": [0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110],
        "6": [0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110],
        "-": [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000]
    ]
}

// The small card above a hovered meter. It takes no mouse events, so it never gets in the strip's way.
@MainActor
private final class MeterHoverPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = NSView()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        content.addSubview(label)
        contentView = GlassBackdropView(contentView: content, cornerRadius: 10)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    func show(_ text: String, centeredAbove point: NSPoint) {
        label.stringValue = text
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 10, y: 6))
        let size = NSSize(width: ceil(label.frame.width) + 20, height: ceil(label.frame.height) + 12)
        var frame = NSRect(x: point.x - size.width / 2, y: point.y + 8, width: size.width, height: size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            frame.origin.x = min(max(frame.minX, screen.frame.minX), screen.frame.maxX - size.width)
        }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

private func fontHeight(_ font: NSFont) -> CGFloat {
    font.ascender - font.descender + font.leading
}

private func pixelPalette() -> (accent: NSColor, warm: NSColor) {
    (NSColor(srgbRed: 63.0 / 255, green: 191.0 / 255, blue: 178.0 / 255, alpha: 1),
     NSColor(srgbRed: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255, alpha: 1))
}

private func primaryColor(dark: Bool) -> NSColor {
    dark ? NSColor(srgbRed: 230.0 / 255, green: 236.0 / 255, blue: 245.0 / 255, alpha: 1) : .labelColor
}

private func secondaryColor(dark: Bool) -> NSColor {
    dark ? NSColor(srgbRed: 179.0 / 255, green: 191.0 / 255, blue: 208.0 / 255, alpha: 1) : .secondaryLabelColor
}

private func tertiaryColor(dark: Bool) -> NSColor {
    dark ? NSColor(srgbRed: 132.0 / 255, green: 146.0 / 255, blue: 166.0 / 255, alpha: 1) : .tertiaryLabelColor
}

private func trackColor(dark: Bool) -> NSColor {
    dark ? NSColor(srgbRed: 44.0 / 255, green: 54.0 / 255, blue: 72.0 / 255, alpha: 1) : .quaternaryLabelColor
}
