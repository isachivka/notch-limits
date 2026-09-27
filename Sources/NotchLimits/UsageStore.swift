import Foundation
import NotchLimitsCore
import Observation

@MainActor @Observable
final class UsageStore {
    var claude: ProviderStatus = .loading
    var codex: ProviderStatus = .loading
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Called when the notch opens: refresh unless the data is fresh.
    func refreshIfStale() {
        guard let last = lastRefresh, Date().timeIntervalSince(last) < 30 else { return refresh() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            async let c = ClaudeClient.fetch()
            async let x = CodexClient.fetch()
            let (claudeResult, codexResult) = await (c, x)
            claude = claude.applying(claudeResult)
            codex = codex.applying(codexResult)
            lastRefresh = Date()
            isRefreshing = false
        }
    }

    var visible: [(ProviderKind, ProviderStatus)] {
        [(.claude, claude), (.codex, codex)].filter { $0.1 != .notConfigured }
    }
}
