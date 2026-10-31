import Foundation

enum ProviderUsageWindow: String, Sendable {
    case fiveHour = "5h"
    case weekly
}

struct ProviderUsageBucket: Equatable, Sendable {
    let name: String
    let window: ProviderUsageWindow
    let remainingPercent: Int
}

struct ProviderUsageGroup: Equatable, Sendable {
    let name: String
    let buckets: [ProviderUsageBucket]
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    let groups: [ProviderUsageGroup]
    let credits: String?
    let planType: String?
    let updatedAt: Date

    static func parseAntigravity(usage: Data, credits: Data?, updatedAt: Date = .now) -> Self? {
        guard
            let quota = try? JSONDecoder().decode(AntigravityUsageEnvelope.self, from: usage),
            quota.status == "SUCCESS",
            quota.numTurns == 0,
            quota.command.name == "usage"
        else { return nil }

        let creditBalance = credits.flatMap { try? JSONDecoder().decode(AntigravityCreditsEnvelope.self, from: $0) }
        let remainingCredits = creditBalance.flatMap {
            $0.status == "SUCCESS" && $0.numTurns == 0 && $0.command.name == "credits"
                ? $0.command.data.remainingCredits
                : nil
        }

        let groups = quota.command.data.groups.compactMap { group -> ProviderUsageGroup? in
            let buckets = group.buckets.compactMap { bucket -> ProviderUsageBucket? in
                guard let window = ProviderUsageWindow(rawValue: bucket.window),
                      bucket.remainingFraction.isFinite else { return nil }
                let percent = bucket.remainingFraction <= 1 ? bucket.remainingFraction * 100 : bucket.remainingFraction
                guard (0...100).contains(percent) else { return nil }
                return ProviderUsageBucket(
                    name: bucket.name,
                    window: window,
                    remainingPercent: Int(percent.rounded())
                )
            }
            return buckets.isEmpty ? nil : ProviderUsageGroup(name: group.name, buckets: buckets)
        }
        guard !groups.isEmpty || remainingCredits != nil else { return nil }
        return ProviderUsageSnapshot(
            groups: groups,
            credits: remainingCredits.map(String.init),
            planType: nil,
            updatedAt: updatedAt
        )
    }

    static func parseCodexRateLimits(_ data: Data, updatedAt: Date = .now) -> Self? {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let result = response["result"] as? [String: Any] ?? response
        guard let rateLimits = result["rateLimits"] as? [String: Any] else { return nil }

        let codexLimits = (result["rateLimitsByLimitId"] as? [String: [String: Any]])?["codex"] ?? rateLimits
        guard codexLimits["limitId"] as? String == nil || codexLimits["limitId"] as? String == "codex" else { return nil }

        let buckets = [codexLimits["primary"], codexLimits["secondary"]].compactMap { value -> ProviderUsageBucket? in
            guard
                let window = value as? [String: Any],
                let duration = window["windowDurationMins"] as? Int,
                let usage = window["usedPercent"] as? Double,
                usage.isFinite,
                (0...100).contains(usage)
            else { return nil }

            let usageWindow: ProviderUsageWindow
            let name: String
            switch duration {
            case 300:
                usageWindow = .fiveHour
                name = "5-hour limit"
            case 10_080:
                usageWindow = .weekly
                name = "Weekly limit"
            default:
                return nil
            }
            return ProviderUsageBucket(name: name, window: usageWindow, remainingPercent: Int((100 - usage).rounded()))
        }

        let credits = codexLimits["credits"] as? [String: Any]
        let creditBalance: String?
        if credits?["unlimited"] as? Bool == true {
            creditBalance = "Unlimited"
        } else if let balance = credits?["balance"] as? String, Decimal(string: balance) != nil {
            creditBalance = balance
        } else {
            creditBalance = nil
        }
        let planType = codexLimits["planType"] as? String ?? rateLimits["planType"] as? String
        guard !buckets.isEmpty || creditBalance != nil || planType != nil else { return nil }
        let groups = buckets.isEmpty ? [] : [ProviderUsageGroup(name: "Codex", buckets: buckets)]
        return ProviderUsageSnapshot(groups: groups, credits: creditBalance, planType: planType, updatedAt: updatedAt)
    }
}

private struct AntigravityUsageEnvelope: Decodable {
    let status: String
    let numTurns: Int
    let command: Command

    enum CodingKeys: String, CodingKey { case status, numTurns = "num_turns", command }
    struct Command: Decodable {
        let name: String
        let data: DataPayload
    }
    struct DataPayload: Decodable { let groups: [Group] }
    struct Group: Decodable {
        let name: String
        let buckets: [Bucket]
    }
    struct Bucket: Decodable {
        let name: String
        let window: String
        let remainingFraction: Double

        enum CodingKeys: String, CodingKey {
            case name, window, remainingFraction = "remaining_fraction"
        }
    }
}

private struct AntigravityCreditsEnvelope: Decodable {
    let status: String
    let numTurns: Int
    let command: Command

    enum CodingKeys: String, CodingKey { case status, numTurns = "num_turns", command }
    struct Command: Decodable {
        let name: String
        let data: DataPayload
    }
    struct DataPayload: Decodable { let remainingCredits: Int?
        enum CodingKeys: String, CodingKey { case remainingCredits = "remaining_credits" }
    }
}
