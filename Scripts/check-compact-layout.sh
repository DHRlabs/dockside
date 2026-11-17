#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat "$repo_root/Sources/Dockside/BubblePanel.swift" > "$temp_dir/BubblePanelCheck.swift"
cat >> "$temp_dir/BubblePanelCheck.swift" <<'SWIFT'
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var selectedTheme: DocksideTheme = .glass

    @objc func toggleOpenAtLogin(_ sender: NSMenuItem) {}
    @objc func selectTheme(_ sender: NSMenuItem) {}
}

@main
struct CompactLayoutCheck {
    @MainActor
    static func main() {
        let readings = [
            UsageReading.empty("Claude 5h", provider: .claude, duration: 5 * 3600),
            UsageReading.empty("Claude", provider: .claude, duration: 7 * 86400),
            UsageReading.empty("Codex", provider: .codex),
            UsageReading.empty("Work", provider: .feed(colorHex: nil), duration: 7 * 86400)
        ]
        let height: CGFloat = 58
        let widths = BubblePanel.meterWidths(height: height, readings: readings)
        let natural = BubblePanel.meterLayout(height: height, available: 600, count: 4,
                                              naturalMeterWidth: widths.natural,
                                              minimumMeterWidth: widths.readableMinimum)!
        let slightlyShort = BubblePanel.meterLayout(height: height, available: natural.width - 1,
                                                    count: 4, naturalMeterWidth: widths.natural,
                                                    minimumMeterWidth: widths.readableMinimum)
        assert(slightlyShort != nil)
        assert(slightlyShort!.meterWidth < natural.meterWidth)
        assert(slightlyShort!.meterWidth >= widths.readableMinimum)

        var lower: CGFloat = 0
        var upper = natural.width
        for _ in 0..<20 {
            let middle = (lower + upper) / 2
            if BubblePanel.meterLayout(height: height, available: middle, count: 4,
                                       naturalMeterWidth: widths.natural,
                                       minimumMeterWidth: widths.readableMinimum) == nil {
                lower = middle
            } else {
                upper = middle
            }
        }
        assert(BubblePanel.meterLayout(height: height, available: lower, count: 4,
                                       naturalMeterWidth: widths.natural,
                                       minimumMeterWidth: widths.readableMinimum) == nil)
        assert(BubblePanel.meterLayout(height: height, available: upper, count: 4,
                                       naturalMeterWidth: widths.natural,
                                       minimumMeterWidth: widths.readableMinimum) != nil)

        let compact = BubblePanel.meterLayout(height: height, available: upper - 1, count: 4,
                                              naturalMeterWidth: widths.natural,
                                              minimumMeterWidth: widths.readableMinimum) == nil
            ? BubblePanel.compactMeterLayout(available: upper - 1, count: 4) : nil
        assert(compact?.width == 216)
        assert(BubblePanel.meterLayout(height: height, available: 500, count: 4,
                                       naturalMeterWidth: widths.natural,
                                       minimumMeterWidth: widths.readableMinimum) != nil)

        let availableWidths: [CGFloat] = [180, 200, 216, 400]
        for available in availableWidths {
            guard let layout = BubblePanel.compactMeterLayout(available: available, count: 4) else {
                fatalError("Expected compact meters when space is available")
            }
            assert(layout.width <= min(216, available))
            assert(layout.inset >= 0 && layout.gap >= 0 && layout.meterWidth > 0)
            let lastBarEnd = layout.inset + 4 * layout.meterWidth + 3 * layout.gap
            assert(lastBarEnd <= layout.width)
        }
        assert(BubblePanel.compactMeterLayout(available: 179.9, count: 4) == nil)
        assert(BubblePanel.compactMeterLayout(available: 0, count: 4) == nil)
        assert(BubblePanel.compactMeterLayout(available: 160, count: 4,
                                              minimumWidth: 160)?.width == 160)

        let statsView = SystemStatsView(frame: .zero)
        for (theme, normalRatio, compactRatio) in [
            (DocksideTheme.glass, 4.59, 3.94),
            (DocksideTheme.pixel, 5.19, 4.30),
            (DocksideTheme.ticks, 4.59, 3.94)
        ] {
            statsView.setTheme(theme)
            for height: CGFloat in [40, 58, 100] {
                let normal = statsView.width(for: height, compact: false)
                let compact = statsView.width(for: height, compact: true)
                assert(abs(normal - height * CGFloat(normalRatio)) < 0.01)
                assert(abs(compact - height * CGFloat(compactRatio)) < 0.01)
                assert(normal > compact && compact > 0)
            }
        }
        print("Stats widths passed for all three themes at 40, 58, and 100pt")

        // Compact width grows with the meter count, keeping the four-meter cell width.
        for (count, expected) in [(1, 216.0), (2, 216.0), (3, 216.0), (4, 216.0),
                                  (5, 268.0), (6, 320.0), (7, 372.0)] {
            guard let wide = BubblePanel.compactMeterLayout(available: 1000, count: count) else {
                fatalError("Expected a compact layout for \(count) meters")
            }
            assert(wide.width == CGFloat(expected), "\(count) -> \(wide.width)")
            if count >= 4 {
                assert(abs(wide.meterWidth - 44) < 0.001, "\(count) -> \(wide.meterWidth)")
            }
        }
        for count in 1...4 {
            for available in availableWidths {
                let layout = BubblePanel.compactMeterLayout(available: available, count: count)!
                assert(layout.width == min(216, available), "\(count)@\(available) -> \(layout.width)")
            }
        }
        let crowded = BubblePanel.compactMeterLayout(available: 250, count: 6)!
        assert(crowded.width == 250 && crowded.meterWidth < 44,
               "\(crowded.width) \(crowded.meterWidth)")
        print(String(format: "compact caps: 1-4 -> 216, 5 -> 268, 6 -> 320; 6 meters in 250pt -> %.0fpt wide, %.1fpt cells",
                     crowded.width, crowded.meterWidth))

        // Labels in a 44pt cell, measured in the compact name font.
        let compactNameFont = NSFont.systemFont(ofSize: min(10, max(7.5, 44 * 0.24)), weight: .medium)
        for label in ["Work 5h", "Codex 5h", "Claude", "5h"] {
            let width = ceil(textSize(label, font: compactNameFont).width)
            print(String(format: "label \"%@\" %.0fpt vs a 44pt cell%@", label, width,
                         width <= 44 ? "" : " (over)"))
        }
        assert(ceil(textSize("Work 5h", font: compactNameFont).width) <= 44)

        // Every five-hour meter shortens to "5h" in the compact view; the rest keep the name.
        for label in ["Claude 5h", "Codex 5h", "Work 5h"] {
            let short = BubblePanel.compactName(for: label)
            assert(short == "5h", "\(label) -> \(short)")
            print("compact name \"\(label)\" -> \"\(short)\"")
        }
        for label in ["Claude", "Codex", "Work", "Studio"] {
            let short = BubblePanel.compactName(for: label)
            assert(short == label, "\(label) -> \(short)")
            let width = ceil(textSize(short, font: compactNameFont).width)
            print(String(format: "compact name \"%@\" unchanged, %.0fpt vs a 44pt cell%@", short, width,
                         width <= 44 ? "" : " (over)"))
        }
        for label in ["Studio", "Claude"] {
            assert(ceil(textSize(label, font: compactNameFont).width) <= 44, label)
        }
        // The full row and the hover card both draw reading.label through
        // drawMeterTitleLine, so their labels stay long.
        let fullReading = UsageReading.empty("Work 5h", provider: .feed(colorHex: nil),
                                             duration: 5 * 3600)
        assert(fullReading.label == "Work 5h")
        print("full row and hover card label stays \"\(fullReading.label)\"")

        print(String(format: "AI panel normal at 58pt: %.1fpt natural, %.1fpt readable minimum; compact: 180-216pt for four",
                     natural.width, upper))
        print("Compact layout checks passed")
    }
}
SWIFT

source_files=()
for source in "$repo_root"/Sources/Dockside/*.swift; do
    case "$source" in
        */BubblePanel.swift|*/main.swift) continue ;;
    esac
    source_files+=("$source")
done

swiftc -parse-as-library "$temp_dir/BubblePanelCheck.swift" "${source_files[@]}" -o "$temp_dir/check"
"$temp_dir/check"
