import AppKit

@MainActor
final class SystemStatsView: NSView {
    private var reading: SystemStatsReading?
    private var theme: DocksideTheme = .glass
    private var compact = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("CPU, RAM, and average CPU temperature")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func width(for height: CGFloat) -> CGFloat {
        width(for: height, compact: compact)
    }

    func width(for height: CGFloat, compact: Bool) -> CGFloat {
        if compact { return 150 }
        return max(150, min(200, height * 3.15))
    }

    func update(_ reading: SystemStatsReading) {
        self.reading = reading
        updateAccessibilityValue()
        needsDisplay = true
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

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        guard height > 0, bounds.width > 0 else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = pixelPalette()
        let inset: CGFloat = 4
        let temperatureWidth = compact ? CGFloat(50) : min(60, max(48, height * 0.92))
        let gap: CGFloat = compact ? 4 : 6
        let meterWidth = max(1, (bounds.width - inset * 2 - temperatureWidth - gap * 2) / 2)
        let cpuX = bounds.minX + inset
        let ramX = cpuX + meterWidth + gap
        let temperatureX = bounds.maxX - inset - temperatureWidth

        drawLevelMeter("CPU", value: reading?.cpuPercent, x: cpuX, width: meterWidth,
                       height: height, accent: palette.accent, dark: dark)
        drawLevelMeter("RAM", value: reading?.memoryPercent, x: ramX, width: meterWidth,
                       height: height, accent: palette.warm, dark: dark)
        drawTemperatureGauge(reading?.temperatureCelsius, x: temperatureX, width: temperatureWidth,
                             height: height, dark: dark)
    }

    private func drawLevelMeter(_ label: String, value: Double?, x: CGFloat, width: CGFloat,
                                height: CGFloat, accent: NSColor, dark: Bool) {
        let barWidth: CGFloat = theme == .pixel ? 9 : 8
        let barHeight = max(8, height - 8)
        let bar = NSRect(x: x + 2, y: (height - barHeight) / 2, width: barWidth, height: barHeight)
        let fraction = value.flatMap { $0.isFinite ? min(1, max(0, $0 / 100)) : nil } ?? 0
        if theme == .pixel {
            drawPixelMeter(value, in: bar, fraction: fraction, accent: accent, dark: dark)
        } else {
            drawGlassMeter(in: bar, fraction: fraction, accent: accent, dark: dark)
        }

        let valueSize = max(8, min(compact ? 10 : 12, height * 0.22))
        let labelSize = max(7, min(compact ? 8 : 9, height * 0.17))
        let labelFont = meterFont(size: labelSize, weight: .medium)
        let labelHeight = fontHeight(labelFont)
        let textX = bar.maxX + 4
        let textWidth = max(1, x + width - textX)
        let referenceFont = meterFont(size: valueSize, weight: .semibold)
        let referenceWidth = ceil(("100%" as NSString).size(withAttributes: [.font: referenceFont]).width)
        let fittedSize = valueSize * min(1, max(0, (textWidth - 1) / max(1, referenceWidth)))
        let valueFont = meterFont(size: max(6, fittedSize), weight: .semibold)
        let valueHeight = fontHeight(valueFont)
        let valueY = height / 2 - valueHeight - 1
        let labelY = height / 2 + 1
        let number = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        drawLabel(label, in: NSRect(x: textX, y: labelY, width: textWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark))
        drawLabel(number.map { "\($0)%" } ?? "--%",
                  in: NSRect(x: textX, y: valueY, width: textWidth, height: valueHeight),
                  font: valueFont, color: number == nil ? tertiaryColor(dark: dark) : accent)
    }

