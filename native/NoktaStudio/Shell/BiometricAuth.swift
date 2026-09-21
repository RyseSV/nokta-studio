import Foundation
import LocalAuthentication
import Security

/// Wraps Touch ID (Mac) / Face ID or Touch ID (iPhone) via LocalAuthentication.
/// Never touches the account password itself — only gates whether the
/// Keychain-stored credential below can be read back.
enum BiometricAuth {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// `.deviceOwnerAuthentication` (not `...WithBiometrics`) so a Mac/iPhone
    /// passcode still works as a fallback if Touch ID/Face ID fails or isn't
    /// enrolled — same as the system's own "use Touch ID or passcode" prompt.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// Stores the account credential in the system Keychain, protected by an
/// access-control policy that requires the same biometric/passcode check as
/// BiometricAuth.authenticate — the OS itself refuses to return the item
/// without it, not just this code's own logic. Only ever written right after
/// the user typed their own password into LoginView's own SecureField.
enum KeychainCredentialStore {
    private static let service = "com.noktastudio.app.login"
    private static let account = "current-user"

    static func save(username: String, password: String) {
        delete()
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet, .or, .devicePasscode], nil
        ) else { return }
        let payload = try? JSONEncoder().encode(["username": username, "password": password])
        guard let data = payload else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Prompts biometrics/passcode via the Keychain's own access-control
    /// check (kSecUseOperationPrompt), not a separate BiometricAuth call.
    static func load(reason: String) -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: reason,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data),
              let username = decoded["username"], let password = decoded["password"]
        else { return nil }
        return (username, password)
    }

    static var hasStoredCredential: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        // kSecUseAuthenticationUIFail: check existence without prompting —
        // errSecInteractionNotAllowed still means "an item exists".
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
