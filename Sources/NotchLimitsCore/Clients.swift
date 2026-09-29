import Foundation

/// Reads credentials Claude Code / Codex already store on this Mac and asks
/// their usage endpoints. Read-only: tokens are never refreshed here, because
/// refreshing rotates the refresh token and would log the CLI out.
public enum ClaudeClient {
    static let keychainService = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let plan: String?
        let expiresAt: Date?
    }

    public static func fetch() async -> FetchResult {
        guard let creds = loadCredentials() else { return .notConfigured }
        if let expiry = creds.expiresAt, expiry < Date() {
            return .failed("Token expired — run claude once")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15
        do {
            let data = try await HTTP.get(request)
            return .ok(try ClaudeUsageParser.parse(data, plan: creds.plan))
        } catch UsageError.rateLimited(let after) {
            return .rateLimited(retryAfter: after)
        } catch {
            return .failed(HTTP.describe(error, cli: "claude"))
        }
    }

    /// Goes through /usr/bin/security: it is on the item's ACL, so the user
    /// is never prompted, even after the app is rebuilt with a new signature.
    static func loadCredentials() -> Credentials? {
        guard let raw = Shell.run("/usr/bin/security",
                                  ["find-generic-password", "-s", keychainService, "-w"]),
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let plan = ClaudeUsageParser.planName(
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
        return Credentials(accessToken: token, plan: plan, expiresAt: expiresAt)
    }
}

public enum CodexClient {
    public static func fetch() async -> FetchResult {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex")
        let path = (home as NSString).appendingPathComponent("auth.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            return .notConfigured
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let account = tokens["account_id"] as? String {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let data = try await HTTP.get(request)
            return .ok(try CodexUsageParser.parse(data))
        } catch UsageError.rateLimited(let after) {
            return .rateLimited(retryAfter: after)
        } catch {
            return .failed(HTTP.describe(error, cli: "codex"))
        }
    }
}

enum HTTP {
    static func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        if http.statusCode == 429 {
            let after = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: after)
        }
        guard (200..<300).contains(http.statusCode) else { throw UsageError.http(http.statusCode) }
        return data
    }

    static func describe(_ error: Error, cli: String) -> String {
        switch error {
        case UsageError.http(401), UsageError.http(403): "Signed out — run \(cli) once"
        case UsageError.http(let code): "HTTP \(code)"
        case UsageError.badResponse: "Unexpected response"
        default: "Offline"
        }
    }
}

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
