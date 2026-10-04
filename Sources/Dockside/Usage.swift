import Foundation

struct UsageReading {
    enum Provider {
        case claude
        case codex
        case grok
    }

    let label: String
    let provider: Provider
    let duration: TimeInterval?
    let used: Double?
    let resetsAt: Date?
    let observedAt: Date?
    let stateIsOK: Bool

    func isCurrent(at now: Date = Date()) -> Bool {
        guard stateIsOK, let used, used.isFinite, let resetsAt, resetsAt > now,
              observedAt != nil else { return false }
        return true
    }

    func isFresh(at now: Date = Date()) -> Bool {
        guard isCurrent(at: now), let observedAt, let resetsAt else { return false }
        return now.timeIntervalSince(observedAt) <= resetsAt.timeIntervalSince(now)
    }

    func share(at now: Date = Date()) -> Double? {
        guard isCurrent(at: now), let used else { return nil }
        return min(max(used / 100, 0), 1)
    }

    func pace(at now: Date = Date()) -> Double? {
        guard isCurrent(at: now), let resetsAt, let duration, duration > 0 else { return nil }
        return min(max(1 - resetsAt.timeIntervalSince(now) / duration, 0), 1)
    }

    func percentageText(at now: Date = Date()) -> String {
        guard isCurrent(at: now), let used else { return "--" }
        return String(format: "%.0f%%", locale: .current, used)
    }

    func resetLine(at now: Date = Date()) -> String? {
        guard isCurrent(at: now), let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let minutes = max(1, Int(remaining / 60))
        let days = minutes / (24 * 60)
        let hours = minutes % (24 * 60) / 60
        let remainder = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(remainder)m"
    }

    func verdictLine(at now: Date = Date()) -> String? {
        guard isCurrent(at: now), let used, let pace = pace(at: now) else { return nil }
        let delta = Int(abs((used - pace * 100).rounded()))
        if delta == 0 { return "on pace" }
        let direction = used >= pace * 100 ? "over" : "under"
        return "\(delta)% \(direction) pace"
    }

    static func empty(_ label: String, provider: Provider, duration: TimeInterval? = nil) -> UsageReading {
        UsageReading(label: label, provider: provider, duration: duration, used: nil,
                     resetsAt: nil, observedAt: nil, stateIsOK: false)
    }
}

@MainActor
final class UsagePoller {
    private let onReadings: ([UsageReading]) -> Void
    private var claudeTimer: Timer?
    private var feedTimer: Timer?
    private var claudeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var claudeReadings: [UsageReading]
    private var feedReadings: [UsageReading] = []

    private static let emptyClaude = [
        UsageReading.empty("Claude 5h", provider: .claude, duration: 5 * 3600),
        UsageReading.empty("Claude", provider: .claude, duration: 7 * 86400)
    ]

    init(onReadings: @escaping ([UsageReading]) -> Void) {
        self.onReadings = onReadings
        claudeReadings = Self.emptyClaude
    }

    func start() {
        publish()
        fetchClaude()
        fetchFeed()
    }

    private func fetchClaude() {
        guard claudeTask == nil else { return }
        claudeTask = Task {
            let result = await UsageClient.fetchClaude()
            claudeTask = nil
            switch result {
            case .readings(let readings):
                claudeReadings = readings
            case .unavailable:
                // ponytail: reader scans only the newest 400 cache entries, so a fresh launch after long idle can start blank until Claude is used.
                break
            }
            publish()
            claudeTimer?.invalidate()
            claudeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fetchClaude() }
            }
        }
    }

    private func fetchFeed() {
        guard feedTask == nil else { return }
        feedTask = Task {
            if let url = UsageClient.feedURL {
                if let accounts = await UsageClient.fetchFeed(from: url) {
                    feedReadings = UsageClient.codexReadings(from: accounts)
                        + [UsageClient.grokReading(from: accounts)]
                } else {
                    feedReadings = [UsageReading.empty("Codex", provider: .codex),
                                    UsageReading.empty("Grok", provider: .grok, duration: 7 * 86400)]
                }
            } else {
                feedReadings = []
            }
            feedTask = nil
            publish()
            feedTimer?.invalidate()
            feedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fetchFeed() }
            }
        }
    }

    private func publish() {
        onReadings(claudeReadings + feedReadings)
    }
}

