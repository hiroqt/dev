import Foundation
import Security

protocol GitHubTokenStoring: Sendable {
    func load() throws -> GitHubToken?
    func save(_ token: GitHubToken) throws
    func delete() throws
}

struct KeychainGitHubTokenStore: GitHubTokenStoring {
    private let service = "com.arnel.dev.github"
    private let account = "user-access-token"

    func load() throws -> GitHubToken? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GitHubBackendError.keychainStatus(status)
        }
        do {
            return try JSONDecoder().decode(GitHubToken.self, from: data)
        } catch {
            throw GitHubBackendError.invalidResponse
        }
    }

    func save(_ token: GitHubToken) throws {
        let data = try JSONEncoder().encode(token)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw GitHubBackendError.keychainStatus(status) }
        } else if update != errSecSuccess {
            throw GitHubBackendError.keychainStatus(update)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubBackendError.keychainStatus(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
