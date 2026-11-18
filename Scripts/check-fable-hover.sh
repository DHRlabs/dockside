#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat "$repo_root/Sources/Dockside/Usage.swift" > "$temp_dir/FableHoverCheck.swift"
cat >> "$temp_dir/FableHoverCheck.swift" <<'SWIFT'
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var selectedTheme: DocksideTheme = .glass

    @objc func toggleOpenAtLogin(_ sender: NSMenuItem) {}
    @objc func selectTheme(_ sender: NSMenuItem) {}
}

/// The main Claude account payload, with the weekly limit scoped to Fable.
private let withFable = """
{"five_hour":{"utilization":18,"resets_at":"2099-11-17T03:20:00+00:00"},
 "seven_day":{"utilization":41,"resets_at":"2099-11-22T00:00:00+00:00"},
 "limits":[{"kind":"weekly_all","group":"weekly","percent":2,"severity":"normal","resets_at":"2099-11-22T00:00:00.285359+00:00","scope":null,"is_active":true},{"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal","resets_at":"2099-11-22T00:00:00.285524+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}]}
"""

/// The same payload with no Fable entry at all.
private let withoutFable = """
{"five_hour":{"utilization":18,"resets_at":"2099-11-17T03:20:00+00:00"},
 "seven_day":{"utilization":41,"resets_at":"2099-11-22T00:00:00+00:00"},
 "limits":[{"kind":"weekly_all","group":"weekly","percent":2,"resets_at":"2099-11-22T00:00:00.285359+00:00","scope":null}]}
"""

private let feedWithFable = """
{"accounts":[{"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","color":"#D9923F","windows":[
   {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"},
   {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"},
   {"label":"Fable","used":46,"resetsAt":"2099-11-20T20:00:00Z"}]}]}
"""

private let feedWithoutFable = """
{"accounts":[{"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","color":"#D9923F","windows":[
   {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"},
   {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"}]}]}
"""

private struct CheckFeed: Decodable { let accounts: [FeedAccount]? }

private func accounts(_ json: String) -> [FeedAccount] {
    (try! JSONDecoder().decode(CheckFeed.self, from: Data(json.utf8)).accounts) ?? []
}

private func response(_ json: String) -> ClaudeResponse {
    try! JSONDecoder().decode(ClaudeResponse.self, from: Data(json.utf8))
}

private func describe(_ readings: [UsageReading]) -> String {
    readings.map { reading in
        let used = reading.used.map { String(format: "%.0f", $0) } ?? "--"
        return "\(reading.label)=\(used)"
    }.joined(separator: " ")
}

private func hover(_ readings: [UsageReading]) -> [UsageReading] { readings }
private func bubble(_ readings: [UsageReading]) -> [UsageReading] { readings.filter { !$0.hoverOnly } }

private func hex(_ reading: UsageReading) -> String {
    let color = fillColor(for: reading.provider).usingColorSpace(.sRGB) ?? .black
    return String(format: "#%02X%02X%02X",
                  Int((color.redComponent * 255).rounded()),
                  Int((color.greenComponent * 255).rounded()),
                  Int((color.blueComponent * 255).rounded()))
}

/// Readings the main-account payload makes, built the way the poller builds them.
@MainActor
private func claudeReadings(_ json: String, observedAt: Date) -> [UsageReading] {
    let decoded = response(json)
    var readings: [UsageReading] = []
    if let fiveHour = decoded.fiveHour {
        readings.append(UsageReading(label: "Claude 5h", provider: .claude, duration: 5 * 3600,
                                     used: fiveHour.utilization,
                                     resetsAt: ISO8601DateFormatter().date(from: fiveHour.resetsAt ?? ""),
                                     observedAt: observedAt, stateIsOK: true))
    }
    if let sevenDay = decoded.sevenDay {
        readings.append(UsageReading(label: "Claude", provider: .claude, duration: 7 * 86400,
                                     used: sevenDay.utilization,
                                     resetsAt: ISO8601DateFormatter().date(from: sevenDay.resetsAt ?? ""),
                                     observedAt: observedAt, stateIsOK: true))
    }
    if let fable = UsageClient.fableReading(from: decoded.limits, observedAt: observedAt) {
        readings.append(fable)
    }
    return readings
}

