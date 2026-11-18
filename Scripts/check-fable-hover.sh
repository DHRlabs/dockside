#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

# Usage.swift and BubblePanel.swift join the check in one file so its fileprivate
# readings and compact layout are both in reach.
cat "$repo_root/Sources/Dockside/Usage.swift" \
    "$repo_root/Sources/Dockside/BubblePanel.swift" > "$temp_dir/FableHoverCheck.swift"
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
    hex(meterFillColor(for: reading))
}

private func hex(_ color: NSColor) -> String {
    let color = color.usingColorSpace(.sRGB) ?? .black
    return String(format: "#%02X%02X%02X",
                  Int((color.redComponent * 255).rounded()),
                  Int((color.greenComponent * 255).rounded()),
                  Int((color.blueComponent * 255).rounded()))
}

private let violet = "#8E6CF0"
private let canvas = NSColor(srgbRed: 15 / 255.0, green: 19 / 255.0, blue: 26 / 255.0, alpha: 1)
private let scale = 4
private let dockHeight: CGFloat = 64

/// The bubble meters drawn the way the app draws them, dark appearance, on a plate, at 4x.
@MainActor
private func renderBubble(_ bubble: [UsageReading], fable: [UsageReading], now: Date) -> (rep: NSBitmapImageRep, layout: (inset: CGFloat, gap: CGFloat, meterWidth: CGFloat, width: CGFloat)) {
    _ = NSApplication.shared
    let widths = BubblePanel.meterWidths(height: dockHeight, readings: bubble)
    let layout = BubblePanel.meterLayout(height: dockHeight, available: 4000, count: bubble.count,
                                         naturalMeterWidth: widths.natural,
                                         minimumMeterWidth: widths.minimum)!
    let view = UsageMetersView(frame: NSRect(x: 0, y: 0, width: layout.width, height: dockHeight))
    view.appearance = NSAppearance(named: .darkAqua)
    view.readings = bubble
    view.fableReadings = fable
    view.now = now
    return (draw(view), layout)
}

@MainActor
private func draw(_ view: NSView) -> NSBitmapImageRep {
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width.rounded(.up)) * scale,
                               pixelsHigh: Int(size.height.rounded(.up)) * scale, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)))
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    canvas.setFill()
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 15, yRadius: 15).fill()
    view.displayIgnoringOpacity(view.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> String {
    hex(rep.colorAt(x: x, y: y) ?? .black)
}

private func near(_ a: String, _ b: String) -> Bool {
    func parts(_ s: String) -> [Int] { (0..<3).map { Int(s.dropFirst(1 + $0 * 2).prefix(2), radix: 16)! } }
    return zip(parts(a), parts(b)).allSatisfy { abs($0 - $1) <= 3 }
}

/// Bounding box (in pixels) of every pixel that differs between two renders, or nil.
private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
    assert(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh)
    var xs: [Int] = [], ys: [Int] = []
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide where pixel(a, x, y) != pixel(b, x, y) { xs.append(x); ys.append(y) }
    }
    guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
    return (x0...x1, y0...y1)
}

/// Proves the sub-bar under the meter at `index`: nothing else changes, and its fill and color.
@MainActor
private func proveSubBar(bubble: [UsageReading], fable: [UsageReading], index: Int, share: Double, now: Date,
                         trackBetween: Bool = true) -> String {
    let plain = renderBubble(bubble, fable: [], now: now)
    let with = renderBubble(bubble, fable: fable, now: now)
    let diff = difference(plain.rep, with.rep)!
    let meterX = Int(((plain.layout.inset + CGFloat(index) * (plain.layout.meterWidth + plain.layout.gap))
                      * CGFloat(scale)).rounded())
    let meterW = Int((plain.layout.meterWidth * CGFloat(scale)).rounded())
    // Every changed pixel sits in the strip under that one meter's bar, as wide as the meter.
    assert(abs(diff.x.lowerBound - meterX) <= 2 && abs(diff.x.upperBound - (meterX + meterW)) <= 2,
           "\(diff.x) vs \(meterX)+\(meterW)")
    let strip = diff.y.upperBound - diff.y.lowerBound + 1
    let barPixels = Int((dockHeight * 0.08 * CGFloat(scale)).rounded())
    assert(abs(strip - barPixels / 2) <= 2, "strip \(strip) vs half of \(barPixels)")
    // Fill fraction and colors along the strip's middle row.
    let row = (diff.y.lowerBound + diff.y.upperBound) / 2
    let samples = (diff.x.lowerBound...diff.x.upperBound).map { pixel(with.rep, $0, row) }
    let violetCount = samples.filter { near($0, violet) }.count
    let fraction = Double(violetCount) / Double(samples.count)
    assert(abs(fraction - share) < 0.03, "fill \(fraction)")
    let track = hex(NSColor(srgbRed: 44.0 / 255, green: 54.0 / 255, blue: 72.0 / 255, alpha: 1))
    assert(near(samples.last!, track) || near(samples[samples.count - 4], track), samples.last!)
    assert(!samples.contains { near($0, "#D97757") || near($0, "#D9923F") })
    // The rest of the bubble, meter by meter, is byte for byte what main draws.
    assert(with.rep.pixelsWide == plain.rep.pixelsWide)
    return String(format: "sub-bar x %d-%d y %d-%d, fill %.2f, color %@", diff.x.lowerBound, diff.x.upperBound,
                  diff.y.lowerBound, diff.y.upperBound, fraction, violet)
}

