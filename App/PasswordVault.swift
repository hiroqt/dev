import Foundation
import Security
import LocalAuthentication

struct PasswordEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var service: String
    var username: String
    var password: String

    var isValid: Bool {
        !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

enum PasswordVaultError: LocalizedError {
    case keychain(OSStatus)
    case invalidEntry

    var errorDescription: String? {
        switch self {
        case .keychain(let status) where status == errSecMissingEntitlement:
            "Password vault requires an app signed with valid Keychain entitlements. Configure signing in Xcode before saving passwords."
        case .keychain(let status):
            status == errSecUserCanceled ? "Unlock cancelled. Your vault remains locked." :
                "macOS could not access the password vault (\(status)). Your saved data has been preserved."
        case .invalidEntry: "Enter a service, username and password."
        }
    }
}

protocol PasswordVaultAccess: Sendable {
    func unlock() async throws -> [PasswordEntry]
    func save(_ entries: [PasswordEntry]) async throws
    func lock() async
}

// A separate actor keeps blocking Keychain authentication off the main actor.
actor PasswordVault: PasswordVaultAccess {
    private var context: LAContext?
    private let service = "com.arnel.dev.password-vault.v1"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "vault",
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    func unlock() throws -> [PasswordEntry] {
        context?.invalidate()
        let authentication = LAContext()
        authentication.localizedReason = "Unlock your dev password manager with your Mac password."
        context = authentication
        do {
            var read = query
            read[kSecReturnData as String] = true
            read[kSecMatchLimit as String] = kSecMatchLimitOne
            read[kSecUseAuthenticationContext as String] = authentication
            var result: CFTypeRef?
            var status = SecItemCopyMatching(read as CFDictionary, &result)
            if status == errSecItemNotFound {
                var error: Unmanaged<CFError>?
                guard let access = SecAccessControlCreateWithFlags(nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .devicePasscode, &error) else {
                    throw PasswordVaultError.keychain(errSecNotAvailable)
                }
                var create = query
                create[kSecAttrAccessControl as String] = access
                create[kSecValueData as String] = try JSONEncoder().encode([PasswordEntry]())
                let added = SecItemAdd(create as CFDictionary, nil)
                guard added == errSecSuccess || added == errSecDuplicateItem else {
                    throw PasswordVaultError.keychain(added)
                }
                status = SecItemCopyMatching(read as CFDictionary, &result)
            }
            guard status == errSecSuccess, let data = result as? Data else {
                throw PasswordVaultError.keychain(status)
            }
            return try JSONDecoder().decode([PasswordEntry].self, from: data)
        } catch {
            authentication.invalidate()
            context = nil
            throw error
        }
    }

    func save(_ entries: [PasswordEntry]) throws {
        guard let context else { throw PasswordVaultError.keychain(errSecAuthFailed) }
        guard entries.allSatisfy(\.isValid) else { throw PasswordVaultError.invalidEntry }
        var update = query
        update[kSecUseAuthenticationContext as String] = context
        let status = SecItemUpdate(update as CFDictionary,
            [kSecValueData as String: try JSONEncoder().encode(entries)] as CFDictionary)
        guard status == errSecSuccess else { throw PasswordVaultError.keychain(status) }
    }

    func lock() {
        context?.invalidate()
        context = nil
    }
}
