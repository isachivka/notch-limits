import Foundation

public enum ProviderKind: String, Sendable, CaseIterable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// One rate-limit window, e.g. "5h" or "Week".
public struct UsageWindow: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    /// 0...100
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ProviderSnapshot: Equatable, Sendable {
    public let kind: ProviderKind
    public let plan: String?
    public let windows: [UsageWindow]
    public let fetchedAt: Date

    public init(kind: ProviderKind, plan: String?, windows: [UsageWindow], fetchedAt: Date) {
        self.kind = kind
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
    }
}

/// Outcome of a single fetch.
public enum FetchResult: Sendable {
    case notConfigured
    case ok(ProviderSnapshot)
    case failed(String)
    /// HTTP 429; `retryAfter` from the Retry-After header when present.
    case rateLimited(retryAfter: TimeInterval?)
}

/// What the UI shows for a provider. A failed fetch keeps the last good snapshot.
public enum ProviderStatus: Equatable, Sendable {
    case notConfigured
    case loading
    case ok(ProviderSnapshot)
    case failed(message: String, last: ProviderSnapshot?)

    public var snapshot: ProviderSnapshot? {
        switch self {
        case .ok(let s): s
        case .failed(_, let last): last
        default: nil
        }
    }

    public func applying(_ result: FetchResult) -> ProviderStatus {
        switch result {
        case .notConfigured: .notConfigured
        case .ok(let s): .ok(s)
        case .failed(let message): .failed(message: message, last: snapshot)
        // Throttling says nothing about the numbers: keep showing them.
        case .rateLimited: snapshot == nil ? .failed(message: "Rate limited", last: nil) : self
        }
    }
}

public enum UsageError: Error, Equatable {
    case badResponse
    case http(Int)
    case rateLimited(retryAfter: TimeInterval?)
}
