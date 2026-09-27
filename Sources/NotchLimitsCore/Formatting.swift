import Foundation

public enum UsageLevel: Sendable {
    case calm, warm, hot

    public init(percent: Double) {
        switch percent {
        case ..<60: self = .calm
        case ..<85: self = .warm
        default: self = .hot
        }
    }
}

public enum ResetFormatter {
    /// "3h 12m", "2d 4h", "12m", "<1m".
    public static func string(until date: Date, now: Date = Date()) -> String {
        let total = Int(date.timeIntervalSince(now))
        guard total >= 60 else { return total > 0 ? "<1m" : "now" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// "just now", "2m ago".
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3_600)h ago"
    }
}
