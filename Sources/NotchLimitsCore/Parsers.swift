import Foundation

/// Parses `GET https://api.anthropic.com/api/oauth/usage`.
public enum ClaudeUsageParser {
    static let knownWindows: [(key: String, label: String)] = [
        ("five_hour", "5h"),
        ("seven_day", "Week"),
        ("seven_day_opus", "Opus week"),
        ("seven_day_sonnet", "Sonnet week"),
    ]

    public static func parse(_ data: Data, plan: String?, now: Date = Date()) throws -> ProviderSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.badResponse
        }
        let windows = knownWindows.compactMap { key, label -> UsageWindow? in
            guard let w = root[key] as? [String: Any],
                  let used = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(
                label: label,
                usedPercent: used,
                resetsAt: (w["resets_at"] as? String).flatMap(DateParsing.iso8601)
            )
        }
        guard !windows.isEmpty else { throw UsageError.badResponse }
        return ProviderSnapshot(kind: .claude, plan: plan, windows: windows, fetchedAt: now)
    }

    /// `subscriptionType` + `rateLimitTier` from the Keychain item → "Max 20x".
    public static func planName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let sub = subscriptionType, !sub.isEmpty else { return nil }
        var name = sub.prefix(1).uppercased() + sub.dropFirst()
        if let tier = rateLimitTier,
           let match = tier.firstMatch(of: /_(\d+x)$/) {
            name += " \(match.1)"
        }
        return name
    }
}

/// Parses `GET https://chatgpt.com/backend-api/wham/usage`.
public enum CodexUsageParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ProviderSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limit"] as? [String: Any] else {
            throw UsageError.badResponse
        }
        let windows = ["primary_window", "secondary_window"].compactMap { key -> UsageWindow? in
            guard let w = limits[key] as? [String: Any],
                  let used = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let seconds = (w["limit_window_seconds"] as? NSNumber)?.intValue ?? 0
            var reset: Date?
            if let at = (w["reset_at"] as? NSNumber)?.doubleValue {
                reset = Date(timeIntervalSince1970: at)
            } else if let after = (w["reset_after_seconds"] as? NSNumber)?.doubleValue {
                reset = now.addingTimeInterval(after)
            }
            return UsageWindow(label: windowLabel(seconds: seconds), usedPercent: used, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw UsageError.badResponse }
        let plan = (root["plan_type"] as? String).map(planName)
        return ProviderSnapshot(kind: .codex, plan: plan, windows: windows, fetchedAt: now)
    }

    public static func windowLabel(seconds: Int) -> String {
        switch seconds {
        case 604_800: "Week"
        case let s where s > 0 && s % 86_400 == 0: "\(s / 86_400)d"
        case let s where s > 0 && s % 3_600 == 0: "\(s / 3_600)h"
        case let s where s > 0: "\(s / 60)m"
        default: "Limit"
        }
    }

    public static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "prolite": "Pro Lite"
        case "pro": "Pro"
        case "plus": "Plus"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case "edu": "Edu"
        case "free": "Free"
        default: raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}

enum DateParsing {
    /// ISO 8601 with or without fractional seconds (Anthropic sends microseconds).
    static func iso8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        let trimmed = string.replacing(/\.\d+/, with: "")
        return formatter.date(from: trimmed)
    }
}
