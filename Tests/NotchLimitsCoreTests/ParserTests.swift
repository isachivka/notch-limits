import XCTest
@testable import NotchLimitsCore

final class ParserTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testClaudeLimitsArrayIncludesPerModelCap() throws {
        let s = try ClaudeUsageParser.parse(fixture("claude_usage"), plan: "Max 20x")
        XCTAssertEqual(s.windows.map(\.label), ["5h", "Week", "Fable week"])
        XCTAssertEqual(s.windows.map(\.usedPercent), [2, 53, 18])
        XCTAssertNotNil(s.windows[2].resetsAt)
    }

    func testClaudeLegacyWindowsInOrderSkippingNulls() throws {
        let s = try ClaudeUsageParser.parse(fixture("claude_usage_legacy"), plan: "Max 20x")
        XCTAssertEqual(s.windows.map(\.label), ["5h", "Week", "Sonnet week"])
        XCTAssertEqual(s.windows.map(\.usedPercent), [3, 53, 12.5])
        XCTAssertEqual(s.plan, "Max 20x")
    }

    func testClaudeMicrosecondDates() throws {
        let s = try ClaudeUsageParser.parse(fixture("claude_usage_legacy"), plan: nil)
        let reset = try XCTUnwrap(s.windows[0].resetsAt)
        XCTAssertEqual(reset.timeIntervalSince1970, 1_790_541_000, accuracy: 1)
        XCTAssertNotNil(s.windows[2].resetsAt)
    }

    func testClaudeGarbageThrows() {
        XCTAssertThrowsError(try ClaudeUsageParser.parse(Data("{}".utf8), plan: nil))
    }

    func testClaudePlanName() {
        XCTAssertEqual(ClaudeUsageParser.planName(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Max 20x")
        XCTAssertEqual(ClaudeUsageParser.planName(subscriptionType: "pro", rateLimitTier: "default_claude_pro"), "Pro")
        XCTAssertNil(ClaudeUsageParser.planName(subscriptionType: nil, rateLimitTier: nil))
    }

    func testCodexTwoWindows() throws {
        let s = try CodexUsageParser.parse(fixture("codex_usage"))
        XCTAssertEqual(s.windows.map(\.label), ["5h", "Week"])
        XCTAssertEqual(s.windows.map(\.usedPercent), [7, 41])
        XCTAssertEqual(s.windows[0].resetsAt?.timeIntervalSince1970, 1_791_050_768)
        XCTAssertEqual(s.plan, "Pro Lite")
    }

    func testCodexResetAfterFallback() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let s = try CodexUsageParser.parse(fixture("codex_usage"), now: now)
        XCTAssertEqual(s.windows[1].resetsAt, now.addingTimeInterval(526_270))
    }

    func testCodexSingleWindow() throws {
        let s = try CodexUsageParser.parse(fixture("codex_usage_single"))
        XCTAssertEqual(s.windows.map(\.label), ["Week"])
        XCTAssertEqual(s.plan, "Plus")
    }

    func testWindowLabels() {
        XCTAssertEqual(CodexUsageParser.windowLabel(seconds: 18_000), "5h")
        XCTAssertEqual(CodexUsageParser.windowLabel(seconds: 604_800), "Week")
        XCTAssertEqual(CodexUsageParser.windowLabel(seconds: 86_400), "1d")
    }
}

final class SVGPathTests: XCTestCase {
    func testOpenAIIconFillsViewBox() {
        let box = SVGPath.cgPath(BrandIcons.openAI).boundingBoxOfPath
        XCTAssertEqual(box.minX, 0, accuracy: 0.3)
        XCTAssertEqual(box.minY, 0, accuracy: 0.3)
        XCTAssertEqual(box.maxX, 24, accuracy: 0.3)
        XCTAssertEqual(box.maxY, 24, accuracy: 0.3)
    }

    func testArcHalfCircle() {
        let box = SVGPath.cgPath("M0 10 A10 10 0 0 1 20 10").boundingBoxOfPath
        XCTAssertEqual(box.minY, 0, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 20, accuracy: 0.01)
    }
}

final class FormattingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 0)

    func testResetStrings() {
        XCTAssertEqual(ResetFormatter.string(until: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "3h 12m")
        XCTAssertEqual(ResetFormatter.string(until: now.addingTimeInterval(2 * 86400 + 4 * 3600), now: now), "2d 4h")
        XCTAssertEqual(ResetFormatter.string(until: now.addingTimeInterval(12 * 60 + 5), now: now), "12m")
        XCTAssertEqual(ResetFormatter.string(until: now.addingTimeInterval(30), now: now), "<1m")
        XCTAssertEqual(ResetFormatter.string(until: now.addingTimeInterval(-5), now: now), "now")
    }

    func testLevels() {
        XCTAssertEqual(UsageLevel(percent: 10), .calm)
        XCTAssertEqual(UsageLevel(percent: 60), .warm)
        XCTAssertEqual(UsageLevel(percent: 85), .hot)
    }

    func testFailureKeepsLastSnapshot() {
        let snap = ProviderSnapshot(kind: .codex, plan: nil, windows: [], fetchedAt: now)
        let status = ProviderStatus.ok(snap).applying(.failed("Offline"))
        XCTAssertEqual(status, .failed(message: "Offline", last: snap))
        XCTAssertEqual(status.applying(.ok(snap)), .ok(snap))
    }
}
