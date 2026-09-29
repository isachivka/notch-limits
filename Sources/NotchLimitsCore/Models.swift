import Foundation

public enum ProviderKind: String, Sendable, CaseIterable, Codable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// One rate-limit window, e.g. "5h" or "Week".
public struct UsageWindow: Equatable, Sendable, Identifiable, Codable {
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

public struct ProviderSnapshot: Equatable, Sendable, Codable {
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
    /// Worth retrying later (429, 5xx, offline); says nothing about the numbers.
    case unavailable(reason: String, retryAfter: TimeInterval?)
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
        // A transient outage says nothing about the numbers: keep showing them.
        case .unavailable(let reason, _): snapshot == nil ? .failed(message: reason, last: nil) : self
        }
    }
}

public enum UsageError: Error, Equatable {
    case badResponse
    case http(Int)
    case transient(reason: String, retryAfter: TimeInterval?)
}
