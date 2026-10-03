import Foundation
import LocalAuthentication
import Combine
import Security

enum AuthState {
    case locked
    case authenticated
    case biometricUnavailable
}

@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var authState: AuthState = .locked
    @Published var authError: String?
    @Published var biometricType: LABiometryType = .none
    @Published var isPINSetup: Bool = false

    private let context = LAContext()
    private let pinKeychainKey = "com.personalfinance.app.pin"

    private init() {
        detectBiometricType()
        isPINSetup = loadPINFromKeychain() != nil
    }

    // MARK: - Biometric Detection

    private func detectBiometricType() {
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricType = available ? context.biometryType : .none
    }

    var biometricLabel: String {
        switch biometricType {
        case .faceID:   return "Face ID"
        case .touchID:  return "Touch ID"
        case .opticID:  return "Optic ID"
        default:        return "Biometrics"
        }
    }

    var biometricIcon: String {
        switch biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "lock.fill"
        }
    }

    // MARK: - Authentication

    func authenticate() async {
        authError = nil
        let ctx = LAContext()
        var error: NSError?

        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                let success = try await ctx.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Unlock your Finance app"
                )
                if success {
                    authState = .authenticated
                }
            } catch let laError as LAError {
                handleBiometricError(laError)
            } catch {
                authError = error.localizedDescription
            }
        } else {
            // No biometrics — fall through to PIN if set up
            if isPINSetup {
                authState = .biometricUnavailable
            } else {
                authState = .authenticated
            }
        }
    }

    private func handleBiometricError(_ error: LAError) {
        switch error.code {
        case .userCancel, .appCancel:
            break
        case .userFallback, .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled:
            authState = isPINSetup ? .biometricUnavailable : .locked
            authError = isPINSetup ? "Use your PIN to unlock." : error.localizedDescription
        default:
            authError = error.localizedDescription
        }
    }

    func lock() {
        authState = .locked
    }

    // MARK: - PIN

    func setupPIN(_ pin: String) -> Bool {
        return savePINToKeychain(pin)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = loadPINFromKeychain() else { return false }
        let isCorrect = stored == pin
        if isCorrect { authState = .authenticated }
        return isCorrect
    }

    func removePIN() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKeychainKey
        ]
        SecItemDelete(query as CFDictionary)
        isPINSetup = false
    }

    // MARK: - Keychain helpers

    private func savePINToKeychain(_ pin: String) -> Bool {
        guard let data = pin.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      pinKeychainKey,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { isPINSetup = true }
        return status == errSecSuccess
    }

    private func loadPINFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: pinKeychainKey,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
