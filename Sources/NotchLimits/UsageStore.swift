import Foundation
import NotchLimitsCore
import Observation

@MainActor @Observable
final class UsageStore {
    var claude: ProviderStatus = .loading
    var codex: ProviderStatus = .loading
    private(set) var isRefreshing = false
    /// Set after a 429/5xx/offline; no automatic fetch for that provider until then.
    private(set) var paused: [ProviderKind: Pause] = [:]

    struct Pause: Equatable {
        let reason: String
        let until: Date
    }

    /// The usage endpoints are rate limited per account, and every Claude
    /// Code session shares that budget, so poll gently.
    static let pollInterval: TimeInterval = 900
    static let openMaxAge: TimeInterval = 300
    static let minBackoff: TimeInterval = 120
    static let maxBackoff: TimeInterval = 1800

    private var lastAttempt: [ProviderKind: Date] = [:]
    private var backoff: [ProviderKind: TimeInterval] = [:]
    private var timer: Timer?

    init() {
        // Last good numbers survive restarts, so an outage at launch still shows data.
        if let s = Self.cached(.claude) { claude = .ok(s) }
        if let s = Self.cached(.codex) { codex = .ok(s) }
    }

    private static func cacheKey(_ kind: ProviderKind) -> String { "snapshot.\(kind.rawValue)" }

    private static func cached(_ kind: ProviderKind) -> ProviderSnapshot? {
        UserDefaults.standard.data(forKey: cacheKey(kind))
            .flatMap { try? JSONDecoder().decode(ProviderSnapshot.self, from: $0) }
    }

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(maxAge: Self.pollInterval) }
        }
    }

    /// The notch opened.
    func refreshIfStale() {
        refresh(maxAge: Self.openMaxAge)
    }

    /// Refresh button / menu: the user asked, so skip interval and backoff.
    func refresh() {
        refresh(force: true)
    }

    /// Oldest snapshot on screen, for the "updated … ago" label.
    var lastRefresh: Date? {
        visible.compactMap { $0.1.snapshot?.fetchedAt }.min()
    }

    var visible: [(ProviderKind, ProviderStatus)] {
        [(.claude, claude), (.codex, codex)].filter { $0.1 != .notConfigured }
    }

    private func refresh(maxAge: TimeInterval = 0, force: Bool = false) {
        guard !isRefreshing else { return }
        let now = Date()
        let due = ProviderKind.allCases.filter { kind in
            if force { return true }
            if let pause = paused[kind], pause.until > now { return false }
            guard let last = lastAttempt[kind] else { return true }
            return now.timeIntervalSince(last) >= maxAge
        }
        guard !due.isEmpty else { return }
        isRefreshing = true
        Task {
            await withTaskGroup(of: (ProviderKind, FetchResult).self) { group in
                for kind in due {
                    group.addTask {
                        switch kind {
                        case .claude: (kind, await ClaudeClient.fetch())
                        case .codex: (kind, await CodexClient.fetch())
                        }
                    }
                }
                for await (kind, result) in group { apply(result, to: kind) }
            }
            isRefreshing = false
        }
    }

    private func apply(_ result: FetchResult, to kind: ProviderKind) {
        lastAttempt[kind] = Date()
        switch result {
        case .unavailable(let reason, let retryAfter):
            let next = min(Self.maxBackoff, max(retryAfter ?? 0, (backoff[kind] ?? Self.minBackoff / 2) * 2))
            backoff[kind] = next
            paused[kind] = Pause(reason: reason, until: Date().addingTimeInterval(next))
            NSLog("NotchLimits: \(kind.rawValue) \(reason), next try in \(Int(next))s")
        case .ok(let snapshot):
            backoff[kind] = nil
            paused[kind] = nil
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey(kind))
            }
        case .failed(let message):
            NSLog("NotchLimits: \(kind.rawValue) failed: \(message)")
        case .notConfigured:
            UserDefaults.standard.removeObject(forKey: Self.cacheKey(kind))
        }
        switch kind {
        case .claude: claude = claude.applying(result)
        case .codex: codex = codex.applying(result)
        }
    }
}
