import Foundation

enum ProviderIntegrationPreferences {
    static func globalKey(_ provider: CodingProvider) -> String { "providerIntegration.\(provider.rawValue).enabled" }
    static func projectKey(_ provider: CodingProvider, projectID: String) -> String {
        "providerIntegration.\(provider.rawValue).project.\(projectID).enabled"
    }
    static func planKey(_ provider: CodingProvider) -> String { "providerIntegration.\(provider.rawValue).plan" }

    static func isEnabled(_ provider: CodingProvider, projectID: String? = nil, defaults: UserDefaults = .standard) -> Bool {
        let key = projectID.map { projectKey(provider, projectID: $0) } ?? globalKey(provider)
        guard defaults.object(forKey: key) != nil else { return projectID == nil ? provider.defaultEnabled : true }
        return defaults.bool(forKey: key)
    }
}
