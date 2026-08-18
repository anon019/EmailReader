import Foundation
import Security

public enum KeychainStoreError: Error, LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain 错误：\(status)"
        }
    }
}

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.sota.EmailReader.oauth.v4") {
        self.service = service
    }

    public func setOAuthBundle(_ bundle: OAuthCredentialBundle) throws {
        let data = try JSONEncoder().encode(bundle)
        guard let value = String(data: data, encoding: .utf8) else { throw KeychainStoreError.status(errSecParam) }
        try set(value, for: "credentials")
    }

    public func oauthBundle() throws -> OAuthCredentialBundle? {
        guard let value = try get("credentials") else { return nil }
        return try JSONDecoder().decode(OAuthCredentialBundle.self, from: Data(value.utf8))
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainStoreError.status(updateStatus) }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStoreError.status(status) }
    }

    public func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainStoreError.status(status) }
    }
}

public struct OAuthCredentialBundle: Codable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public var tokenEndpoint: String
    public let refreshToken: String
    public var accessToken: String
    public var expiresAt: TimeInterval

    public init(clientID: String, clientSecret: String, tokenEndpoint: String, refreshToken: String, accessToken: String, expiresAt: TimeInterval) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.tokenEndpoint = tokenEndpoint
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}
