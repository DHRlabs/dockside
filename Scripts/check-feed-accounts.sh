#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

cat "$repo_root/Sources/Dockside/Usage.swift" > "$temp_dir/FeedAccountsCheck.swift"
cat >> "$temp_dir/FeedAccountsCheck.swift" <<'SWIFT'
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var selectedTheme: DocksideTheme = .glass

    @objc func toggleOpenAtLogin(_ sender: NSMenuItem) {}
    @objc func selectTheme(_ sender: NSMenuItem) {}
}

private let sample = """
{"accounts":[
 {"maker":"Anthropic","name":"Claude","state":"ok","at":"2026-11-17T01:01:21Z","windows":[
   {"label":"5 hours","used":100,"resetsAt":"2099-11-17T03:20:00Z"},
   {"label":"week","used":52,"resetsAt":"2099-11-20T11:00:00Z"}]},
 {"maker":"OpenAI","name":"Codex","state":"ok","at":"2026-11-17T01:01:21Z","windows":[
   {"label":"week","used":61,"resetsAt":"2099-11-22T01:42:45Z"}]},
 {"maker":"Anthropic","name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","color":"#D9923F","windows":[
   {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"},
   {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"}]}]}
"""

private struct CheckFeed: Decodable { let accounts: [FeedAccount]? }

private func accounts(_ json: String) -> [FeedAccount] {
    (try! JSONDecoder().decode(CheckFeed.self, from: Data(json.utf8)).accounts) ?? []
}

private func describe(_ readings: [UsageReading]) -> String {
    readings.map { reading in
        let used = reading.used.map { String(format: "%.0f", $0) } ?? "--"
        return "\(reading.label)=\(used)"
    }.joined(separator: " ")
}

private func hex(_ reading: UsageReading) -> String {
    let color = fillColor(for: reading.provider).usingColorSpace(.sRGB) ?? .black
    return String(format: "#%02X%02X%02X",
                  Int((color.redComponent * 255).rounded()),
                  Int((color.greenComponent * 255).rounded()),
                  Int((color.blueComponent * 255).rounded()))
}

@main
struct FeedAccountsCheck {
    @MainActor
    static func main() {
        let all = accounts(sample)

        // a. Setting unset or empty means Codex alone, exactly as before.
        for setting in [nil, "", "  "] as [String?] {
            let readings = UsageClient.feedReadings(from: all,
                                                    names: UsageClient.accountNames(from: setting))
            assert(describe(readings) == "Codex=61", describe(readings))
            assert(hex(readings[0]) == "#3FBFB2", hex(readings[0]))
        }
        print("a. unset/empty -> Codex=61 teal #3FBFB2")

        // b. Two accounts in order, with the feed color and no unconfigured accounts.
        let two = UsageClient.feedReadings(from: all,
                                           names: UsageClient.accountNames(from: "Work,Codex"))
        assert(describe(two) == "Work 5h=7 Work=3 Codex=61", describe(two))
        assert(hex(two[0]) == "#D9923F" && hex(two[1]) == "#D9923F", hex(two[0]))
        assert(hex(two[2]) == "#3FBFB2", hex(two[2]))
        assert(!two.contains { $0.label.hasPrefix("Claude") })
        print("b. Work,Codex -> \(describe(two)); colors \(hex(two[0])) \(hex(two[1])) \(hex(two[2])); no Claude")

        // c. Missing account, missing color, bad color.
        let codexOnly = accounts(
            "{\"accounts\":[{\"name\":\"Codex\",\"state\":\"ok\",\"at\":\"2026-11-17T01:01:21Z\",\"windows\":[{\"label\":\"week\",\"used\":61,\"resetsAt\":\"2099-11-22T01:42:45Z\"}]}]}")
        let missing = UsageClient.feedReadings(from: codexOnly,
                                               names: UsageClient.accountNames(from: "Work,Codex"))
        assert(describe(missing) == "Work=-- Codex=61", describe(missing))
        let neutral = fillColor(for: .feed(colorHex: nil))
        for json in [
            "{\"accounts\":[{\"name\":\"Work\",\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"week\",\"used\":3,\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}",
            "{\"accounts\":[{\"name\":\"Work\",\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"color\":\"banana\",\"windows\":[{\"label\":\"week\",\"used\":3,\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}"
        ] {
            let readings = UsageClient.feedReadings(from: accounts(json),
                                                    names: UsageClient.accountNames(from: "Work"))
            assert(describe(readings) == "Work=3", describe(readings))
            assert(fillColor(for: readings[0].provider) == neutral)
        }
        assert(fillColor(for: .feed(colorHex: nil)) == NSColor.labelColor)
        print("c. missing account -> \(describe(missing)); absent and invalid color -> labelColor neutral")

        // d. Spaces and empty entries are trimmed and skipped.
        let messy = UsageClient.feedReadings(from: all,
                                             names: UsageClient.accountNames(from: " Work , ,Codex "))
        assert(describe(messy) == describe(two), describe(messy))
        print("d. \" Work , ,Codex \" -> \(describe(messy))")

        // e. A color that is not a string decodes as absent and spoils nothing else.
        let oddOnUnconfigured = """
        {"accounts":[
         {"name":"Spare","state":"ok","at":"2026-11-17T01:01:21Z","color":42,"windows":[
           {"label":"week","used":9,"resetsAt":"2099-11-22T01:42:45Z"}]},
         {"name":"Codex","state":"ok","at":"2026-11-17T01:01:21Z","windows":[
           {"label":"week","used":61,"resetsAt":"2099-11-22T01:42:45Z"}]}]}
        """
        let oddCodex = UsageClient.feedReadings(from: accounts(oddOnUnconfigured),
                                                names: UsageClient.accountNames(from: nil))
        assert(describe(oddCodex) == "Codex=61", describe(oddCodex))
        assert(hex(oddCodex[0]) == "#3FBFB2", hex(oddCodex[0]))

        let oddOnConfigured = """
        {"accounts":[
         {"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","color":42,"windows":[
           {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"}]},
         {"name":"Codex","state":"ok","at":"2026-11-17T01:01:21Z","windows":[
           {"label":"week","used":61,"resetsAt":"2099-11-22T01:42:45Z"}]}]}
        """
        let oddWork = UsageClient.feedReadings(from: accounts(oddOnConfigured),
                                               names: UsageClient.accountNames(from: "Work,Codex"))
        assert(describe(oddWork) == "Work=3 Codex=61", describe(oddWork))
        assert(fillColor(for: oddWork[0].provider) == neutral)
        assert(describe([oddWork[1]]) == "Codex=61")
        for json in [
            "{\"accounts\":[{\"name\":\"Work\",\"color\":{\"hex\":\"#fff\"},\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"week\",\"used\":3,\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}",
            "{\"accounts\":[{\"name\":\"Work\",\"color\":[1,2],\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"week\",\"used\":3,\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}",
            "{\"accounts\":[{\"name\":\"Work\",\"color\":true,\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"week\",\"used\":3,\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}"
        ] {
            let readings = UsageClient.feedReadings(from: accounts(json),
                                                    names: UsageClient.accountNames(from: "Work"))
            assert(describe(readings) == "Work=3", describe(readings))
            assert(fillColor(for: readings[0].provider) == neutral)
        }
        print("e. non-string color -> absent; unconfigured odd account -> \(describe(oddCodex)); configured -> \(describe(oddWork)) with neutral Work")

        print("Feed account checks passed")
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

swiftc -parse-as-library "$temp_dir/FeedAccountsCheck.swift" "${source_files[@]}" -o "$temp_dir/check"
"$temp_dir/check"
