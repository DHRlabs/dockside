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
        guard height > 0 else { return 0 }
        switch (theme, compact) {
        case (.glass, false): return height * 3.02
        case (.glass, true): return height * 2.53
        case (.pixel, false): return height * 3.96
        case (.pixel, true): return height * 3.28
        }
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
        if theme == .glass {
            drawGlassMeters(height: height, palette: palette, dark: dark)
        } else {
            drawPixelMeters(height: height, palette: palette, dark: dark)
        }
    }

    private func drawGlassMeters(height: CGFloat, palette: (accent: NSColor, warm: NSColor), dark: Bool) {
        let diameter = height * (compact ? 0.54 : 0.62)
        let centerY = height * (compact ? 0.50 : 0.55)
        let cpuCenterX = bounds.minX + bounds.width * (compact ? 0.21 : 0.245)
        let ramCenterX = cpuCenterX + height * (compact ? 0.75 : 0.96)
        let temperatureCenterX = bounds.minX + bounds.width * (compact ? 0.79 : 0.82)
        let label = compact ? nil : "CPU"
        drawGlassRing(reading?.cpuPercent, label: label,
                      center: NSPoint(x: cpuCenterX, y: centerY), diameter: diameter,
                      height: height, compact: compact,
                      accent: palette.accent, dark: dark)
        drawGlassRing(reading?.memoryPercent, label: compact ? nil : "RAM",
                      center: NSPoint(x: ramCenterX, y: centerY), diameter: diameter,
                      height: height, compact: compact,
                      accent: palette.warm, dark: dark)
        let temperatureWidth = height * (compact ? 0.72 : 0.70)
        let temperatureHeight = height * 0.30
        drawGlassTemperature(reading?.temperatureCelsius,
                             in: NSRect(x: temperatureCenterX - temperatureWidth / 2,
                                        y: height * 0.27,
                                        width: temperatureWidth, height: temperatureHeight), dark: dark)
    }

    private func drawGlassRing(_ value: Double?, label: String?, center: NSPoint,
                               diameter: CGFloat, height: CGFloat, compact: Bool,
                               accent: NSColor, dark: Bool) {
        let thickness = height * (compact ? 0.065 : 0.075)
        let radius = diameter / 2 - thickness / 2
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                              width: radius * 2, height: radius * 2))
        ring.lineWidth = thickness
        trackColor(dark: dark).setStroke()
        ring.stroke()
        if let value, value.isFinite {
            let fraction = min(1, max(0, value / 100))
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.move(to: NSPoint(x: center.x, y: center.y + radius))
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - CGFloat(360 * fraction), clockwise: true)
                arc.lineWidth = thickness
                arc.lineCapStyle = .round
                accent.setStroke()
                arc.stroke()
            }
        }

        let number = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let text = number.map { "\($0)%" } ?? "--%"
        let textWidth = max(1, diameter - thickness * 2 - 2)
        let baseSize = height * 0.14
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .semibold)
        let measuredWidth = ceil(("100%" as NSString).size(withAttributes: [.font: baseFont]).width)
        let fittedSize = baseSize * min(1, textWidth / max(1, measuredWidth))
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(4, fittedSize), weight: .semibold)
        let textHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: center.x - textWidth / 2, y: center.y - textHeight / 2,
                                   width: textWidth, height: textHeight),
                  font: font, color: number == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)

        if let label {
            let labelFont = NSFont.systemFont(ofSize: max(5, min(9, height * 0.10)), weight: .medium)
            let labelHeight = fontHeight(labelFont)
            drawLabel(label, in: NSRect(x: center.x - diameter / 2, y: height * 0.09,
                                        width: diameter, height: labelHeight),
                      font: labelFont, color: secondaryColor(dark: dark), alignment: .center)
        }
    }

    private func drawGlassTemperature(_ value: Double?, in rect: NSRect, dark: Bool) {
        let degrees = value.flatMap { $0.isFinite ? Int($0.rounded()) : nil }
        let text = degrees.map { "\($0)°C" } ?? "--°C"
        let baseSize = min(16, rect.height * 0.50)
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: baseSize, weight: .medium)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: baseFont]).width)
        let size = baseSize * min(1, rect.width / max(1, measuredWidth))
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(6, size), weight: .medium)
        let textHeight = fontHeight(font)
        drawLabel(text, in: NSRect(x: rect.minX, y: rect.midY - textHeight / 2,
                                   width: rect.width, height: textHeight),
                  font: font, color: degrees == nil ? tertiaryColor(dark: dark) : primaryColor(dark: dark),
                  alignment: .center)
    }

    private func drawPixelMeters(height: CGFloat, palette: (accent: NSColor, warm: NSColor), dark: Bool) {
        let archWidth = height * (compact ? 0.80 : 0.96)
        let cpuCenterX = bounds.minX + height * (compact ? 0.58 : 0.69)
        let ramCenterX = bounds.minX + height * (compact ? 1.60 : 1.92)
        let temperatureCenterX = bounds.minX + bounds.width * 0.84
        drawPixelUsageArch(reading?.cpuPercent, label: "CPU", centerX: cpuCenterX,
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
                      fraction: fraction, color: accent, dark: dark)

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