    private func drawGlassMeter(in rect: NSRect, fraction: Double, accent: NSColor, dark: Bool) {
        trackColor(dark: dark).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
        guard fraction > 0 else { return }
        let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width,
                          height: rect.height * CGFloat(fraction))
        accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: rect.width / 2, yRadius: rect.width / 2).fill()
    }

    private func drawPixelMeter(_ value: Double?, in rect: NSRect, fraction: Double,
                                accent: NSColor, dark: Bool) {
        let gap: CGFloat = 1
        let count = max(1, Int(ceil(rect.height / 5.5)))
        let segmentHeight = min(4.5, (rect.height - CGFloat(count - 1) * gap) / CGFloat(count))
        let filled = value.flatMap { $0.isFinite ? Int((fraction * Double(count)).rounded(.down)) : nil } ?? 0
        for index in 0..<count {
            let segment = NSRect(x: rect.minX, y: rect.minY + CGFloat(index) * (segmentHeight + gap),
                                 width: rect.width, height: segmentHeight)
            (index < filled ? accent : trackColor(dark: dark)).setFill()
            segment.fill()
        }
    }

    private func drawTemperatureGauge(_ value: Double?, x: CGFloat, width: CGFloat,
                                     height: CGFloat, dark: Bool) {
        let diameter = min(width - 2, min(height - 4, compact ? 38 : 56))
        guard diameter > 16 else { return }
        let center = NSPoint(x: x + width / 2, y: height / 2)
        let thickness: CGFloat = theme == .pixel ? 5 : 4.5
        let radius = diameter / 2 - thickness / 2 - 0.5
        let fraction = value.flatMap { $0.isFinite ? min(1, max(0, $0 / 100)) : nil } ?? 0
        let color = primaryColor(dark: dark)
        if theme == .pixel {
            let archRadius = min(diameter * 0.36, height * 0.34)
            let baseline = NSPoint(x: center.x, y: height / 2 + 1)
            drawPixelArch(baseline: baseline, radius: archRadius, side: max(3.2, min(4.5, diameter * 0.12)),
                          fraction: fraction, color: color, dark: dark)
            let readoutCenter = baseline.y - archRadius * 0.8
            drawPixelTemperature(value.flatMap { $0.isFinite ? Int($0.rounded()) : nil },
                                 in: NSRect(x: x, y: readoutCenter - 7,
                                            width: width, height: 14), dark: dark)
        } else {
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
            ring.lineWidth = thickness
            trackColor(dark: dark).setStroke()
            ring.stroke()
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.move(to: NSPoint(x: center.x, y: center.y + radius))
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - CGFloat(360 * fraction), clockwise: true)
                arc.lineWidth = thickness
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            let innerDiameter = max(1, 2 * (radius - thickness / 2))
            let inner = NSRect(x: center.x - innerDiameter / 2, y: center.y - innerDiameter / 2,
                               width: innerDiameter, height: innerDiameter)
            drawTemperatureValue(value, in: inner, dark: dark)
        }
    }

    private func drawPixelArch(baseline: NSPoint, radius: CGFloat, side: CGFloat,
                               fraction: Double, color: NSColor, dark: Bool) {
        let gap: CGFloat = 0.7
        let count = max(8, Int(ceil(Double.pi * Double(radius) / Double(side + gap))))
        let filled = Int((fraction * Double(count)).rounded(.down))
        for index in 0..<count {
            let angle = Double.pi - Double.pi * Double(index) / Double(count - 1)
            for row in 0..<2 {
                let rowRadius = radius - CGFloat(row) * (side + gap)
                let point = NSPoint(x: baseline.x + CGFloat(cos(angle)) * rowRadius,
                                    y: baseline.y + CGFloat(sin(angle)) * rowRadius)
                let block = NSRect(x: point.x - side / 2, y: point.y - side / 2,
                                   width: side, height: side)
                (index < filled ? color : trackColor(dark: dark)).setFill()
                block.fill()
            }
        }
    }

    private func drawTemperatureValue(_ value: Double?, in rect: NSRect, dark: Bool) {
        let degrees = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        if theme == .pixel {
            drawPixelTemperature(degrees, in: rect, dark: dark)
            return
        }
        let text = degrees.map { "\($0)°C" } ?? "--°C"
        let baseSize = max(7, min(11, rect.height * 0.38))
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .semibold)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: baseFont]).width)
        let size = baseSize * min(1, rect.width / max(1, measuredWidth))
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(6, size), weight: .semibold)
        let color = degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark)
        let lineHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: rect.minX, y: rect.midY - lineHeight / 2,
                                   width: rect.width, height: lineHeight),
                  font: font, color: color, alignment: .center)
    }

    private func drawPixelTemperature(_ degrees: Int?, in rect: NSRect, dark: Bool) {
        let digits = degrees.map { String($0) } ?? "--"
        let suffixFont = NSFont.monospacedDigitSystemFont(ofSize: max(5, min(6.5, rect.height * 0.28)), weight: .medium)
        let suffix = "°C"
        let suffixWidth = ceil((suffix as NSString).size(withAttributes: [.font: suffixFont]).width)
        let gapRatio: CGFloat = 0.8
        let dotUnits = CGFloat(digits.count) * 6.4 + CGFloat(max(0, digits.count - 1)) * gapRatio
        let dot = max(0.45, min(1.25, (rect.width - suffixWidth - 2) / dotUnits))
        let spacing = dot * 0.35
        let glyphWidth = dot * 6.4
        let glyphGap = dot * gapRatio
        let textWidth = CGFloat(digits.count) * glyphWidth + CGFloat(max(0, digits.count - 1)) * glyphGap + suffixWidth + 2
        var x = rect.midX - textWidth / 2
        let gridHeight = dot * 7 + spacing * 6
        let y = rect.midY - gridHeight / 2
        let color = degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark)
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
        drawLabel(suffix, in: NSRect(x: x + 1, y: rect.midY - fontHeight(suffixFont) / 2,
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
        setAccessibilityValue("CPU \(formatted(reading?.cpuPercent, suffix: "%")), RAM \(formatted(reading?.memoryPercent, suffix: "%")), average CPU temperature \(formatted(reading?.temperatureCelsius, suffix: " degrees Celsius"))")
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
