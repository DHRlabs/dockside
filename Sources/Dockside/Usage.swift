import Foundation

struct UsageReading {
    enum Provider {
        case claude
        case codex
        /// Any other feed account; `colorHex` is the optional "#RRGGBB" the feed gave it.
        case feed(colorHex: String?)
    }

    let label: String
    let provider: Provider
    let duration: TimeInterval?
    let used: Double?
    let resetsAt: Date?
    let observedAt: Date?
    let stateIsOK: Bool
    /// Rows the hover card keeps and the bubble row and compact view skip.
    let hoverOnly: Bool

    init(label: String, provider: Provider, duration: TimeInterval?, used: Double?,
         resetsAt: Date?, observedAt: Date?, stateIsOK: Bool, hoverOnly: Bool = false) {
        self.label = label
        self.provider = provider
        self.duration = duration
        self.used = used
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.stateIsOK = stateIsOK
        self.hoverOnly = hoverOnly
    }

    func isCurrent(at now: Date = Date()) -> Bool {
        guard stateIsOK, let used, used.isFinite, let resetsAt, resetsAt > now,
              observedAt != nil else { return false }
        return true
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
                let names = UsageClient.feedAccountNames
                if let accounts = await UsageClient.fetchFeed(from: url) {
                    feedReadings = UsageClient.feedReadings(from: accounts, names: names)
                } else {
                    feedReadings = UsageClient.feedReadings(from: [], names: names)
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

    /// Optional Codex feed, set with `defaults write com.dhrlabs.dockside UsageFeedURL <url>`.
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
        // Accounts without a five-hour limit (Max) send no five_hour window; show no 5h meter for them.
        var readings: [UsageReading] = []
        if let fiveHour = cached.response.fiveHour {
            readings.append(claudeReading(fiveHour, label: "Claude 5h",
                                          duration: 5 * 3600, observedAt: cached.savedAt))
        }
        readings.append(claudeReading(cached.response.sevenDay, label: "Claude",
                                      duration: 7 * 86400, observedAt: cached.savedAt))
        if let fable = fableReading(from: cached.response.limits, observedAt: cached.savedAt) {
            readings.append(fable)
        }
        return .readings(readings)
    }

    /// The weekly limit scoped to Fable, when the payload carries one with a number and a date.
    static func fableReading(from limits: [ClaudeLimit]?, observedAt: Date) -> UsageReading? {
        guard let limit = (limits ?? []).first(where: {
            $0.kind == "weekly_scoped" && $0.scope?.model?.displayName == "Fable"
        }), let percent = limit.percent, percent.isFinite,
              let resetsAt = parseDate(limit.resetsAt) else { return nil }
        return UsageReading(label: "Claude Fable", provider: .claude, duration: 7 * 86400,
                            used: percent, resetsAt: resetsAt, observedAt: observedAt,
                            stateIsOK: true, hoverOnly: true)
    }

    static func fetchFeed(from url: URL) async -> [FeedAccount]? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let feed = try? JSONDecoder().decode(UsageFeed.self, from: data)
        else { return nil }
        return feed.accounts
    }

    /// Feed accounts to show, in order, from `defaults write com.dhrlabs.dockside UsageFeedAccounts "Codex,Work"`.
    static var feedAccountNames: [String] {
        accountNames(from: UserDefaults.standard.string(forKey: "UsageFeedAccounts"))
    }

    static func accountNames(from text: String?) -> [String] {
        let names = (text ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? ["Codex"] : names
    }

    static func feedReadings(from accounts: [FeedAccount], names: [String]) -> [UsageReading] {
        names.flatMap { readings(from: accounts, name: $0) }
    }

    private static func readings(from accounts: [FeedAccount], name: String) -> [UsageReading] {
        let provider: UsageReading.Provider = name == "Codex"
            ? .codex : .feed(colorHex: accounts.first(where: { $0.name == name })?.color)
        guard let account = accounts.first(where: { $0.name == name }) else {
            return [UsageReading.empty(name, provider: provider)]
        }
        let observedAt = parseDate(account.at)
        let windows = (account.windows ?? []).compactMap { window -> (FeedWindow, TimeInterval, Int)? in
            switch window.label {
            case "5 hours": return (window, 5 * 3600, 0)
            case "week": return (window, 7 * 86400, 1)
            // The Fable weekly window rides along for the hover card only.
            case "Fable": return (window, 7 * 86400, 2)
            default: return nil
            }
        }.sorted { $0.2 < $1.2 }

        let rows = windows.map { window, duration, order -> UsageReading in
            let label: String
            switch order {
            case 0: label = "\(name) 5h"
            case 2: label = "\(name) Fable"
            default: label = name
            }
            return UsageReading(label: label, provider: provider,
                         duration: duration, used: window.used.map(Double.init),
                         resetsAt: parseDate(window.resetsAt), observedAt: observedAt,
                         stateIsOK: account.state == "ok", hoverOnly: order == 2)
        }
        // A Fable window never takes the place of a reading the account would show
        // without it: with no five-hour and no weekly window the account keeps its
        // one empty meter, and the Fable row follows it in the hover card only.
        guard rows.contains(where: { !$0.hoverOnly }) else {
            return [UsageReading.empty(name, provider: provider)] + rows
        }
        return rows
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
    /// Optional "#RRGGBB" meter color for accounts other than Codex.
    /// A color that is not a string decodes as absent so one odd account
    /// never keeps the rest of the feed from decoding.
    let color: String?
    let windows: [FeedWindow]?

    private enum CodingKeys: String, CodingKey {
        case name, state, at, color, windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        color = try? container.decodeIfPresent(String.self, forKey: .color)
        windows = try container.decodeIfPresent([FeedWindow].self, forKey: .windows)
    }
}

struct FeedWindow: Decodable {
    let label: String?
    let used: Int?
    let resetsAt: String?
}