@main
struct FableHoverCheck {
    @MainActor
    static func main() {
        let now = Date()

        // a. Main account: the hover card gains Claude Fable 0%, the bubble row does not.
        let main = claudeReadings(withFable, observedAt: now)
        assert(describe(hover(main)) == "Claude 5h=18 Claude=41 Claude Fable=0", describe(main))
        assert(describe(bubble(main)) == "Claude 5h=18 Claude=41", describe(bubble(main)))
        let fable = main[2]
        assert(fable.hoverOnly)
        assert(fable.percentageText(at: now) == "0%", fable.percentageText(at: now))
        assert(fable.resetLine(at: now) != nil)
        assert(hex(fable) == hex(main[1]), hex(fable))
        print("a. with Fable -> hover \(describe(hover(main))); bubble \(describe(bubble(main))); "
              + "Claude Fable \(fable.percentageText(at: now)) resets in \(fable.resetLine(at: now)!) color \(hex(fable))")

        // b. Feed account with a Fable window.
        let work = UsageClient.feedReadings(from: accounts(feedWithFable),
                                            names: UsageClient.accountNames(from: "Work"))
        assert(describe(hover(work)) == "Work 5h=7 Work=3 Work Fable=46", describe(work))
        assert(describe(bubble(work)) == "Work 5h=7 Work=3", describe(bubble(work)))
        assert(work[2].hoverOnly && !work[0].hoverOnly && !work[1].hoverOnly)
        assert(hex(work[2]) == "#D9923F" && hex(work[1]) == "#D9923F", hex(work[2]))
        print("b. Work with Fable -> hover \(describe(hover(work))); bubble \(describe(bubble(work))); "
              + "Work Fable color \(hex(work[2]))")

        // c. No Fable entry and no Fable window: nothing added anywhere.
        let plain = claudeReadings(withoutFable, observedAt: now)
        assert(describe(hover(plain)) == "Claude 5h=18 Claude=41", describe(plain))
        assert(describe(hover(plain)) == describe(bubble(plain)))
        assert(!plain.contains { $0.hoverOnly })
        assert(UsageClient.fableReading(from: response(withoutFable).limits, observedAt: now) == nil)
        let plainWork = UsageClient.feedReadings(from: accounts(feedWithoutFable),
                                                 names: UsageClient.accountNames(from: "Work"))
        assert(describe(hover(plainWork)) == "Work 5h=7 Work=3", describe(plainWork))
        assert(describe(hover(plainWork)) == describe(bubble(plainWork)))
        assert(!plainWork.contains { $0.hoverOnly })
        print("c. no Fable -> \(describe(plain)) and \(describe(plainWork)), hover and bubble alike")

        // d. A malformed Fable entry is never guessed at.
        for json in [
            "{\"limits\":[{\"kind\":\"weekly_scoped\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"resets_at\":\"2099-11-22T00:00:00Z\"}]}",
            "{\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":5,\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"resets_at\":\"banana\"}]}",
            "{\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":\"five\",\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"resets_at\":\"2099-11-22T00:00:00Z\"}]}",
            "{\"limits\":[{\"kind\":\"weekly_all\",\"percent\":5,\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"resets_at\":\"2099-11-22T00:00:00Z\"}]}",
            "{\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":5,\"scope\":null,\"resets_at\":\"2099-11-22T00:00:00Z\"}]}",
            "{\"limits\":\"none\"}",
            "{}"
        ] {
            let decoded = response(json)
            assert(UsageClient.fableReading(from: decoded.limits, observedAt: now) == nil, json)
        }
        // The weekly and five-hour numbers still decode beside an odd limits array.
        let oddLimits = response(
            "{\"five_hour\":{\"utilization\":18,\"resets_at\":\"2099-11-17T03:20:00Z\"},\"seven_day\":{\"utilization\":41,\"resets_at\":\"2099-11-22T00:00:00Z\"},\"limits\":42}")
        assert(oddLimits.sevenDay?.utilization == 41 && oddLimits.limits == nil)
        print("d. missing percent, bad date, wrong kind, wrong scope and odd limits -> no row")

        // e. An unparseable Fable feed window gives a hover row that reads as --, never a guess.
        let blank = UsageClient.feedReadings(from: accounts(
            "{\"accounts\":[{\"name\":\"Work\",\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"Fable\",\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}"),
                                             names: UsageClient.accountNames(from: "Work"))
        assert(describe(blank) == "Work Fable=--", describe(blank))
        assert(blank[0].percentageText(at: now) == "--")
        assert(bubble(blank).isEmpty)
        print("e. Fable window with no used -> \(describe(blank)) in the hover card, nothing in the bubble row")

        print("Fable hover checks passed")
    }
}
SWIFT

source_files=()
for source in "$repo_root"/Sources/Dockside/*.swift; do
    case "$source" in
        */Usage.swift|*/main.swift) continue ;;
    esac
    source_files+=("$source")
done

swiftc -parse-as-library "$temp_dir/FableHoverCheck.swift" "${source_files[@]}" -o "$temp_dir/check"
"$temp_dir/check"
