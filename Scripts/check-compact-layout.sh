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
            UsageReading.empty("Grok", provider: .grok, duration: 7 * 86400)
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
            (DocksideTheme.glass, 3.49, 3.00),
            (DocksideTheme.pixel, 3.96, 3.28)
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
        print("Stats widths passed for both themes at 40, 58, and 100pt")
        print(String(format: "AI panel normal at 58pt: %.1fpt natural, %.1fpt readable minimum; compact: 180-216pt",
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
