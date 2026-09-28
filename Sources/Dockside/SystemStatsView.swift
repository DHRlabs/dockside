import AppKit

@MainActor
final class SystemStatsView: NSView {
    private var reading: SystemStatsReading?
    private var theme: DocksideTheme = .glass
    private var compact = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("System statistics")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func width(for height: CGFloat) -> CGFloat {
        width(for: height, compact: compact)
    }

    func width(for height: CGFloat, compact: Bool) -> CGFloat {
        if compact { return 100 }
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
        if compact {
            drawCompact(height: height, dark: dark, cpu: palette.accent, ram: palette.warm)
        } else {
            drawExpanded(height: height, dark: dark, cpu: palette.accent, ram: palette.warm)
        }
    }

    private func drawExpanded(height: CGFloat, dark: Bool, cpu: NSColor, ram: NSColor) {
        let inset: CGFloat = 4
        let gap: CGFloat = 4
        let temperatureWidth = min(50, max(42, bounds.width * 0.25))
        let gaugeWidth = max(1, (bounds.width - inset * 2 - temperatureWidth - gap * 2) / 2)
        let cpuX = bounds.minX + inset
        let ramX = cpuX + gaugeWidth + gap
        let temperatureX = bounds.maxX - inset - temperatureWidth
        let labelFont = smallFont(max(7.5, min(8.5, height * 0.16)))
        let labelHeight = fontHeight(labelFont)
        let labelY = height * 0.57
        let meterY = height * 0.43
        drawGaugeRow("CPU", reading?.cpuPercent, x: cpuX, width: gaugeWidth, labelY: labelY,
                     meterY: meterY, labelHeight: labelHeight, font: labelFont, accent: cpu, dark: dark)
        drawGaugeRow("RAM", reading?.memoryPercent, x: ramX, width: gaugeWidth, labelY: labelY,
                     meterY: meterY, labelHeight: labelHeight, font: labelFont, accent: ram, dark: dark)
        let temperatureLabelY = labelY
        let temperatureY: CGFloat = 3
        let temperatureHeight = max(1, temperatureLabelY - temperatureY - 3)
        drawLabel("AVG CPU", in: NSRect(x: temperatureX, y: temperatureLabelY,
                                        width: temperatureWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
        drawTemperature(reading?.temperatureCelsius,
                        in: NSRect(x: temperatureX, y: temperatureY,
                                   width: temperatureWidth, height: temperatureHeight), dark: dark)
    }

    private func drawGaugeRow(_ name: String, _ value: Double?, x: CGFloat, width: CGFloat,
                              labelY: CGFloat, meterY: CGFloat, labelHeight: CGFloat,
                              font: NSFont, accent: NSColor, dark: Bool) {
        let reading = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        drawLabel("\(name) \(reading.map { "\($0)%" } ?? "--")",
                  in: NSRect(x: x, y: labelY, width: width, height: labelHeight),
                  font: font, color: reading == nil ? tertiaryColor(dark: dark) : secondaryColor(dark: dark))
        drawHorizontalMeter(value, x: x, y: meterY, width: width, accent: accent, dark: dark)
    }

    private func drawHorizontalMeter(_ value: Double?, x: CGFloat, y: CGFloat, width: CGFloat,
                                     accent: NSColor, dark: Bool) {
        let segmentWidth: CGFloat = 2
        let gap: CGFloat = 1
        let count = max(1, Int((width + gap) / (segmentWidth + gap)))
        let filled = filledCount(value, count: count)
        let used = CGFloat(count) * segmentWidth + CGFloat(count - 1) * gap
        let originX = x + max(0, (width - used) / 2)
        for index in 0..<count {
            let segment = NSRect(x: originX + CGFloat(index) * (segmentWidth + gap), y: y,
                                 width: segmentWidth, height: 2)
            (index < filled ? accent : trackColor(dark: dark)).setFill()
            if theme == .pixel {
                segment.fill()
            } else {
                NSBezierPath(roundedRect: segment, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private func drawCompact(height: CGFloat, dark: Bool, cpu: NSColor, ram: NSColor) {
        let margin: CGFloat = 3
        let temperatureWidth: CGFloat = 42
        let gap: CGFloat = 4
        let temperatureX = bounds.maxX - margin - temperatureWidth
        let columnsEnd = temperatureX - gap
        let columnsWidth = max(1, columnsEnd - (bounds.minX + margin))
        let columnGap: CGFloat = 2
        let columnWidth = max(1, (columnsWidth - columnGap) / 2)
        let cpuX = bounds.minX + margin
        let ramX = cpuX + columnWidth + columnGap
        let labelFont = smallFont(max(6.5, min(7.5, height * 0.18)))
        let valueFont = smallFont(max(6.5, min(7.5, height * 0.18)), weight: .medium)
        let labelHeight = fontHeight(labelFont)
        let valueHeight = fontHeight(valueFont)
        let barBottom = labelHeight + 4
        let barTop = max(barBottom + 1, height - valueHeight - 3)
        drawVerticalGauge("CPU", reading?.cpuPercent, x: cpuX, width: columnWidth,
                          bottom: barBottom, top: barTop, labelFont: labelFont,
                          valueFont: valueFont, labelHeight: labelHeight, valueHeight: valueHeight,
                          accent: cpu, dark: dark)
        drawVerticalGauge("RAM", reading?.memoryPercent, x: ramX, width: columnWidth,
                          bottom: barBottom, top: barTop, labelFont: labelFont,
                          valueFont: valueFont, labelHeight: labelHeight, valueHeight: valueHeight,
                          accent: ram, dark: dark)
        drawLabel("AVG", in: NSRect(x: temperatureX, y: height - labelHeight - 1,
                                     width: temperatureWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
        drawTemperature(reading?.temperatureCelsius,
                        in: NSRect(x: temperatureX, y: height * 0.22,
                                   width: temperatureWidth, height: height * 0.48), dark: dark)
    }

    private func drawVerticalGauge(_ name: String, _ value: Double?, x: CGFloat, width: CGFloat,
                                   bottom: CGFloat, top: CGFloat, labelFont: NSFont, valueFont: NSFont,
                                   labelHeight: CGFloat, valueHeight: CGFloat, accent: NSColor, dark: Bool) {
        let reading = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        drawLabel(name, in: NSRect(x: x, y: 1, width: width, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
        drawLabel(reading.map { "\($0)%" } ?? "--",
                  in: NSRect(x: x, y: bounds.height - valueHeight - 1, width: width, height: valueHeight),
                  font: valueFont, color: reading == nil ? tertiaryColor(dark: dark) : secondaryColor(dark: dark),
                  alignment: .center)
        let barWidth: CGFloat = 2.5
        let barHeight = max(1, top - bottom)
        let barX = x + (width - barWidth) / 2
        let count = max(1, Int(ceil(barHeight / 3)))
        let filled = filledCount(value, count: count)
        for index in 0..<count {
            let segment = NSRect(x: barX, y: bottom + CGFloat(index) * 3,
                                 width: barWidth, height: min(2, max(0, top - (bottom + CGFloat(index) * 3))))
            (index < filled ? accent : trackColor(dark: dark)).setFill()
            if theme == .pixel {
                segment.fill()
            } else {
                NSBezierPath(roundedRect: segment, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private func filledCount(_ value: Double?, count: Int) -> Int {
        guard let value, value.isFinite else { return 0 }
        return Int((min(100, max(0, value)) / 100 * Double(count)).rounded(.down))
    }

    private func smallFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if theme == .pixel, let pixel = NSFont(name: "Menlo", size: size) { return pixel }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private func drawTemperature(_ value: Double?, in rect: NSRect, dark: Bool) {
        let degrees = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let digits = degrees.map { String($0) } ?? "--"
        let suffixFont = NSFont.monospacedDigitSystemFont(ofSize: max(6.5, min(8.5, rect.height * 0.18)), weight: .medium)
        let suffix = "°C"
        let suffixWidth = ceil((suffix as NSString).size(withAttributes: [.font: suffixFont]).width)
        let glyphGapRatio: CGFloat = 0.8
        let dotUnits = CGFloat(digits.count) * 6.4 + CGFloat(max(0, digits.count - 1)) * glyphGapRatio
        let dot = max(0.7, min(1.8, (rect.width - suffixWidth - 3) / dotUnits))
        let spacing = dot * 0.35
        let glyphWidth = dot * 5 + spacing * 4
        let glyphGap = dot * glyphGapRatio
        let totalWidth = CGFloat(digits.count) * glyphWidth + CGFloat(max(0, digits.count - 1)) * glyphGap + 3 + suffixWidth
        var x = rect.midX - totalWidth / 2
        let gridHeight = dot * 7 + spacing * 6
        let y = rect.midY - gridHeight / 2
        let color = degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark)
        for (index, character) in digits.enumerated() {
            for (row, bits) in (Self.dotGlyphs[character] ?? Self.dotGlyphs["-"] ?? []).enumerated() {
                for column in 0..<5 where bits & (1 << (4 - column)) != 0 {
                    let pixel = NSRect(x: x + CGFloat(column) * (dot + spacing),
                                       y: y + CGFloat(6 - row) * (dot + spacing), width: dot, height: dot)
                    color.setFill()
                    if theme == .pixel {
                        pixel.fill()
                    } else {
                        NSBezierPath(ovalIn: pixel).fill()
                    }
                }
            }
            x += glyphWidth
            if index < digits.count - 1 { x += glyphGap }
        }
        drawLabel(suffix, in: NSRect(x: x + 1, y: rect.midY - fontHeight(suffixFont) / 2,
                                      width: suffixWidth + 1, height: fontHeight(suffixFont)),
                  font: suffixFont, color: color)
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