/// The hover card rows, dark, to read the Fable row's bar color.
@MainActor
private func hoverRowColors(_ readings: [UsageReading]) -> Set<String> {
    _ = NSApplication.shared
    let rows = HoverCardRowsView(frame: NSRect(x: 0, y: 0, width: 260, height: 24 + 48 * CGFloat(readings.count)))
    rows.appearance = NSAppearance(named: .darkAqua)
    rows.readings = readings
    let rep = draw(rows)
    var colors = Set<String>()
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        let color = pixel(rep, x, y)
        if near(color, violet) { colors.insert(violet) }
        if near(color, "#D97757") { colors.insert("#D97757") }
        if near(color, "#D9923F") { colors.insert("#D9923F") }
    } }
    return colors
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
                                     observedAt: observedAt, stateIsOK: true, account: "claude"))
    }
    if let sevenDay = decoded.sevenDay {
        readings.append(UsageReading(label: "Claude", provider: .claude, duration: 7 * 86400,
                                     used: sevenDay.utilization,
                                     resetsAt: ISO8601DateFormatter().date(from: sevenDay.resetsAt ?? ""),
                                     observedAt: observedAt, stateIsOK: true,
                                     account: "claude", isWeekly: true))
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
        assert(hex(fable) == violet && hex(main[1]) == "#D97757", hex(fable))
        print("a. with Fable -> hover \(describe(hover(main))); bubble \(describe(bubble(main))); "
              + "Claude Fable \(fable.percentageText(at: now)) resets in \(fable.resetLine(at: now)!) color \(hex(fable))")

        // b. Feed account with a Fable window.
        let work = UsageClient.feedReadings(from: accounts(feedWithFable),
                                            names: UsageClient.accountNames(from: "Work"))
        assert(describe(hover(work)) == "Work 5h=7 Work=3 Work Fable=46", describe(work))
        assert(describe(bubble(work)) == "Work 5h=7 Work=3", describe(bubble(work)))
        assert(work[2].hoverOnly && !work[0].hoverOnly && !work[1].hoverOnly)
        assert(hex(work[2]) == violet && hex(work[1]) == "#D9923F", hex(work[2]))
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

        // e. An unparseable Fable feed window gives a hover row that reads as --, never a guess,
        //    and the account still keeps the one empty meter it has without any Fable window.
        let blank = UsageClient.feedReadings(from: accounts(
            "{\"accounts\":[{\"name\":\"Work\",\"state\":\"ok\",\"at\":\"2026-11-17T00:24:17Z\",\"windows\":[{\"label\":\"Fable\",\"resetsAt\":\"2099-11-20T20:00:00Z\"}]}]}"),
                                             names: UsageClient.accountNames(from: "Work"))
        assert(describe(blank) == "Work=-- Work Fable=--", describe(blank))
        assert(describe(bubble(blank)) == "Work=--", describe(bubble(blank)))
        assert(blank[1].percentageText(at: now) == "--")
        print("e. Fable window with no used -> \(describe(blank)) in the hover card, "
              + "\(describe(bubble(blank))) in the bubble row")

        // f. The reviewer's case: five configured accounts, one with only a Fable window.
        //    The bubble readings and the compact width must be exactly main's.
        let fableOnlyFeed = """
        {"accounts":[{"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","windows":[
           {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"},
           {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"}]},
          {"name":"Studio","state":"ok","at":"2026-11-17T00:24:17Z","windows":[
           {"label":"Fable","used":46,"resetsAt":"2099-11-20T20:00:00Z"}]}]}
        """
        /// The same feed with the Fable window removed, which is what main sees.
        let mainFeed = """
        {"accounts":[{"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","windows":[
           {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"},
           {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"}]},
          {"name":"Studio","state":"ok","at":"2026-11-17T00:24:17Z","windows":[]}]}
        """
        let names = UsageClient.accountNames(from: "Work,Studio")
        let withRow = claudeReadings(withFable, observedAt: now)
            + UsageClient.feedReadings(from: accounts(fableOnlyFeed), names: names)
        let mainRow = claudeReadings(withoutFable, observedAt: now)
            + UsageClient.feedReadings(from: accounts(mainFeed), names: names)
        assert(describe(bubble(withRow)) == describe(bubble(mainRow)), describe(bubble(withRow)))
        assert(describe(bubble(withRow)) == "Claude 5h=18 Claude=41 Work 5h=7 Work=3 Studio=--",
               describe(bubble(withRow)))
        assert(bubble(withRow).count == 5 && mainRow.count == 5)
        let hoverExtra = hover(withRow).filter { $0.hoverOnly }.map(\.label)
        assert(hoverExtra == ["Claude Fable", "Studio Fable"], "\(hoverExtra)")
        let before = BubblePanel.compactMeterLayout(available: 1000, count: bubble(mainRow).count)!
        let after = BubblePanel.compactMeterLayout(available: 1000, count: bubble(withRow).count)!
        assert(before.width == 268 && after.width == before.width, "\(before.width) \(after.width)")
        print("f. five accounts, one Fable-only -> bubble \(describe(bubble(withRow))); "
              + String(format: "compact %.0fpt on main and %.0fpt here; hover adds ", before.width, after.width)
              + hoverExtra.joined(separator: ", "))

        // g. The bubble sub-bar, from real drawing: Claude Fable 46 under the weekly Claude meter.
        let weeklyNow = now.addingTimeInterval(3 * 86400)
        func reading(_ label: String, _ provider: UsageReading.Provider, _ used: Double,
                     hours: Double, week: Bool = false, hoverOnly: Bool = false,
                     account: String? = nil) -> UsageReading {
            UsageReading(label: label, provider: provider, duration: week ? 7 * 86400 : 5 * 3600, used: used,
                         resetsAt: week ? weeklyNow : now.addingTimeInterval(hours * 3600),
                         observedAt: now, stateIsOK: true, hoverOnly: hoverOnly,
                         account: account, isWeekly: week && !hoverOnly)
        }
        let workColor = UsageReading.Provider.feed(colorHex: "#D9923F")
        let claudeBubble = [reading("Claude 5h", .claude, 18, hours: 3, account: "claude"), reading("Claude", .claude, 41, hours: 0, week: true, account: "claude")]
        let claudeFable = reading("Claude Fable", .claude, 46, hours: 0, week: true, hoverOnly: true, account: "claude")
        assert(BubblePanel.fableReading(for: claudeBubble[1], in: [claudeFable]) != nil)
        assert(BubblePanel.fableReading(for: claudeBubble[0], in: [claudeFable]) == nil)
        let claudeProof = proveSubBar(bubble: claudeBubble, fable: [claudeFable], index: 1, share: 0.46, now: now)
        let sameWidths = BubblePanel.meterWidths(height: dockHeight, readings: claudeBubble)
        assert(sameWidths.natural == BubblePanel.meterWidths(height: dockHeight, readings: bubble(claudeBubble + [claudeFable])).natural)
        assert(describe(bubble(claudeBubble + [claudeFable])) == "Claude 5h=18 Claude=41")
        let hoverClaude = hoverRowColors(claudeBubble + [claudeFable])
        assert(hoverClaude == [violet, "#D97757"], "\(hoverClaude)")
        print("g. Claude Fable 46 -> bubble meters Claude 5h, Claude (2, widths unchanged); \(claudeProof); "
              + "hover Fable row \(hex(claudeFable))")

        // h. The same for the feed account Work.
        let workBubble = [reading("Work 5h", workColor, 7, hours: 2, account: "feed:Work"), reading("Work", workColor, 3, hours: 0, week: true, account: "feed:Work")]
        let workFable = reading("Work Fable", workColor, 46, hours: 0, week: true, hoverOnly: true, account: "feed:Work")
        let workProof = proveSubBar(bubble: workBubble, fable: [workFable], index: 1, share: 0.46, now: now)
        let hoverWork = hoverRowColors(workBubble + [workFable])
        assert(hoverWork == [violet, "#D9923F"], "\(hoverWork)")
        print("h. Work Fable 46 -> bubble meters Work 5h, Work; \(workProof); hover Fable row \(hex(workFable))")

        // i. No Fable reading for the account: the drawing is untouched, pixel for pixel.
        let stranger = reading("Other Fable", .claude, 30, hours: 0, week: true, hoverOnly: true, account: "other")
        let none = renderBubble(claudeBubble, fable: [], now: now)
        let unrelated = renderBubble(claudeBubble, fable: [stranger], now: now)
        assert(difference(none.rep, unrelated.rep) == nil)
        assert(difference(none.rep, renderBubble(workBubble, fable: [], now: now).rep) != nil)
        print("i. no matching Fable reading -> bubble pixels identical to the no-Fable drawing")

        // k. The reviewer's case: "Work" (five-hour only) beside "Work 5h" (week and Fable), built
        //    through the feed. Only the Work 5h account's weekly meter gets the sub-bar.
        let twin = UsageClient.feedReadings(from: accounts("""
        {"accounts":[{"name":"Work","state":"ok","at":"2026-11-17T00:24:17Z","windows":[
           {"label":"5 hours","used":7,"resetsAt":"2099-11-17T02:30:00Z"}]},
          {"name":"Work 5h","state":"ok","at":"2026-11-17T00:24:17Z","windows":[
           {"label":"week","used":3,"resetsAt":"2099-11-20T20:00:00Z"},
           {"label":"Fable","used":46,"resetsAt":"2099-11-20T20:00:00Z"}]}]}
        """), names: ["Work", "Work 5h"])
        assert(describe(bubble(twin)) == "Work 5h=7 Work 5h=3", describe(bubble(twin)))
        let twinBubble = bubble(twin), twinFable = twin.filter { $0.hoverOnly }
        assert(twinFable.count == 1)
        assert(BubblePanel.fableReading(for: twinBubble[0], in: twinFable) == nil)
        assert(BubblePanel.fableReading(for: twinBubble[1], in: twinFable) != nil)
        let twinProof = proveSubBar(bubble: twinBubble, fable: twinFable, index: 1, share: 0.46, now: now)
        print("k. Work + Work 5h -> five-hour meter of Work none; Work 5h weekly meter only; \(twinProof)")

        // l. A Fable-only account: its empty placeholder draws no sub-bar, the hover row stays.
        let only = UsageClient.feedReadings(from: accounts(fableOnlyFeed), names: ["Studio"])
        assert(describe(bubble(only)) == "Studio=--" && hover(only).filter { $0.hoverOnly }.count == 1)
        assert(BubblePanel.fableReading(for: bubble(only)[0], in: only.filter { $0.hoverOnly }) == nil)
        let onlyPlain = renderBubble(bubble(only), fable: [], now: now)
        assert(difference(onlyPlain.rep, renderBubble(bubble(only), fable: only.filter { $0.hoverOnly }, now: now).rep) == nil)
        // The same name with no weekly window, as a five-hour account, never gets one either.
        let fiveOnly = UsageClient.feedReadings(from: accounts(feedWithFable), names: ["Work"])
        assert(BubblePanel.fableReading(for: fiveOnly[0], in: fiveOnly.filter { $0.hoverOnly }) == nil)
        print("l. Fable-only Studio -> bubble Studio=--, no sub-bar (pixels identical), hover row Studio Fable kept")

        // j. Sample bubble for the designer, when a path is given.
        if let path = ProcessInfo.processInfo.environment["DOCKSIDE_SUBBAR_PNG"] {
            let sample = [reading("Claude 5h", .claude, 18, hours: 3, account: "claude"), reading("Claude", .claude, 41, hours: 0, week: true, account: "claude"),
                          reading("Work 5h", workColor, 7, hours: 2, account: "feed:Work"), reading("Work", workColor, 3, hours: 0, week: true, account: "feed:Work"),
                          reading("Codex", .codex, 63, hours: 0, week: true, account: "feed:Codex")]
            let fables = [reading("Claude Fable", .claude, 46, hours: 0, week: true, hoverOnly: true, account: "claude"),
                          reading("Work Fable", workColor, 12, hours: 0, week: true, hoverOnly: true, account: "feed:Work")]
            let png = renderBubble(sample, fable: fables, now: now).rep.representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: path))
            print("j. sample bubble written to \(path)")
        }

        print("Fable hover checks passed")
    }
}
SWIFT

source_files=()
for source in "$repo_root"/Sources/Dockside/*.swift; do
    case "$source" in
        */Usage.swift|*/BubblePanel.swift|*/main.swift) continue ;;
    esac
    source_files+=("$source")
done

swiftc -parse-as-library "$temp_dir/FableHoverCheck.swift" "${source_files[@]}" -o "$temp_dir/check"
"$temp_dir/check"
