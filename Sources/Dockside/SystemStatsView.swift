import AppKit

@MainActor
final class SystemStatsView: NSView {
    private var reading: SystemStatsReading?
    private var theme: DocksideTheme = .glass

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("System statistics")
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func width(for height: CGFloat) -> CGFloat {
        max(150, min(200, height * 3.15))
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

    override func draw(_ dirtyRect: NSRect) {
        let height = bounds.height
        guard height > 0, bounds.width > 0 else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inset: CGFloat = 4
        let gap: CGFloat = 3
        let temperatureWidth = min(56, max(42, bounds.width * 0.28))
        let gaugeWidth = max(1, (bounds.width - inset * 2 - temperatureWidth - gap * 2) / 2)
        let cpuX = bounds.minX + inset
        let ramX = cpuX + gaugeWidth + gap
        let temperatureX = bounds.maxX - inset - temperatureWidth
        let labelFont = NSFont.systemFont(ofSize: max(7, min(9, height * 0.15)), weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: max(9, min(15, height * 0.21)), weight: .semibold)
        let labelHeight = fontHeight(labelFont)
        let valueHeight = fontHeight(valueFont)
        let labelY = height - labelHeight - 3
        let valueY = labelY - valueHeight - 2
        let palette = pixelPalette()

        drawLabel("CPU", in: NSRect(x: cpuX, y: labelY, width: gaugeWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark))
        drawLabel("RAM", in: NSRect(x: ramX, y: labelY, width: gaugeWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark))
        drawGauge(reading?.cpuPercent, x: cpuX, width: gaugeWidth, valueY: valueY,
                  valueHeight: valueHeight, height: height, accent: palette.accent, dark: dark)
        drawGauge(reading?.memoryPercent, x: ramX, width: gaugeWidth, valueY: valueY,
                  valueHeight: valueHeight, height: height, accent: palette.warm, dark: dark)

        drawLabel("AVG CPU", in: NSRect(x: temperatureX, y: labelY, width: temperatureWidth, height: labelHeight),
                  font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
        drawTemperature(reading?.temperatureCelsius, in: NSRect(x: temperatureX, y: 5,
                                                                width: temperatureWidth, height: valueY - 5 + valueHeight),
                        dark: dark)
    }

    private func drawGauge(_ value: Double?, x: CGFloat, width: CGFloat, valueY: CGFloat,
                           valueHeight: CGFloat, height: CGFloat, accent: NSColor, dark: Bool) {
        let available = value.flatMap { $0.isFinite ? $0 : nil }
        let valueText = available.map { "\(Int($0.rounded()))%" } ?? "--"
        let size = max(9, min(15, height * 0.21))
        let valueFont = theme == .pixel
            ? (NSFont(name: "Menlo-Bold", size: size) ?? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold))
            : NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        drawLabel(valueText, in: NSRect(x: x, y: valueY, width: width, height: valueHeight),
                  font: valueFont, color: available == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)

        let radius = min(width * 0.32, height * 0.21)
        let center = NSPoint(x: x + width / 2, y: max(4, height * 0.20))
        let count = 13
        let filled = available.map { Int((min(100, max(0, $0)) / 100 * Double(count)).rounded(.down)) } ?? 0
        if theme == .pixel {
            let grid = max(2.5, min(3.4, height * 0.055))
            let block = grid * 0.82
            for index in 0..<count {
                let angle = Double.pi - Double.pi * Double(index) / Double(count - 1)
                let gx = (CGFloat(cos(angle)) * radius / grid).rounded() * grid
                let gy = (CGFloat(sin(angle)) * radius / grid).rounded() * grid
                let pixel = NSRect(x: center.x + gx - block / 2, y: center.y + gy - block / 2,
                                  width: block, height: block)
                (index < filled ? accent : trackColor(dark: dark)).setFill()
                pixel.fill()
            }
        } else {
            for index in 0..<count {
                let angle = Double.pi - Double.pi * Double(index) / Double(count - 1)
                let inner = radius - max(2, height * 0.055)
                let start = NSPoint(x: center.x + CGFloat(cos(angle)) * inner,
                                    y: center.y + CGFloat(sin(angle)) * inner)
                let end = NSPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                  y: center.y + CGFloat(sin(angle)) * radius)
                let tick = NSBezierPath()
                tick.lineWidth = 2.1
                tick.lineCapStyle = .round
                tick.move(to: start)
                tick.line(to: end)
                (index < filled ? accent : trackColor(dark: dark)).setStroke()
                tick.stroke()
            }
        }
    }

    private func drawTemperature(_ value: Double?, in rect: NSRect, dark: Bool) {
        let degrees = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let digits = degrees.map { String($0) } ?? "--"
        let suffixFont = NSFont.monospacedDigitSystemFont(ofSize: max(7, min(10, rect.height * 0.19)), weight: .medium)
        let suffix = "°C"
        let suffixWidth = ceil((suffix as NSString).size(withAttributes: [.font: suffixFont]).width)
        let glyphGapRatio: CGFloat = 0.8
        let dotUnits = CGFloat(digits.count) * 6.4 + CGFloat(max(0, digits.count - 1)) * glyphGapRatio
        let dot = max(1, min(2.1, (rect.width - suffixWidth - 4) / dotUnits))
        let spacing = dot * 0.35
        let glyphWidth = dot * 5 + spacing * 4
        let glyphGap = dot * glyphGapRatio
        let totalWidth = CGFloat(digits.count) * glyphWidth + CGFloat(max(0, digits.count - 1)) * glyphGap + 3 + suffixWidth
        var x = rect.midX - totalWidth / 2
        let gridHeight = dot * 7 + spacing * 6
        let y = rect.midY - gridHeight / 2
        let color = degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark)
        for character in digits {
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
            x += glyphWidth + glyphGap
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
