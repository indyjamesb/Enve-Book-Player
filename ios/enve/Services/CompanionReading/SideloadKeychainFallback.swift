#if SIDELOAD_FREE_APPLE_ID
import Foundation
import Security

/// Device-local keychain used when a free Personal Team cannot use the App Group keychain.
/// Compiled only for the Sideload configuration. Debug and Release never include this type.
enum SideloadKeychainFallback {
    private static let service = "com.indyjamesb.enve.sideload"

    static func persist(_ connection: ServerConnection) -> Bool {
        let id = connection.id.uuidString
        var success = true
        if let token = connection.token, !token.isEmpty {
            success = set(token, account: "token.\(id)") && success
        }
        if let password = connection.password, !password.isEmpty {
            success = set(password, account: "password.\(id)") && success
        }
        if let token = connection.plexHomeUserToken, !token.isEmpty {
            success = set(token, account: "plexHome.\(id)") && success
        }
        if let token = connection.plexOwnerToken, !token.isEmpty {
            success = set(token, account: "plexOwner.\(id)") && success
        }
        for headerName in connection.allSecretCustomHeaderNames() {
            guard let value = ServerConnection.headerValue(in: connection.customHeaders, for: headerName), !value.isEmpty else {
                continue
            }
            success = set(value, account: "header.\(id).\(headerName)") && success
        }
        return success
    }

    static func hydrate(_ connection: inout ServerConnection) {
        let id = connection.id.uuidString
        if connection.token?.isEmpty != false, let stored = get(account: "token.\(id)") {
            connection.token = stored
        }
        if connection.password?.isEmpty != false, let stored = get(account: "password.\(id)") {
            connection.password = stored
        }
        if connection.plexHomeUserToken?.isEmpty != false, let stored = get(account: "plexHome.\(id)") {
            connection.plexHomeUserToken = stored
        }
        if connection.plexOwnerToken?.isEmpty != false, let stored = get(account: "plexOwner.\(id)") {
            connection.plexOwnerToken = stored
        }
        var headers = connection.customHeaders ?? [:]
        for headerName in connection.allSecretCustomHeaderNames() where ServerConnection.headerValue(in: headers, for: headerName)?.isEmpty != false {
            guard let stored = get(account: "header.\(id).\(headerName)") else { continue }
            ServerConnection.setHeaderValue(stored, for: headerName, in: &headers)
        }
        connection.customHeaders = headers.isEmpty ? nil : headers
    }

    private static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
#endif