private enum UsageClient {
    enum ClaudeResult {
        case readings([UsageReading])
        case unavailable
    }

    /// Optional Codex and Grok feed, set with `defaults write com.dhrlabs.dockside UsageFeedURL <url>`.
    static var feedURL: URL? {
        guard let text = UserDefaults.standard.string(forKey: "UsageFeedURL"),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func fetchClaude() async -> ClaudeResult {
        let scan = await Task.detached(priority: .utility) {
            ClaudeDesktopUsageCache().read()
        }.value
        guard let cached = scan.reading else { return .unavailable }
        return .readings([
            claudeReading(cached.response.fiveHour, label: "Claude 5h",
                          duration: 5 * 3600, observedAt: cached.savedAt),
            claudeReading(cached.response.sevenDay, label: "Claude",
                          duration: 7 * 86400, observedAt: cached.savedAt)
        ])
    }

    static func fetchFeed(from url: URL) async -> [FeedAccount]? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let feed = try? JSONDecoder().decode(UsageFeed.self, from: data)
        else { return nil }
        return feed.accounts
    }

    static func codexReadings(from accounts: [FeedAccount]) -> [UsageReading] {
        guard let account = accounts.first(where: { $0.name == "Codex" }) else {
            return [UsageReading.empty("Codex", provider: .codex)]
        }
        let observedAt = parseDate(account.at)
        let windows = (account.windows ?? []).compactMap { window -> (FeedWindow, TimeInterval)? in
            switch window.label {
            case "5 hours": return (window, 5 * 3600)
            case "week": return (window, 7 * 86400)
            default: return nil
            }
        }.sorted { $0.0.label == "5 hours" && $1.0.label != "5 hours" }

        guard !windows.isEmpty else {
            return [UsageReading.empty("Codex", provider: .codex)]
        }
        return windows.map { window, duration in
            let label = window.label == "5 hours" ? "Codex 5h" : "Codex"
            return UsageReading(label: label, provider: .codex,
                         duration: duration, used: window.used.map(Double.init),
                         resetsAt: parseDate(window.resetsAt), observedAt: observedAt,
                         stateIsOK: account.state == "ok")
        }
    }

    static func grokReading(from accounts: [FeedAccount]) -> UsageReading {
        guard let account = accounts.first(where: { $0.name == "Grok" }),
              let window = account.windows?.first(where: { $0.label == "week" })
        else { return .empty("Grok", provider: .grok, duration: 7 * 86400) }
        return UsageReading(label: "Grok", provider: .grok, duration: 7 * 86400,
                            used: window.used.map(Double.init), resetsAt: parseDate(window.resetsAt),
                            observedAt: parseDate(account.at), stateIsOK: account.state == "ok")
    }

    private static func claudeReading(
        _ window: ClaudeWindow?, label: String, duration: TimeInterval, observedAt: Date
    ) -> UsageReading {
        guard let window else { return .empty(label, provider: .claude, duration: duration) }
        return UsageReading(label: label, provider: .claude, duration: duration,
                            used: window.utilization, resetsAt: parseDate(window.resetsAt),
                            observedAt: observedAt, stateIsOK: true)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: value) ?? plain.date(from: value)
    }
}

private struct UsageFeed: Decodable {
    let accounts: [FeedAccount]?
}

struct FeedAccount: Decodable {
    let name: String?
    let state: String?
    let at: String?
    let windows: [FeedWindow]?
}

struct FeedWindow: Decodable {
    let label: String?
    let used: Int?
    let resetsAt: String?
}
