import Foundation

enum CodingProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case antigravity
    case claude

    var id: String { rawValue }
    var name: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .claude: "Claude"
        }
    }
    var logoAssetName: String {
        switch self {
        case .codex: "CodexMark"
        case .antigravity: "AntigravityMark"
        case .claude: "ClaudeMark"
        }
    }
    var launchCommand: String { rawValue == "antigravity" ? "agy" : rawValue }
    var usageCommand: String { self == .codex ? "/status" : "/usage" }
    var defaultEnabled: Bool { self == .codex }
    var setupURL: URL {
        switch self {
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        case .antigravity: URL(string: "https://antigravity.google/download")!
        case .claude: URL(string: "https://code.claude.com/docs/en/setup")!
        }
    }
    var plans: [String] {
        switch self {
        case .codex: ["Not selected", "Free", "Go", "Plus", "Pro", "Business", "Enterprise", "Edu", "Other"]
        case .antigravity: ["Not selected", "Free", "Google AI Pro", "Google AI Ultra", "Gemini Enterprise", "Other"]
        case .claude: ["Not selected", "Free", "Pro", "Max", "Team", "Enterprise", "Other"]
        }
    }
    var signInStatus: String {
        switch self {
        case .codex: "Unknown until checked in Settings"
        case .antigravity, .claude: "Unknown; verify in CLI"
        }
    }
    var usageGuideURL: URL {
        switch self {
        case .codex: URL(string: "https://help.openai.com/en/articles/20001478-reviewing-work-and-codex-usage-and-using-personal-analytics-in-chatgpt-desktop")!
        case .antigravity: URL(string: "https://antigravity.google/docs/cli/commands/usage?id=GoogleAntigravity")!
        case .claude: URL(string: "https://code.claude.com/docs/en/costs")!
        }
    }
}

enum ProviderSignInState: Equatable {
    case unknown
    case checking
    case connected
}
