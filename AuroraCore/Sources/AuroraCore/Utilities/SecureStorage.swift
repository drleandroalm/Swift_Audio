//
//  SecureStorage.swift
//
//
//  Created by Dan Murrell Jr on 9/1/24.
//

import Foundation

#if canImport(Security)
import Security

/// `SecureStorage` is responsible for securely saving, retrieving, and deleting API keys and base URLs using the Keychain on Apple devices.
/// This is useful for storing sensitive information like API keys and custom base URLs in a secure and persistent manner.
public class SecureStorage {
    /// Saves an API key to the secure storage (Keychain) for a specific service.
    ///
    /// - Parameters:
    ///    - key: The API key to be saved.
    ///    - serviceName: The name of the service associated with the API key (e.g., "OpenAI", "Anthropic", "Ollama").
    ///
    /// - Returns: A boolean indicating whether the key was saved successfully.
    @discardableResult
    public static func saveAPIKey(_ key: String, for serviceName: String) -> Bool {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_apiKey",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        // Remove any existing key for the service before saving the new one
        SecItemDelete(query as CFDictionary)
        // Add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to add item to Keychain. Status: \(status)")
        }
        return status == errSecSuccess
    }

    /// Retrieves an API key from the secure storage (Keychain) for a specific service.
    ///
    /// - Parameter serviceName: The name of the service for which the API key is retrieved.
    ///
    /// - Returns: The API key as a string, or `nil` if the key is not found.
    public static func getAPIKey(for serviceName: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_apiKey",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }

    /// Deletes an API key from the secure storage (Keychain) for a specific service.
    ///
    /// - Parameter serviceName: The name of the service whose API key should be deleted.
    public static func deleteAPIKey(for serviceName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_apiKey",
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Saves the base URL to the secure storage (Keychain) for a specific service.
    ///
    /// - Parameters:
    ///    - url: The base URL to be saved.
    ///    - serviceName: The name of the service associated with the base URL (e.g., "Ollama").
    ///
    /// - Returns: A boolean indicating whether the base URL was saved successfully.
    @discardableResult
    public static func saveBaseURL(_ url: String, for serviceName: String) -> Bool {
        let data = Data(url.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_baseURL",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        // Remove any existing base URL for the service before saving the new one
        SecItemDelete(query as CFDictionary)
        // Add the new base URL
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the base URL from the secure storage (Keychain) for a specific service.
    ///
    /// - Parameter serviceName: The name of the service for which the base URL is retrieved.
    ///
    /// - Returns: The base URL as a string, or `nil` if the base URL is not found.
    public static func getBaseURL(for serviceName: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_baseURL",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }

    /// Deletes the base URL from the secure storage (Keychain) for a specific service.
    ///
    /// - Parameter serviceName: The name of the service whose base URL should be deleted.
    public static func deleteBaseURL(for serviceName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: serviceName + "_baseURL",
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Clears all API keys and base URLs from the secure storage (Keychain).
    ///
    /// This method removes all entries saved by the app in the Keychain. Use with caution as this may affect multiple services.
    ///
    /// - Note: This is an optional method that can be used for testing or when you need to reset stored keys.
    public static func clearAll(for serviceName: String) {
        deleteAPIKey(for: serviceName)
        deleteBaseURL(for: serviceName)
    }
}
#else

/// Linux-compatible fallback implementation that mirrors the Keychain-based
/// API surface while storing secrets in-memory during the process lifetime.
/// This allows the Swift Package tests to execute on non-Apple platforms where
/// the Security framework is unavailable. Values are guarded by a serial queue
/// to keep access thread-safe, which matches the semantics used by the
/// Keychain-backed implementation.
public class SecureStorage {
    private static var storage: [String: String] = [:]
    private static let queue = DispatchQueue(label: "com.mutantsoup.AuroraCore.secureStorage")

    private static func apiKeyIdentifier(for serviceName: String) -> String {
        "\(serviceName)_apiKey"
    }

    private static func baseURLIdentifier(for serviceName: String) -> String {
        "\(serviceName)_baseURL"
    }

    @discardableResult
    public static func saveAPIKey(_ key: String, for serviceName: String) -> Bool {
        queue.sync { storage[apiKeyIdentifier(for: serviceName)] = key }
        return true
    }

    public static func getAPIKey(for serviceName: String) -> String? {
        queue.sync { storage[apiKeyIdentifier(for: serviceName)] }
    }

    public static func deleteAPIKey(for serviceName: String) {
        queue.sync { _ = storage.removeValue(forKey: apiKeyIdentifier(for: serviceName)) }
    }

    @discardableResult
    public static func saveBaseURL(_ url: String, for serviceName: String) -> Bool {
        queue.sync { storage[baseURLIdentifier(for: serviceName)] = url }
        return true
    }

    public static func getBaseURL(for serviceName: String) -> String? {
        queue.sync { storage[baseURLIdentifier(for: serviceName)] }
    }

    public static func deleteBaseURL(for serviceName: String) {
        queue.sync { _ = storage.removeValue(forKey: baseURLIdentifier(for: serviceName)) }
    }

    public static func clearAll(for serviceName: String) {
        queue.sync {
            _ = storage.removeValue(forKey: apiKeyIdentifier(for: serviceName))
            _ = storage.removeValue(forKey: baseURLIdentifier(for: serviceName))
        }
    }
}
#endif
