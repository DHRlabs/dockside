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
        guard stateIsOK, let used, used.isFinite, resetsAt != nil,
              let observedAt else { return false }
        return now.timeIntervalSince(observedAt) <= 15 * 60
    }

    func share(at now: Date = Date()) -> Double? {
        guard isCurrent(at: now), let used else { return nil }
        return min(max(used / 100, 0), 1)
    }

    func pace(at now: Date = Date()) -> Double? {
        guard isCurrent(at: now), let resetsAt, let duration, duration > 0 else { return nil }
        return min(max(1 - resetsAt.timeIntervalSince(now) / duration, 0), 1)
    }

    var tooltipLine: String {
        guard isCurrent(), let used, let resetsAt else { return "\(label): no reading" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let percentage = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), used)
        return "\(label): \(percentage)% used, resets \(formatter.string(from: resetsAt))"
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
    private var codexReadings = [UsageReading.empty("Codex", provider: .codex)]
    private var grokReading = UsageReading.empty("Grok week", provider: .grok, duration: 7 * 86400)

    private static let emptyClaude = [
        UsageReading.empty("Claude 5 hours", provider: .claude, duration: 5 * 3600),
        UsageReading.empty("Claude week", provider: .claude, duration: 7 * 86400)
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
                claudeReadings = Self.emptyClaude
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
            if let accounts = await UsageClient.fetchFeed() {
                codexReadings = UsageClient.codexReadings(from: accounts)
                grokReading = UsageClient.grokReading(from: accounts)
            } else {
                codexReadings = [UsageReading.empty("Codex", provider: .codex)]
                grokReading = UsageReading.empty("Grok week", provider: .grok, duration: 7 * 86400)
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
        onReadings(claudeReadings + codexReadings + [grokReading])
    }
}

private enum UsageClient {
    enum ClaudeResult {
        case readings([UsageReading])
        case unavailable
    }

    private static let feedEndpoint = URL(string: "https://crons.dhrlabs.com/api/account-usage.json")!

    static func fetchClaude() async -> ClaudeResult {
        let scan = await Task.detached(priority: .utility) {
            ClaudeDesktopUsageCache().read()
        }.value
        guard let cached = scan.reading else { return .unavailable }
        return .readings([
            claudeReading(cached.response.fiveHour, label: "Claude 5 hours",
                          duration: 5 * 3600, observedAt: cached.savedAt),
            claudeReading(cached.response.sevenDay, label: "Claude week",
                          duration: 7 * 86400, observedAt: cached.savedAt)
        ])
    }

    static func fetchFeed() async -> [FeedAccount]? {
        guard let (data, response) = try? await URLSession.shared.data(from: feedEndpoint),
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
            UsageReading(label: "Codex \(window.label ?? "")", provider: .codex,
                         duration: duration, used: window.used.map(Double.init),
                         resetsAt: parseDate(window.resetsAt), observedAt: observedAt,
                         stateIsOK: account.state == "ok")
        }
    }

    static func grokReading(from accounts: [FeedAccount]) -> UsageReading {
        guard let account = accounts.first(where: { $0.name == "Grok" }),
              let window = account.windows?.first(where: { $0.label == "week" })
        else { return .empty("Grok week", provider: .grok, duration: 7 * 86400) }
        return UsageReading(label: "Grok week", provider: .grok, duration: 7 * 86400,
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

    enum CodingKeys: String, CodingKey {
        case label, used
        case resetsAt = "resetsAt"
    }
}
