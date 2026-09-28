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
        assert(BubblePanel.fitsNaturalMeters(height: 58, available: 500, count: 4,
                                             naturalMeterWidth: 92.8))
        assert(!BubblePanel.fitsNaturalMeters(height: 58, available: 36, count: 4,
                                              naturalMeterWidth: 92.8))
        assert(BubblePanel.compactMeterLayout(available: 0, count: 4).map { $0.width } == nil)

        let availableWidths: [CGFloat] = [0.25, 10, 36, 200]
        for available in availableWidths {
            guard let layout = BubblePanel.compactMeterLayout(available: available, count: 4) else {
                fatalError("Expected compact bars when space is available")
            }
            assert(layout.width <= min(36, available))
            assert(layout.inset >= 0 && layout.gap >= 0 && layout.meterWidth > 0)
            let lastBarEnd = layout.inset + 4 * layout.meterWidth + 3 * layout.gap
            assert(lastBarEnd <= layout.width)
        }

        let statsView = SystemStatsView(frame: .zero)
        for height: CGFloat in [40, 58, 100] {
            assert(statsView.width(for: height, compact: true) == 100)
        }
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
